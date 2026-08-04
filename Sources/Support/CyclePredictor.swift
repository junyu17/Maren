import Foundation

/// F2:设备端自适应周期预测。
///
/// 设计原则(对应立项书铁律):
/// - **不写死「第 14 天排卵」**:只从用户真实经期记录里学周期长度,不套用固定模板。
/// - **支持不规律 / 长周期(15–120 天)**:用最近若干个周期的均值 + 标准差自适应。
/// - **呈现置信区间而非假装精准**:数据少 / 波动大时,主动给出更宽的区间和更低的置信度。
/// - **不做避孕 / 排卵保证定位**:只预测「下次经期」与「周期规律度」,不输出安全期 / 受孕窗。
/// - 纯函数、无网络、无副作用,便于单测。
enum CyclePredictor {

    enum Confidence: Int {
        case none = 0   // 数据不足
        case low        // 数据少或波动大
        case medium
        case high

        var label: String {
            switch self {
            case .none:   return String(localized: "数据不足")
            case .low:    return String(localized: "较低")
            case .medium: return String(localized: "中等")
            case .high:   return String(localized: "较高")
            }
        }
    }

    /// 一个已观测到的周期(供历史列表与洞察复用)。
    struct CycleRecord: Identifiable {
        let start: Date        // 该周期首日(经期第 1 天)
        let periodDays: Int    // 这次经期记录的天数
        let length: Int?       // 到下一个周期首日的天数;当前进行中的周期为 nil
        var id: Date { start }
    }

    struct Prediction {
        var hasEnoughData: Bool
        var observedCycleCount: Int         // 已观测到的完整周期数
        var cycles: [CycleRecord] = []      // 各周期明细(时间升序)
        var cycleLengths: [Int] = []        // 各周期长度(供图表)
        var averageCycleLength: Double?     // 平均周期长度(天)
        var cycleLengthStdDev: Double?      // 周期长度标准差
        var averagePeriodLength: Double?    // 平均经期持续天数
        var lastCycleStart: Date?
        var nextPeriodStart: Date?          // 预测的下次经期首日(区间中点)
        var nextRangeStart: Date?           // 置信区间下界
        var nextRangeEnd: Date?             // 置信区间上界
        var confidence: Confidence
        var regularity: String              // 规律 / 较规律 / 不规律
        var isManual: Bool = false          // 是否来自用户手动设置的周期

        static let empty = Prediction(
            hasEnoughData: false, observedCycleCount: 0,
            averageCycleLength: nil, cycleLengthStdDev: nil, averagePeriodLength: nil,
            lastCycleStart: nil, nextPeriodStart: nil, nextRangeStart: nil, nextRangeEnd: nil,
            confidence: .none, regularity: "—"
        )
    }

    /// 只用最近这么多个周期来学习(更贴近当前身体状态)。
    private static let recentWindow = 6

    /// 只回溯这么久的记录参与计算(约 2 年)。
    /// 两个理由:① 两年前的周期对「下次经期」已无预测价值,身体状况也变了;
    /// ② 更重要的是**成本有界** —— 否则用户用了五年、十年后,
    /// 每次重算都要遍历全部历史,开销随使用年限无限增长。
    /// 2 年即使按 90 天的长周期算也有 8 个周期,远超 recentWindow 所需。
    private static let lookbackDays = 730
    /// 两次经期首日至少相隔这么多天,才算「新的一个周期」。
    /// 小于它的多半是同一次经期中间断记 / 点滴出血,不能当成新周期,
    /// 否则会把预测锚点错误地往前挪。
    private static let minCycle = 15
    /// 周期长度上限。放宽到 120 天以容纳 PCOS / 长周期人群:
    /// 超过上限的间隔仍然算「新周期的开始」(锚点有效),
    /// 只是不把这个长度计入均值,避免一次漏记就把平均值拉飞。
    private static let maxCycle = 120

    /// 同一次经期允许中间漏记的天数。
    /// 相隔 <= 2 天(即最多漏记 1 天)仍算同一段经期,
    /// 否则「忘记记一天」会把一段经期劈成两段,污染经期长度与预测锚点。
    private static let maxGapWithinPeriod = 2

    /// 样本越少,区间必须越宽 —— 用一个诚实的下限,避免只有 1 个周期时假装 ±1 天的精准。
    private static func minimumHalfWidth(forSampleCount n: Int) -> Int {
        switch n {
        case 0: return 5
        case 1: return 4
        case 2: return 3
        default: return 2
        }
    }

    /// 主入口:传入所有经期日,产出预测。
    /// - Parameter manual: 用户手动设置的周期;开启后优先于统计学习结果。
    static func predict(from periodDays: [PeriodDay],
                        today: Date = Date(),
                        manual: ManualCycle? = nil) -> Prediction {
        let cal = Cal.current
        let today = Cal.startOfDay(today)

        // 手动值来自 UserDefaults,可能被篡改/越界(负数、超大值);在入口 clamp 防御,
        // 避免区间计算出现异常语义(虽然不崩溃)。
        let manualSafe: ManualCycle? = manual.map {
            ManualCycle(enabled: $0.enabled,
                        cycleLength: min(max($0.cycleLength, ManualCycle.cycleRange.lowerBound),
                                         ManualCycle.cycleRange.upperBound),
                        periodLength: min(max($0.periodLength, ManualCycle.periodRange.lowerBound),
                                          ManualCycle.periodRange.upperBound))
        }

        // 1) 归一 + 去重 + 排序参与计算的经期日。
        //    - 未来日期不参与:误点一个将来的日子不该把整个预测锚点挪走。
        //    - 只回溯 lookbackDays:让单次重算的成本有上界,不随使用年限增长。
        let earliest = cal.date(byAdding: .day, value: -lookbackDays, to: today) ?? .distantPast
        let days = Array(Set(periodDays.map { Cal.startOfDay($0.date) }))
            .filter { $0 <= today && $0 >= earliest }
            .sorted()
        guard !days.isEmpty else { return .empty }

        // 2) 把连续的日子聚成「经期段」。允许中间漏记 1 天(间隔 <= 2 天仍算同一段),
        //    避免「忘记记一天」把一段经期劈成两段。
        var spans: [(start: Date, length: Int)] = []
        var spanStart = days[0]
        var spanEnd = days[0]
        var spanLen = 1
        for i in 1..<days.count {
            let cur = days[i]
            let gap = cal.dateComponents([.day], from: spanEnd, to: cur).day ?? 0
            if gap <= maxGapWithinPeriod {
                spanLen += 1
                spanEnd = cur
            } else {
                spans.append((spanStart, spanLen))
                spanStart = cur
                spanEnd = cur
                spanLen = 1
            }
        }
        spans.append((spanStart, spanLen))

        // 3) 从经期段里挑出真正的「周期起点」:
        //    距上一个起点不足 minCycle 天的段,视为同一周期内的点滴出血,不另起一个周期。
        var cycleStarts: [Date] = []
        var cycleStartLengths: [Int] = []   // 对应段的经期天数
        for span in spans {
            if let last = cycleStarts.last {
                let gap = cal.dateComponents([.day], from: last, to: span.start).day ?? 0
                if gap < minCycle { continue }  // 点滴/补记,不算新周期
            }
            cycleStarts.append(span.start)
            cycleStartLengths.append(span.length)
        }

        // 经期长度只统计「真正的周期起始段」,避免点滴记录把平均值拉低。
        let averagePeriodLength = cycleStartLengths.isEmpty ? nil
            : Double(cycleStartLengths.reduce(0, +)) / Double(cycleStartLengths.count)
        // 锚点 = 最近一次真正的经期起点。
        let lastCycleStart = cycleStarts.last

        // 组装每个周期的明细(历史列表 + 洞察都要用)。最后一个周期进行中,length = nil。
        var cycles: [CycleRecord] = []
        for (i, start) in cycleStarts.enumerated() {
            let length: Int? = (i + 1 < cycleStarts.count)
                ? cal.dateComponents([.day], from: start, to: cycleStarts[i + 1]).day
                : nil
            cycles.append(CycleRecord(start: start, periodDays: cycleStartLengths[i], length: length))
        }

        // 4) 周期长度 = 相邻两个周期起点之差。
        //    超过上限的间隔仍保留锚点作用,但不计入均值(多半是中间漏记了一整个周期)。
        var cycleLengths: [Int] = []
        if cycleStarts.count >= 2 {
            for i in 1..<cycleStarts.count {
                let len = cal.dateComponents([.day], from: cycleStarts[i - 1], to: cycleStarts[i]).day ?? 0
                if len >= minCycle && len <= maxCycle {
                    cycleLengths.append(len)
                }
            }
        }

        // 用户手动设置优先:她比统计更清楚自己的身体,且只需记录过 1 次经期就能用。
        if let m = manualSafe, m.enabled, let lastStart = lastCycleStart {
            let half = 2 // 手动设置不谈波动,给一个克制的 ±2 天窗口
            return Prediction(
                hasEnoughData: true,
                observedCycleCount: cycleLengths.count,
                cycles: cycles,
                cycleLengths: cycleLengths,
                averageCycleLength: Double(m.cycleLength),
                cycleLengthStdDev: 0,
                averagePeriodLength: Double(m.periodLength),
                lastCycleStart: lastStart,
                nextPeriodStart: cal.date(byAdding: .day, value: m.cycleLength, to: lastStart),
                nextRangeStart: cal.date(byAdding: .day, value: m.cycleLength - half, to: lastStart),
                nextRangeEnd: cal.date(byAdding: .day, value: m.cycleLength + half, to: lastStart),
                confidence: .medium,
                regularity: String(localized: "自定义"),
                isManual: true
            )
        }

        // 数据不足以预测:段数 < 2 或没有有效周期长度。
        guard !cycleLengths.isEmpty else {
            return Prediction(
                hasEnoughData: false,
                observedCycleCount: 0,
                cycles: cycles,
                averageCycleLength: nil, cycleLengthStdDev: nil,
                averagePeriodLength: averagePeriodLength,
                lastCycleStart: lastCycleStart,
                nextPeriodStart: nil, nextRangeStart: nil, nextRangeEnd: nil,
                confidence: .none, regularity: "—"
            )
        }

        // 4) 取最近若干个周期算均值与标准差。
        let recent = Array(cycleLengths.suffix(recentWindow))
        let mean = Double(recent.reduce(0, +)) / Double(recent.count)
        let variance = recent.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(recent.count)
        let std = variance.squareRoot()

        // 5) 置信度:数据越多、波动越小越高。
        let confidence: Confidence
        switch (recent.count, std) {
        case (let n, let s) where n >= 3 && s <= 2.5: confidence = .high
        case (let n, let s) where n >= 2 && s <= 5.0: confidence = .medium
        default: confidence = .low
        }

        let regularity: String
        switch std {
        case ..<2.5: regularity = String(localized: "规律")
        case ..<6.0: regularity = String(localized: "较规律")
        default:     regularity = String(localized: "不规律")
        }

        // 6) 预测下次经期首日 = 上次首日 + 平均周期;区间宽度 = 至少 ±1 天,波动大则更宽。
        let center = Int(mean.rounded())
        // 区间宽度同时受「实测波动」和「样本量下限」约束:
        // 只有 1 个周期时不假装 ±1 天的精准,而是诚实地给出更宽的窗口。
        let half = max(minimumHalfWidth(forSampleCount: recent.count), Int(std.rounded()))
        let base = lastCycleStart ?? today
        let nextStart = cal.date(byAdding: .day, value: center, to: base)
        // 波动极大(如 15 与 120 并存)时 center - half 可能为负,
        // 区间下界会回到过去混入已过去的日子;clamp 到经期起点。
        let rangeStart = max(cal.date(byAdding: .day, value: center - half, to: base) ?? base, base)
        let rangeEnd = cal.date(byAdding: .day, value: center + half, to: base)

        return Prediction(
            hasEnoughData: true,
            observedCycleCount: cycleLengths.count,
            cycles: cycles,
            cycleLengths: cycleLengths,
            averageCycleLength: mean,
            cycleLengthStdDev: std,
            averagePeriodLength: averagePeriodLength,
            lastCycleStart: lastCycleStart,
            nextPeriodStart: nextStart,
            nextRangeStart: rangeStart,
            nextRangeEnd: rangeEnd,
            confidence: confidence,
            regularity: regularity
        )
    }
}
