import Foundation
import SwiftData

/// 层级 4 · 把手表发来的「快速记录」落进手机的 SwiftData。
/// 手表不存库,所有写入都在这里统一走与 UI 相同的 upsert 逻辑,保证行为一致。
enum QuickLogApplier {

    /// The receiver-side replay barrier for WatchConnectivity payloads.
    ///
    /// Watch keeps an outbox and a recent application-context snapshot on the
    /// other device.  The phone cannot delete those values directly, so a
    /// successful local "Delete All Data" records a local cutoff and rejects
    /// every payload that was sent at or before that instant.  This key is
    /// intentionally kept here (rather than in the backup schema) so it is
    /// device state, not user data that can be imported into another device.
    static let deleteReplayCutoffKey = "vela.delete.replay.cutoff"

    /// UserDefaults may quantize a persisted Date/Double by a tiny amount.
    /// Keep the same one-microsecond bound used by read-back validation; this
    /// only covers persistence quantization and does not widen the replay window.
    static let deleteReplayPersistenceTolerance: TimeInterval = 0.000_001

    /// Returns the last successful local-delete cutoff, or nil when no valid
    /// cutoff has been recorded.  Older/broken defaults must fail open rather
    /// than making every future Watch record disappear.
    static func deleteReplayCutoff(from defaults: UserDefaults = .standard) -> Date? {
        let raw = defaults.object(forKey: deleteReplayCutoffKey)
        let seconds: Double
        if let date = raw as? Date {
            seconds = date.timeIntervalSince1970
        } else if let number = raw as? NSNumber {
            seconds = number.doubleValue
        } else {
            return nil
        }

        // A finite, non-negative Unix timestamp is the only representation we
        // write.  Treat malformed values as absent; do not throw or reject a
        // valid log because a previous app version left bad defaults behind.
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Persist a cutoff after local model deletion has succeeded.  Read-back
    /// verification makes the call testable and prevents callers from
    /// assuming a malformed value was stored as a barrier.
    @discardableResult
    static func persistDeleteReplayCutoff(
        at cutoff: Date = Date(),
        in defaults: UserDefaults = .standard
    ) -> Bool {
        let seconds = cutoff.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0 else { return false }
        defaults.set(seconds, forKey: deleteReplayCutoffKey)
        guard let stored = deleteReplayCutoff(from: defaults) else { return false }
        return abs(stored.timeIntervalSince1970 - seconds) < deleteReplayPersistenceTolerance
    }

    /// Whether a decoded Watch payload is older than the last successful
    /// local deletion.  Invalid/missing cutoff values are treated as no
    /// barrier.  The payload's own validation remains separate so callers can
    /// acknowledge malformed queue entries without persisting them.
    static func isBlockedByDeleteReplay(
        _ log: QuickLog,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let cutoff = deleteReplayCutoff(from: defaults) else { return false }
        // UserDefaults persistence can move the stored cutoff by less than the
        // validation tolerance; reject only that quantization-sized interval.
        return log.sentAt.timeIntervalSince(cutoff) <= deleteReplayPersistenceTolerance
    }

    /// Exposed for the Widget queue consumer: malformed or replay-blocked
    /// entries are safe to discard even if a different, new entry fails to
    /// save and therefore remains pending.
    static func shouldDiscard(_ log: QuickLog, defaults: UserDefaults = .standard) -> Bool {
        !isValid(log) || isBlockedByDeleteReplay(log, defaults: defaults)
    }

    /// 跨时区校正:手表的 dayKey 是**手表时区的今天**;手机与手表跨日期变更线时
    /// (如北京 +8 与纽约 -5),直接沿用会落到手机日历的另一天。
    /// 用 QuickLog 自带的发送端时区偏移,把 dayKey 转成发送端当天的绝对时刻,
    /// 再按手机时区重新取日历日 —— 记录始终出现在手机端的「今天」。
    /// 两端时区一致(常见情况)时,dayKey 不变,零开销。
    private static func localDayKey(for log: QuickLog) -> Int {
        let sendTZ = TimeZone(secondsFromGMT: log.tzOffsetSeconds)
        // 两端时区一致(常见情况)时,dayKey 不变,零开销。
        // 注意比较**偏移秒数**而非 TimeZone 相等:identifier 比较下
        // 固定偏移时区与区域时区永不相等,快速路径会失效。
        guard let sendTZ, sendTZ.secondsFromGMT() != TimeZone.current.secondsFromGMT() else {
            return log.dayKey
        }
        // 发送端时区下,该 dayKey 对应的本地零点。
        var comps = DateComponents()
        comps.year = log.dayKey / 10_000
        comps.month = (log.dayKey / 100) % 100
        comps.day = log.dayKey % 100
        comps.timeZone = sendTZ
        guard let absDate = Calendar(identifier: .gregorian).date(from: comps) else {
            return log.dayKey
        }
        // 再按手机时区取日历日。
        return DayKey.from(absDate)
    }

    struct ApplyResult: Equatable {
        let success: Bool
        let affectedDayKeys: Set<Int>

        static let empty = ApplyResult(success: true, affectedDayKeys: [])
    }

    /// 应用日志并持久化。返回 context.save() 是否成功。
    @MainActor
    @discardableResult
    static func apply(
        _ logs: [QuickLog],
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> Bool {
        applyWithKeys(logs, context: context, defaults: defaults).success
    }

    /// Applies logs and returns both success status and affected day keys.
    @MainActor
    static func applyWithKeys(
        _ logs: [QuickLog],
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> ApplyResult {
        guard !logs.isEmpty else { return .empty }
        let acceptedLogs = logs.filter {
            isValid($0) && !isBlockedByDeleteReplay($0, defaults: defaults)
        }
        guard !acceptedLogs.isEmpty else { return .empty }
        var affectedKeys = Set<Int>()
        do {
            for log in acceptedLogs {
                let changed: Bool
                switch log.kind {
                case "period": changed = try applyPeriod(log, context: context)
                case "mood":   changed = try applyMood(log, context: context)
                default:        changed = false
                }
                if changed { affectedKeys.insert(localDayKey(for: log)) }
            }
            guard !affectedKeys.isEmpty else { return .empty }
            try context.save()
            return ApplyResult(success: true, affectedDayKeys: affectedKeys)
        } catch {
            context.rollback()
            return ApplyResult(success: false, affectedDayKeys: [])
        }
    }

    /// 校验一条手表记录的基本合理性:
    /// - dayKey 必须是合法的真实日历日(避免非法值经 DayKey.date(from:) 回落成 1970);
    /// - raw 值在合法枚举范围(越界值会 fallback 并覆盖手机端已有记录);
    /// - sentAt 不得超过手机当前时间未来 48h(手表时钟被改快时,旧 batch 会借助
    ///   「sentAt > updatedAt」覆盖手机端新值)。**过去侧不设上限**:手表离线数天后
    ///   transferUserInfo/outbox 按「最终送达」语义补投,迟到记录不应被丢弃。
    private static func isValid(_ log: QuickLog) -> Bool {
        let year = log.dayKey / 10_000
        let month = (log.dayKey / 100) % 100
        let day = log.dayKey % 100
        guard (2000...2100).contains(year) else { return false }
        // 用公历验证真实存在性:DateComponents.isValidDate 严格校验
        // (自动拒绝 2 月 30 日、4 月 31 日等;Calendar.date(from:) 会溢出归一化而非返回 nil,
        // 会造成查询 key 与落库 dayKey 不一致、重放重复插入)。
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        guard comps.isValidDate(in: Calendar(identifier: .gregorian)) else { return false }
        // 未来侧上限:手表时钟不能快过手机 48h 以上。
        guard log.sentAt.timeIntervalSinceNow <= 48 * 3600 else { return false }
        // raw 值范围:越界会 fallback 成默认值,可能覆盖手机端正确记录。
        switch log.kind {
        case "period": return log.flowRaw != nil && (0...3).contains(log.flowRaw!)
        case "mood":   return log.moodRaw != nil && (1...5).contains(log.moodRaw!)
        default:       return false
        }
    }

    private static func applyPeriod(_ log: QuickLog, context: ModelContext) throws -> Bool {
        let key = localDayKey(for: log)
        let existing = try context.fetch(
            FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == key })).first
        guard let flowRaw = log.flowRaw else { return false }
        let flow = FlowLevel(rawValue: flowRaw) ?? .medium
        if let existing {
            // 只在手表发送时刻比现有记录更新时才覆盖,防止 batch 重放旧值覆盖新值。
            guard log.sentAt > existing.updatedAt else { return false }
            existing.flow = flow
            existing.importedFromHealth = false
            // `updatedAt` is also the durable source timestamp used by the
            // receiver.  Using the phone receive time here makes an older
            // item at the start of an offline Watch batch hide every newer
            // item that follows it (all of their `sentAt` values are in the
            // past by the time the batch arrives).
            existing.updatedAt = log.sentAt
        } else {
            let period = PeriodDay(date: DayKey.date(from: key), flow: flow)
            period.updatedAt = log.sentAt
            context.insert(period)
        }
        return true
    }

    private static func applyMood(_ log: QuickLog, context: ModelContext) throws -> Bool {
        let key = localDayKey(for: log)
        let existing = try context.fetch(
            FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == key })).first
        guard let moodRaw = log.moodRaw else { return false }
        let mood = Mood(rawValue: moodRaw)
        if let existing {
            // 只在手表发送时刻比现有记录更新时才覆盖,防止 batch 重放旧值覆盖新值
            // (用户之后在手机端改过的值不应被更早的手表记录覆盖)。
            guard log.sentAt > existing.updatedAt else { return false }
            existing.mood = mood
            existing.updatedAt = log.sentAt
        } else {
            let dailyLog = DailyLog(date: DayKey.date(from: key), mood: mood)
            dailyLog.updatedAt = log.sentAt
            context.insert(dailyLog)
        }
        return true
    }
}
