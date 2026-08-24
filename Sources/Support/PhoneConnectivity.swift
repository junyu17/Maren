import Foundation
import SwiftData
import WatchConnectivity
import WidgetKit

/// 层级 4 · 手机侧的手表连接。把快照推给手表,并接收手表发来的快速记录。
/// 纯设备间通信,不经过任何服务器。
///
/// 设计要点:**收到记录后直接落库,不依赖任何 SwiftUI 视图**。
/// WatchConnectivity 可能在 app 处于后台时投递,那时没有视图在监听;
/// 若把落库挂在视图的 onChange 上,后台送达的记录就会丢。
final class PhoneConnectivity: NSObject, ObservableObject {
    static let shared = PhoneConnectivity()

    /// WatchConnectivity callbacks are not guaranteed to run on the main
    /// actor, while snapshot/reset calls originate from SwiftUI.
    private let stateLock = NSLock()
    private var pendingDrainScheduled = false
    private var pendingDrainRunning = false

    /// The phone journals decoded Watch payloads before touching SwiftData.
    /// Transport delivery and model persistence are separate acknowledgements;
    /// this journal closes that gap when the container is not ready or a save
    /// fails.
    private static let pendingQuickLogsKey = "vela.watch.pending.quicklogs"
    private static let maxPendingQuickLogs = 100
    /// `UserDefaults` serializes individual reads/writes, but a journal
    /// merge is a read-modify-write transaction.  WatchConnectivity may call
    /// the receiver concurrently, so protect the whole transaction with a
    /// process-local lock.  The `Unlocked` helpers below are deliberately
    /// only called while this lock is held; otherwise a merge could recurse
    /// into the lock and deadlock itself.
    private static let pendingQuickLogsLock = NSLock()

    /// Device state (rather than backup data) used to invalidate records that
    /// may still be sitting in a WatchConnectivity queue on the Watch.
    static let resetEpochKey = "vela.reset.epoch"

    struct WatchResetResult: Equatable, Sendable {
        let epoch: Int64
        let epochPersisted: Bool
        let cutoffPersisted: Bool
        let phoneQueueCleared: Bool
        let watchSessionAvailable: Bool

        var cleanupSucceeded: Bool {
            epochPersisted && cutoffPersisted && phoneQueueCleared
        }
    }

    /// 由 App 启动时注入,供收到记录时直接写库。
    @MainActor static var container: ModelContainer?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        schedulePendingDrain()
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// 最近一次快照。会话尚未激活时先存下来,激活完成后补推 ——
    /// 否则 app 启动瞬间「推送」早于「激活完成」,这一次推送会被静默丢弃,手表一直显示占位符。
    private var lastSnapshot: WidgetSnapshot?
    /// Set immediately when this process issues a reset, so the reset marker
    /// is included even when a caller passes a non-standard UserDefaults suite
    /// in tests.  Normal app launches read the persisted standard value.
    private var inMemoryResetEpoch: Int64?

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    static func resetEpoch(from defaults: UserDefaults = .standard) -> Int64? {
        WatchResetGeneration.decode(defaults.object(forKey: resetEpochKey))
    }

    /// Atomically at the app level (all callers are serialized on the app's
    /// main workflow) advance and persist the reset generation before any
    /// payload is sent to the Watch.
    @discardableResult
    static func advanceResetEpoch(in defaults: UserDefaults = .standard) -> Int64 {
        let previousEpoch = resetEpoch(from: defaults) ?? 0
        let nextEpoch = previousEpoch == Int64.max ? Int64.max : previousEpoch + 1
        defaults.set(nextEpoch, forKey: resetEpochKey)
        return nextEpoch
    }

    private var currentResetEpoch: Int64? {
        withStateLock { inMemoryResetEpoch } ?? Self.resetEpoch()
    }

    /// Invalidate queued Watch/Widget quick records after a successful local
    /// destructive operation.  The iPhone cannot delete the Watch's storage,
    /// so it cancels its own outstanding user-info transfers, persists a new
    /// epoch/cutoff, and publishes the epoch over all feasible WC channels.
    /// The caller may use the result to show a retry notice for local cleanup;
    /// a missing Watch session is not itself an error.
    @discardableResult
    func resetWatchState(
        at cutoff: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> WatchResetResult {
        // UserDefaults is persisted before any Watch packet is published.  A
        // maxed-out Int64 is practically unreachable; retaining it is safer
        // than wrapping to zero and accidentally accepting stale generations.
        let epoch = Self.advanceResetEpoch(in: defaults)
        withStateLock { inMemoryResetEpoch = epoch }
        let epochPersisted = Self.resetEpoch(from: defaults) == epoch
        let cutoffPersisted = QuickLogApplier.persistDeleteReplayCutoff(at: cutoff, in: defaults)
        let phoneQueueCleared = QuickActionQueue.clear(from: WidgetSnapshotStore.appGroup)

        // Do this after persisting the marker/cutoff and clearing the local
        // queue.  A new transfer created below therefore carries the new
        // epoch, while any transfer that was already outstanding is stale.
        let session = self.session
        let watchSessionAvailable = session != nil
        if let session {
            session.delegate = self
            for transfer in session.outstandingUserInfoTransfers {
                transfer.cancel()
            }

            withStateLock { lastSnapshot = .placeholder }
            let payload: [String: Any] = [
                WatchKeys.resetEpoch: NSNumber(value: epoch),
                WatchKeys.resetCommand: true
            ]
            if session.activationState == .activated, session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
            // transferUserInfo is the durable path when the Watch is not
            // reachable.  It is intentionally sent even if activation is in
            // progress; WCSession retains it for delivery after activation.
            session.transferUserInfo(payload)
            if let data = try? JSONEncoder().encode(WidgetSnapshot.placeholder) {
                var context = payload
                context[WatchKeys.snapshot] = data
                try? session.updateApplicationContext(context)
            }
            if session.activationState != .activated {
                session.activate()
            }
        } else {
            withStateLock { lastSnapshot = .placeholder }
        }
        return WatchResetResult(epoch: epoch,
                                epochPersisted: epochPersisted,
                                cutoffPersisted: cutoffPersisted,
                                phoneQueueCleared: phoneQueueCleared,
                                watchSessionAvailable: watchSessionAvailable)
    }

    /// 把最新快照推给手表(只保留最新一份,旧的会被覆盖)。
    func push(_ snapshot: WidgetSnapshot) {
        withStateLock { lastSnapshot = snapshot }
        guard let session, session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        var context: [String: Any] = [WatchKeys.snapshot: data]
        if let epoch = currentResetEpoch {
            context[WatchKeys.resetEpoch] = NSNumber(value: epoch)
        }
        try? session.updateApplicationContext(context)
    }

    /// 激活完成后补推一次,填上激活期间错过的快照。
    fileprivate func flushSnapshot() {
        let snapshot = withStateLock { lastSnapshot }
        guard let snapshot else { return }
        push(snapshot)
    }

    /// 统一落库入口。三条通道(sendMessage / transferUserInfo / applicationContext)都走这里。
    /// `QuickLogApplier` 是按 dayKey 的幂等 upsert,所以同一条记录重复到达也不会出问题。
    fileprivate func ingest(_ payload: [String: Any]) {
        // A mismatched epoch is an explicit stale payload.  Older Watch builds
        // do not know this key, so nil remains subject to the receiver-side
        // sentAt cutoff in QuickLogApplier as a compatibility fallback.
        if payload.keys.contains(WatchKeys.resetEpoch) {
            guard let incomingEpoch = WatchResetGeneration.decode(payload[WatchKeys.resetEpoch]) else {
                return
            }
            if let currentEpoch = currentResetEpoch, incomingEpoch != currentEpoch {
                return
            }
        }
        var logs: [QuickLog] = []
        // 单条:sendMessage / transferUserInfo
        if let data = payload[WatchKeys.quickLog] as? Data,
           let log = try? JSONDecoder().decode(QuickLog.self, from: data) {
            logs.append(log)
        }
        // 批量:applicationContext 只保留最新一份且会互相覆盖,
        // 所以手表放的是「最近若干条」的数组,靠幂等重放补齐。
        if let data = payload[WatchKeys.quickLogBatch] as? Data,
           let batch = try? JSONDecoder().decode([QuickLog].self, from: data) {
            logs.append(contentsOf: batch)
        }
        guard !logs.isEmpty else { return }
        // Persist before scheduling any main-actor work.  This covers both a
        // cold-start callback (container is still nil) and a transient model
        // save failure; the next activation retries the same payload.
        Self.mergePendingQuickLogs(logs)
        schedulePendingDrain()
    }

    // MARK: - Durable receive journal

    private static func withPendingQuickLogsLock<T>(_ body: () -> T) -> T {
        pendingQuickLogsLock.lock()
        defer { pendingQuickLogsLock.unlock() }
        return body()
    }

    private static func pendingQuickLogsUnlocked() -> [QuickLog] {
        guard let data = UserDefaults.standard.data(forKey: pendingQuickLogsKey),
              let logs = try? JSONDecoder().decode([QuickLog].self, from: data) else {
            return []
        }
        return logs
    }

    private static func pendingQuickLogs() -> [QuickLog] {
        withPendingQuickLogsLock { pendingQuickLogsUnlocked() }
    }

    private static func pendingKey(for log: QuickLog) -> String {
        "\(log.kind)|\(log.dayKey)"
    }

    private static func mergePendingQuickLogs(_ logs: [QuickLog]) {
        withPendingQuickLogsLock {
            let candidates = (pendingQuickLogsUnlocked() + logs)
                .filter { !QuickLogApplier.shouldDiscard($0) }
                .sorted { $0.sentAt < $1.sentAt }
            var latestByDay: [String: QuickLog] = [:]
            for log in candidates {
                latestByDay[pendingKey(for: log)] = log
            }
            let merged = latestByDay.values
                .sorted { $0.sentAt < $1.sentAt }
                .suffix(maxPendingQuickLogs)
            guard let data = try? JSONEncoder().encode(Array(merged)) else { return }
            UserDefaults.standard.set(data, forKey: pendingQuickLogsKey)
        }
    }

    private static func removePendingQuickLogs(_ processed: [QuickLog]) {
        guard !processed.isEmpty else { return }
        withPendingQuickLogsLock {
            var pending = pendingQuickLogsUnlocked()
            pending.removeAll { item in processed.contains(item) }
            guard let data = try? JSONEncoder().encode(pending) else { return }
            UserDefaults.standard.set(data, forKey: pendingQuickLogsKey)
        }
    }

    // Test hooks keep the retry journal testable without exposing the
    // WatchConnectivity delegate queue to XCTest.
    static func _pendingQuickLogsForTesting() -> [QuickLog] {
        pendingQuickLogs()
    }

    static func _enqueuePendingQuickLogsForTesting(_ logs: [QuickLog]) {
        mergePendingQuickLogs(logs)
    }

    static func _clearPendingQuickLogsForTesting() {
        withPendingQuickLogsLock {
            UserDefaults.standard.removeObject(forKey: pendingQuickLogsKey)
        }
    }

    private func schedulePendingDrain() {
        let shouldSchedule = withStateLock {
            guard !pendingDrainScheduled else { return false }
            pendingDrainScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.withStateLock { self.pendingDrainScheduled = false }
            self.drainPendingQuickLogs()
        }
    }

    @MainActor
    private func drainPendingQuickLogs() {
        guard let container = Self.container else { return }
        let logs = Self.pendingQuickLogs()
        guard !logs.isEmpty else { return }
        let shouldRun = withStateLock {
            guard !pendingDrainRunning else { return false }
            pendingDrainRunning = true
            return true
        }
        guard shouldRun else { return }
        defer {
            withStateLock { pendingDrainRunning = false }
        }

        // Do not use the shared SwiftData context: a failed Watch save must
        // not roll back an unrelated edit that a visible screen is holding.
        let context = ModelContext(container)
        let result = QuickLogApplier.applyWithKeys(logs, context: context)
        guard result.success else {
            schedulePendingRetry()
            return
        }
        Self.removePendingQuickLogs(logs)
        // A new Watch packet may have arrived while this batch was saving.
        // Drain it after the current run releases the running flag.
        if !Self.pendingQuickLogs().isEmpty { schedulePendingDrain() }
        guard !result.affectedDayKeys.isEmpty else { return }

        let defaults = UserDefaults.standard
        do {
            let actual = try UserContentDeletion.refreshAfterMutation(
                context: context,
                notificationManager: NotificationManager.shared,
                dailyEnabled: defaults.bool(forKey: "notif.dailyEnabled"),
                dailyHour: defaults.object(forKey: "notif.dailyHour") as? Int ?? 21,
                periodEnabled: defaults.bool(forKey: "notif.periodEnabled"),
                periodAdvanceDays: defaults.object(forKey: ProReminderSettings.Keys.periodAdvanceDays) as? Int ?? 2,
                smartEnabled: defaults.bool(forKey: ProReminderSettings.Keys.smartEnabled),
                pmsEnabled: defaults.bool(forKey: ProReminderSettings.Keys.pmsEnabled),
                storePremium: Store.shared.premium,
                manualCycle: ManualCycle.current
            )
            LocalDataChangeCenter.shared.post(
                kind: .quickLogApplied,
                affectedDayKeys: result.affectedDayKeys
            )
            Task { @MainActor in
                _ = await UserContentDeletion.syncQuickLogHealthBestEffort(
                    affectedDayKeys: result.affectedDayKeys,
                    periodDays: actual.periodDays,
                    logs: actual.logs
                )
            }
        } catch {
            // SwiftData is already durable.  Keep that local fact visible and
            // refresh WidgetKit; a later app activation retries derived work.
            LocalDataChangeCenter.shared.post(
                kind: .quickLogApplied,
                affectedDayKeys: result.affectedDayKeys
            )
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func schedulePendingRetry() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.schedulePendingDrain()
        }
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        guard state == .activated else { return }
        flushSnapshot()
        // 激活时兜一遍手表已发布的 context,避免错过激活前送达的记录。
        ingest(session.receivedApplicationContext)
    }

    // iOS 端必须实现这两个,否则切换手表时会话会失效。
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// 即时通道(两端都在前台时)。
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingest(message)
    }

    /// 排队通道(真机上的主力:手机不在旁边也会排队,不丢)。
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        ingest(userInfo)
    }

    /// 冗余通道:手表把「最近若干条记录」作为 context 发布,幂等重放。
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        ingest(context)
    }
}
