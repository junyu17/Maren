import Foundation
import SwiftData

/// F1:被标记为「经期」的某一天,附带流量。
/// 以「天」为粒度存储,天然支持不规律 / 长周期(不假设固定经期长度)。
@Model
final class PeriodDay {
    /// 逻辑唯一键:yyyymmdd 整数(见 `DayKey`)。
    /// 用整数而不是 Date:跨时区 / 夏令时后,「本地零点」的时间戳会变,
    /// 会造成同一天重复记录或记录消失;整数日键只描述「哪一天」,永远稳定。
    /// ⚠️ 不用 `@Attribute(.unique)`:CloudKit 不支持唯一约束。同 dayKey 的去重
    /// 由写入路径手动完成(`CalendarView.upsertPeriod` / `QuickLogApplier`,先查后写)。
    var dayKey: Int = 0
    /// 存原始值,SwiftData 对基础类型最稳。
    var flowRaw: Int = FlowLevel.medium.rawValue
    var createdAt: Date = Date.now
    /// 最近一次修改时刻(用于手表记录的时间戳比较,防止旧值覆盖新值)。
    var updatedAt: Date = Date.now

    /// 该日在当前时区下的零点。派生属性,不入库,仅供显示与日期运算。
    var date: Date { DayKey.date(from: dayKey) }

    var flow: FlowLevel {
        get { FlowLevel(rawValue: flowRaw) ?? .medium }
        set { flowRaw = newValue.rawValue }
    }

    init(date: Date, flow: FlowLevel = .medium) {
        self.dayKey = DayKey.from(date)
        self.flowRaw = flow.rawValue
        self.createdAt = Date()
        self.updatedAt = self.createdAt
    }
}
