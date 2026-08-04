import Foundation
import SwiftData

/// 层级 4 · 把手表发来的「快速记录」落进手机的 SwiftData。
/// 手表不存库,所有写入都在这里统一走与 UI 相同的 upsert 逻辑,保证行为一致。
enum QuickLogApplier {

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

    @MainActor
    static func apply(_ logs: [QuickLog], context: ModelContext) {
        guard !logs.isEmpty else { return }
        for log in logs {
            // 防御:手表消息只来自本机已配对的 WatchConnectivity 会话,
            // 但 dayKey 非法/时间戳离谱时仍应拒绝,避免插入垃圾记录。
            guard isValid(log) else { continue }
            switch log.kind {
            case "period": applyPeriod(log, context: context)
            case "mood":   applyMood(log, context: context)
            default:       break
            }
        }
        try? context.save()
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
        case "period": return (log.flowRaw ?? 0) >= 0 && (log.flowRaw ?? 0) <= 3
        case "mood":   return (log.moodRaw ?? 0) >= 1 && (log.moodRaw ?? 0) <= 5
        default:       return false
        }
    }

    private static func applyPeriod(_ log: QuickLog, context: ModelContext) {
        let key = localDayKey(for: log)
        let existing = (try? context.fetch(
            FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == key })))?.first
        let flow = FlowLevel(rawValue: log.flowRaw ?? 2) ?? .medium
        if let existing {
            // 只在手表发送时刻比现有记录更新时才覆盖,防止 batch 重放旧值覆盖新值。
            guard log.sentAt > existing.updatedAt else { return }
            existing.flow = flow
            existing.updatedAt = Date()
        } else {
            context.insert(PeriodDay(date: DayKey.date(from: key), flow: flow))
        }
    }

    private static func applyMood(_ log: QuickLog, context: ModelContext) {
        let key = localDayKey(for: log)
        let existing = (try? context.fetch(
            FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == key })))?.first
        let mood = Mood(rawValue: log.moodRaw ?? 0)
        if let existing {
            // 只在手表发送时刻比现有记录更新时才覆盖,防止 batch 重放旧值覆盖新值
            // (用户之后在手机端改过的值不应被更早的手表记录覆盖)。
            guard log.sentAt > existing.updatedAt else { return }
            existing.mood = mood
            existing.updatedAt = Date()
        } else {
            context.insert(DailyLog(date: DayKey.date(from: key), mood: mood))
        }
    }
}
