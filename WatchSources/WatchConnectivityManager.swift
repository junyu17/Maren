import Foundation
import WatchConnectivity
import WidgetKit

/// 层级 4 · 手表侧连接。接收手机推来的快照,把快速记录送回手机。
///
/// 投递分两条路径:
///   - `send`/`deliver`: 手表 UI 发起的单条记录,用 sendMessage + transferUserInfo 多通道叠加;
///   - `drainWatchQueue`: 排空小组件/App Shortcuts 写入的本地队列,用 transferUserInfo 排队投递。
/// 手机侧落库是按 dayKey 的 upsert,重复到达不会产生重复数据。
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var snapshot: WidgetSnapshot = .placeholder
    /// 最近一次发送时间(用于给用户「已记录」的反馈)。
    @Published var lastSent: Date?

    private let cacheKey = "vela.watch.snapshot"
    private let recentKey = "vela.watch.recentLogs"
    private let outboxKey = "vela.watch.outbox"
    private let resetEpochKey = "vela.watch.resetEpoch"

    /// 手表独立 App Group,供 watch widget 读取快照。
    static let watchAppGroup = "group.cd.cc.vela"

    /// 会话激活前发起的记录。未激活时投递会静默失败,
    /// 用户刚打开手表 app 就点击的话记录会凭空消失,所以先攒着,激活后补发。
    /// 持久化到 UserDefaults:watchOS 上 app 被系统终止是常态,
    /// 只存内存的话,重启后这些记录会永久丢失(而 UI 已显示「已记录」)。
    private var outbox: [QuickLog] {
        didSet { persistOutbox() }
    }
    /// 最近发出的记录(用于 applicationContext 冗余通道)。
    private var recent: [QuickLog] = []
    /// 上次 applicationContext 更新时间,用于节流(高频连点时合并为低频更新)。
    private var lastContextUpdate = Date.distantPast

    private var resetEpoch: Int64? {
        WatchResetGeneration.decode(UserDefaults.standard.object(forKey: resetEpochKey))
    }

    override init() {
        // 冷启动先用上次缓存,避免一片空白。
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            snapshot = s
        }
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let r = try? JSONDecoder().decode([QuickLog].self, from: data) {
            recent = r
        }
        // 恢复上次未送达的 outbox(终止前没发出去的记录)。
        if let data = UserDefaults.standard.data(forKey: outboxKey),
           let o = try? JSONDecoder().decode([QuickLog].self, from: data) {
            outbox = o
        } else {
            outbox = []
        }
    }

    private func persistOutbox() {
        if let data = try? JSONEncoder().encode(outbox) {
            UserDefaults.standard.set(data, forKey: outboxKey)
        }
    }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        // 拉一次已有的 applicationContext(手机可能在手表 app 打开前就推过了)。
        applyContext(session.receivedApplicationContext)
        // 启动时排空 watch 队列(通过 WCSession 发回手机)。
        drainWatchQueue()
    }

    // MARK: - 快照持久化到 watch App Group

    /// 把快照同时写入 watch App Group,供 watch widget 读取。
    private func persistSnapshotToWatchGroup(_ snapshot: WidgetSnapshot) {
        WatchWidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 快速记录发送

    /// 发送一条快速记录。
    func send(_ log: QuickLog) {
        guard let session else { return }

        guard session.activationState == .activated else {
            outbox.append(log)   // 还没激活,先攒着(已持久化,app 被终止也不丢)
            activate()
            return
        }
        deliver(log, via: session)
    }

    /// 激活完成后把攒下的记录补发出去。
    private func flushOutbox() {
        guard let session, session.activationState == .activated, !outbox.isEmpty else { return }
        let queued = outbox
        outbox.removeAll()
        for log in queued { deliver(log, via: session) }
    }

    private func deliver(_ log: QuickLog, via session: WCSession) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        var deliveredNow = false
        var payload: [String: Any] = [WatchKeys.quickLog: data]
        if let epoch = resetEpoch {
            payload[WatchKeys.resetEpoch] = NSNumber(value: epoch)
        }

        if session.isReachable {
            // 通道 1:立即送达。
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)  // 失败退回排队
            }
            deliveredNow = true
        } else {
            // 通道 2:排队投递(系统保证送达,不算丢失)。
            session.transferUserInfo(payload)
            deliveredNow = true
        }

        // 通道 3:把最近若干条作为 context 发布,幂等重放兜底。
        recent.removeAll { $0.kind == log.kind && $0.dayKey == log.dayKey }
        recent.append(log)
        recent = Array(recent.suffix(20))
        let now = Date()
        if now.timeIntervalSince(lastContextUpdate) > 1.0 {
            lastContextUpdate = now
            if let batch = try? JSONEncoder().encode(recent) {
                UserDefaults.standard.set(batch, forKey: recentKey)
                var context: [String: Any] = [WatchKeys.quickLogBatch: batch]
                if let epoch = resetEpoch {
                    context[WatchKeys.resetEpoch] = NSNumber(value: epoch)
                }
                try? session.updateApplicationContext(context)
            }
        }

        if deliveredNow {
            Task { @MainActor in self.lastSent = Date() }
        }
    }

    private func applyReset(_ epoch: Int64, force: Bool = false) {
        guard WatchResetGeneration.shouldApply(epoch, current: resetEpoch) else { return }
        // A normal snapshot carries the current generation for ordering but
        // is not itself a reset command.  Only a newer generation or an
        // explicit reset command clears state; this prevents every ordinary
        // phone snapshot from deleting a newly-created Watch outbox.
        if !force, resetEpoch == epoch { return }
        // Reset delivery can race across sendMessage, transferUserInfo, and
        // applicationContext.  Make it idempotent, but still re-run cleanup
        // for a duplicate marker in case a previous process was terminated
        // between clearing one store and another.
        UserDefaults.standard.set(epoch, forKey: resetEpochKey)
        outbox.removeAll()
        recent.removeAll()
        lastContextUpdate = Date.distantPast
        UserDefaults.standard.removeObject(forKey: outboxKey)
        UserDefaults.standard.removeObject(forKey: recentKey)
        UserDefaults.standard.removeObject(forKey: cacheKey)
        snapshot = .placeholder
        WatchWidgetSnapshotStore.write(.placeholder)
        _ = QuickActionQueue.clear(from: Self.watchAppGroup)
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in self.lastSent = nil }
    }

    @discardableResult
    private func applyResetIfPresent(in payload: [String: Any], force: Bool = false) -> Bool {
        guard payload.keys.contains(WatchKeys.resetEpoch) else { return true }
        guard let epoch = WatchResetGeneration.decode(payload[WatchKeys.resetEpoch]) else {
            // A malformed legacy marker is not the same as an absent marker;
            // ignore the whole context so it cannot overwrite a newer cache.
            return false
        }
        let isCommand = force || (payload[WatchKeys.resetCommand] as? Bool == true)
        if WatchResetGeneration.shouldApply(epoch, current: resetEpoch) {
            applyReset(epoch, force: isCommand)
        } else {
            // A late lower-generation context is stale, including its
            // snapshot.  The receiver-side cutoff handles old quick logs on
            // iPhone; Watch must also avoid showing that stale cache.
            return false
        }
        return true
    }

    private func applyContext(_ context: [String: Any]) {
        guard applyResetIfPresent(in: context) else { return }
        guard let data = context[WatchKeys.snapshot] as? Data,
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        // 持久化到 watch App Group,供 watch widget 读取。
        persistSnapshotToWatchGroup(s)
        Task { @MainActor in self.snapshot = s }
    }

    // MARK: - Watch Queue 消费(peek → transfer → acknowledge)

    /// 非破坏性读取手表本地快速操作队列,转换为 QuickLog 后通过 transferUserInfo 投递手机。
    /// transferUserInfo 是排队投递(系统保证送达),无需 sendMessage;
    /// 编码成功且 transferUserInfo 返回后才 acknowledge 移除;
    /// 若会话不可用、转换/编码失败,条目保留在队列中等待下次重试。
    func drainWatchQueue() {
        let entries = QuickActionQueue.peek(from: Self.watchAppGroup)
        guard !entries.isEmpty else { return }

        guard let session, session.activationState == .activated else { return }

        var acceptedIDs = Set<UUID>()
        for entry in entries {
            // 将 QuickActionEntry 转换为 QuickLog,手机侧 Decoder 只认 QuickLog。
            let log: QuickLog
            switch entry.kind {
            case "period":
                guard let flowRaw = entry.flowRaw else { continue }
                log = QuickLog.period(flowRaw: flowRaw, dayKey: entry.dayKey,
                                      sentAt: entry.createdAt,
                                      tzOffsetSeconds: TimeZone.current.secondsFromGMT())
            case "mood":
                guard let moodRaw = entry.moodRaw else { continue }
                log = QuickLog.mood(moodRaw: moodRaw, dayKey: entry.dayKey,
                                    sentAt: entry.createdAt,
                                    tzOffsetSeconds: TimeZone.current.secondsFromGMT())
            default:
                continue
            }

            guard let data = try? JSONEncoder().encode(log) else { continue }

            // transferUserInfo 是排队投递,系统保证送达,不需要 sendMessage。
            var payload: [String: Any] = [WatchKeys.quickLog: data]
            if let epoch = resetEpoch {
                payload[WatchKeys.resetEpoch] = NSNumber(value: epoch)
            }
            session.transferUserInfo(payload)
            acceptedIDs.insert(entry.id)
        }

        if !acceptedIDs.isEmpty {
            QuickActionQueue.acknowledge(acceptedIDs, from: Self.watchAppGroup)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        applyContext(session.receivedApplicationContext)
        flushOutbox()
        drainWatchQueue()
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        applyContext(context)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        _ = applyResetIfPresent(in: message, force: true)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        _ = applyResetIfPresent(in: userInfo, force: true)
    }
}
