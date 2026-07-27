import Foundation

/// 用户「按自己经验」手动设置的周期参数。
/// 存在意义:不规律 / PCOS / 刚上手的用户往往比统计更清楚自己的身体,
/// 也让「只记录过 1 次经期」的新用户立刻就能有预测,而不用干等两个周期。
struct ManualCycle: Equatable {
    var enabled: Bool
    var cycleLength: Int    // 周期长度(天)
    var periodLength: Int   // 经期持续天数

    static let defaultCycleLength = 28
    static let defaultPeriodLength = 5

    /// 允许范围,与预测引擎的长/不规律周期支持保持一致(15–120 天,容纳 PCOS 长周期)。
    static let cycleRange = 15...120
    static let periodRange = 1...14

    enum Keys {
        static let enabled = "cycle.manualEnabled"
        static let cycleLength = "cycle.manualCycleLength"
        static let periodLength = "cycle.manualPeriodLength"
    }

    /// 供非 View 场景(如通知调度)读取。
    static var current: ManualCycle {
        let d = UserDefaults.standard
        return ManualCycle(
            enabled: d.bool(forKey: Keys.enabled),
            cycleLength: d.object(forKey: Keys.cycleLength) as? Int ?? defaultCycleLength,
            periodLength: d.object(forKey: Keys.periodLength) as? Int ?? defaultPeriodLength
        )
    }
}
