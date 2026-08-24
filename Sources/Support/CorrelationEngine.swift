import Foundation

/// 设备端相关性探索器 —— 确定性纯函数,分析 pairwise 关系。
/// 使用 neutral observation language,无因果/诊断/治疗效果声明。
/// 始终展示样本量(N)和数据充分性警告。
enum CorrelationEngine {

    struct Correlation: Identifiable {
        let id: String
        let title: String
        let description: String
        let observations: [Observation]
        let sufficientData: Bool
        let sampleSize: Int
    }

    struct Observation: Identifiable {
        let id: String
        let label: String
        let value: String
        let detail: String
    }

    struct AnalysisInput {
        let periodDays: [PeriodDay]
        let logs: [DailyLog]
        let prediction: CyclePredictor.Prediction
        let medications: [Medication]
        let intakes: [MedicationIntake]
    }

    /// 生成所有 pairwise 相关性分析。
    static func analyze(input: AnalysisInput) -> [Correlation] {
        var results: [Correlation] = []

        // 给每条日志标记阶段
        // PhaseModel converts the fallback cycle length to Int.  Treat
        // malformed imported/statistical values as missing before crossing
        // that boundary; Int.nan/Int.infinity would trap instead of yielding
        // an insufficient analysis.
        let safeAverageCycle = input.prediction.averageCycleLength.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        let safeAveragePeriod = input.prediction.averagePeriodLength.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        let phased: [(log: DailyLog, phase: CyclePhase)] = input.logs.compactMap { log in
            let ph = PhaseModel.phaseForPast(log.date, cycles: input.prediction.cycles,
                                              avgCycle: safeAverageCycle,
                                              avgPeriod: safeAveragePeriod)
            return ph == .unknown ? nil : (log, ph)
        }

        if let c = phaseTrackerCorrelation(phased) { results.append(c) }
        if let c = sleepMoodCorrelation(input.logs) { results.append(c) }
        if let c = sleepPainCorrelation(input.logs) { results.append(c) }
        if let c = medicationCheckInCorrelation(input) { results.append(c) }
        if let c = cycleLengthWeightCorrelation(input) { results.append(c) }

        return results
    }

    // MARK: - 周期阶段 × 追踪项/心情(按每观测日归一化)

    private static func phaseTrackerCorrelation(_ phased: [(log: DailyLog, phase: CyclePhase)]) -> Correlation? {
        // 统计每个阶段的追踪项出现次数 和 该阶段的观测天数
        var trackerByPhase: [CyclePhase: [String: Int]] = [:]
        var moodByPhase: [CyclePhase: [Int]] = [:]
        var countByPhase: [CyclePhase: Int] = [:]

        for (log, phase) in phased {
            countByPhase[phase, default: 0] += 1
            for sym in log.symptoms {
                trackerByPhase[phase, default: [:]][sym, default: 0] += 1
            }
            if let m = log.mood {
                moodByPhase[phase, default: []].append(m.rawValue)
            }
        }

        let totalPhased = phased.count
        guard totalPhased >= 10 else {
            return Correlation(id: "phase-tracker", title: String(localized: "阶段与追踪项/心情"),
                               description: String(localized: "分析各周期阶段中追踪项和心情的分布模式。"),
                               observations: [], sufficientData: false, sampleSize: totalPhased)
        }

        // A single phase cannot support a phase comparison.  Return the
        // contract's insufficient result before any per-phase aggregation or
        // normalization; this keeps sparse/single-phase input safe even when
        // future phase metrics add stricter denominators.
        let representedPhases = Set(phased.map(\.phase).filter { $0 != .unknown })
        guard representedPhases.count >= 2 else {
            return Correlation(id: "phase-tracker", title: String(localized: "阶段与追踪项/心情"),
                               description: String(localized: "分析各周期阶段中追踪项和心情的分布模式。"),
                               observations: [], sufficientData: false, sampleSize: totalPhased)
        }

        var observations: [Observation] = []
        var phasesRepresented: Set<CyclePhase> = []

        // 追踪项:找出在某阶段出现频率最高的,按每观测日归一化
        var allTrackers: Set<String> = []
        for byPhase in trackerByPhase.values { for key in byPhase.keys { allTrackers.insert(key) } }
        for key in allTrackers {
            var bestPhase: CyclePhase?
            var bestRate: Double = 0
            var bestCount = 0
            var bestPhaseDays = 0
            var totalCount = 0
            for phase in CyclePhase.allCases where phase != .unknown {
                let count = trackerByPhase[phase]?[key] ?? 0
                let phaseDays = countByPhase[phase] ?? 0
                totalCount += count
                if phaseDays >= 2 {
                    let rate = Double(count) / Double(phaseDays)
                    if rate > bestRate {
                        bestRate = rate
                        bestPhase = phase
                        bestCount = count
                        bestPhaseDays = phaseDays
                    }
                }
            }
            guard totalCount >= 3, let best = bestPhase, bestPhaseDays >= 2 else { continue }
            let ratePct = bestRate * 100
            if ratePct >= 20 {
                phasesRepresented.insert(best)
                observations.append(Observation(
                    id: "tracker-\(key)-\(best.rawValue)",
                    label: Symptoms.label(for: key),
                    value: String(localized: "\(bestCount)/\(bestPhaseDays) 天在 \(best.label) 观测到"),
                    detail: String(localized: "\(best.label)期间 \(bestPhaseDays) 天观测中出现了 \(bestCount) 次(每 \(bestPhaseDays) 天 \(bestCount) 次)。")))
            }
        }

        // 心情:各阶段平均值
        for phase in CyclePhase.allCases where phase != .unknown {
            guard let moods = moodByPhase[phase], moods.count >= 3 else { continue }
            let avg = Double(moods.reduce(0, +)) / Double(moods.count)
            phasesRepresented.insert(phase)
            observations.append(Observation(
                id: "mood-\(phase.rawValue)",
                label: String(localized: "\(phase.label)心情"),
                value: String(localized: "平均 \(String(format: "%.1f", avg)) 分"),
                detail: String(localized: "在 \(moods.count) 个\(phase.label)日中,心情平均 \(String(format: "%.1f", avg)) / 5。")))
        }

        // 需要至少 2 个不同阶段有观测才有比较意义
        return Correlation(id: "phase-tracker", title: String(localized: "阶段与追踪项/心情"),
                           description: String(localized: "分析各周期阶段中追踪项和心情的分布模式。"),
                           observations: observations,
                           sufficientData: observations.count >= 2 && phasesRepresented.count >= 2,
                           sampleSize: totalPhased)
    }

    // MARK: - 睡眠 × 心情

    private static func sleepMoodCorrelation(_ logs: [DailyLog]) -> Correlation? {
        let paired = logs.compactMap { log -> (sleep: Double, mood: Int)? in
            guard let sleep = log.sleepHours, let mood = log.mood else { return nil }
            return (sleep, mood.rawValue)
        }
        guard paired.count >= 5 else {
            return Correlation(id: "sleep-mood", title: String(localized: "睡眠与心情"),
                               description: String(localized: "观察睡眠时长与心情评分之间的关系。"),
                               observations: [], sufficientData: false, sampleSize: paired.count)
        }

        // 按睡眠分组:短(<6h),中(6-7.5h),长(>7.5h)
        let short = paired.filter { $0.sleep < 6.0 }
        let mid = paired.filter { $0.sleep >= 6.0 && $0.sleep <= 7.5 }
        let long = paired.filter { $0.sleep > 7.5 }

        var observations: [Observation] = []

        if short.count >= 2 {
            let avgMood = Double(short.reduce(0) { $0 + $1.mood }) / Double(short.count)
            observations.append(Observation(
                id: "sleep-short",
                label: String(localized: "睡眠 < 6 小时"),
                value: String(localized: "平均心情 \(String(format: "%.1f", avgMood)) 分 (\(short.count) 天)"),
                detail: String(localized: "共 \(short.count) 天睡眠不足 6 小时,平均心情评分 \(String(format: "%.1f", avgMood)) / 5。")))
        }
        if mid.count >= 2 {
            let avgMood = Double(mid.reduce(0) { $0 + $1.mood }) / Double(mid.count)
            observations.append(Observation(
                id: "sleep-mid",
                label: String(localized: "睡眠 6–7.5 小时"),
                value: String(localized: "平均心情 \(String(format: "%.1f", avgMood)) 分 (\(mid.count) 天)"),
                detail: String(localized: "共 \(mid.count) 天睡眠 6–7.5 小时,平均心情评分 \(String(format: "%.1f", avgMood)) / 5。")))
        }
        if long.count >= 2 {
            let avgMood = Double(long.reduce(0) { $0 + $1.mood }) / Double(long.count)
            observations.append(Observation(
                id: "sleep-long",
                label: String(localized: "睡眠 > 7.5 小时"),
                value: String(localized: "平均心情 \(String(format: "%.1f", avgMood)) 分 (\(long.count) 天)"),
                detail: String(localized: "共 \(long.count) 天睡眠超过 7.5 小时,平均心情评分 \(String(format: "%.1f", avgMood)) / 5。")))
        }

        return Correlation(id: "sleep-mood", title: String(localized: "睡眠与心情"),
                           description: String(localized: "观察睡眠时长与心情评分之间的关系。"),
                           observations: observations, sufficientData: observations.count >= 2, sampleSize: paired.count)
    }

    // MARK: - 睡眠 × 疼痛

    private static func sleepPainCorrelation(_ logs: [DailyLog]) -> Correlation? {
        let paired = logs.compactMap { log -> (sleep: Double, pain: Int)? in
            guard let sleep = log.sleepHours, log.pain >= 0 else { return nil }
            return (sleep, log.pain)
        }
        guard paired.count >= 5 else {
            return Correlation(id: "sleep-pain", title: String(localized: "睡眠与疼痛"),
                               description: String(localized: "观察睡眠时长与疼痛评分之间的关系。"),
                               observations: [], sufficientData: false, sampleSize: paired.count)
        }

        let lowPain = paired.filter { $0.pain <= 2 }
        let highPain = paired.filter { $0.pain >= 3 }

        var observations: [Observation] = []

        if lowPain.count >= 2 {
            let avgSleep = lowPain.reduce(0.0) { $0 + $1.sleep } / Double(lowPain.count)
            observations.append(Observation(
                id: "pain-low",
                label: String(localized: "疼痛 ≤ 2 分时"),
                value: String(localized: "平均睡眠 \(String(format: "%.1f", avgSleep)) 小时 (\(lowPain.count) 天)"),
                detail: String(localized: "疼痛评分 ≤ 2 时,平均睡眠 \(String(format: "%.1f", avgSleep)) 小时。")))
        }
        if highPain.count >= 2 {
            let avgSleep = highPain.reduce(0.0) { $0 + $1.sleep } / Double(highPain.count)
            observations.append(Observation(
                id: "pain-high",
                label: String(localized: "疼痛 ≥ 3 分时"),
                value: String(localized: "平均睡眠 \(String(format: "%.1f", avgSleep)) 小时 (\(highPain.count) 天)"),
                detail: String(localized: "疼痛评分 ≥ 3 时,平均睡眠 \(String(format: "%.1f", avgSleep)) 小时。")))
        }

        return Correlation(id: "sleep-pain", title: String(localized: "睡眠与疼痛"),
                           description: String(localized: "观察睡眠时长与疼痛评分之间的关系。"),
                           observations: observations, sufficientData: observations.count >= 2, sampleSize: paired.count)
    }

    // MARK: - 用药打卡 × 追踪项记录(描述性分组观察,不是相关性)

    private static func medicationCheckInCorrelation(_ input: AnalysisInput) -> Correlation? {
        guard !input.medications.isEmpty else {
            return Correlation(id: "med-tracker", title: String(localized: "用药打卡与追踪记录"),
                               description: String(localized: "观察用药打卡日与非打卡日的追踪记录差异。"),
                               observations: [], sufficientData: false, sampleSize: 0)
        }

        let today = Cal.startOfDay(Date())
        var allObservations: [Observation] = []
        var uniqueEligibleDayKeys: Set<Int> = []

        for med in input.medications {
            let medCreated = Cal.startOfDay(med.createdAt)

            // 只使用该药自己的打卡记录
            let medIntakes = input.intakes.filter { $0.medicationId == med.id }
            let intakeDayKeys: Set<Int> = Set(medIntakes.map { $0.dayKey })

            // 日志必须在该药创建日之后且不在未来
            let eligibleLogs = input.logs.filter {
                guard $0.hasContent else { return false }
                let day = Cal.startOfDay($0.date)
                return day >= medCreated && day <= today
            }

            let checkInLogs = eligibleLogs.filter { intakeDayKeys.contains($0.dayKey) }
            let nonCheckInLogs = eligibleLogs.filter { !intakeDayKeys.contains($0.dayKey) }

            guard checkInLogs.count >= 3 && nonCheckInLogs.count >= 3 else { continue }

            // 收集唯一 eligible 日键(跨药去重)
            for log in eligibleLogs { uniqueEligibleDayKeys.insert(log.dayKey) }

            let checkInMoods = checkInLogs.compactMap { $0.mood }
            let nonCheckInMoods = nonCheckInLogs.compactMap { $0.mood }

            if checkInMoods.count >= 3 && nonCheckInMoods.count >= 3 {
                let avgCheckIn = Double(checkInMoods.reduce(0) { $0 + $1.rawValue }) / Double(checkInMoods.count)
                let avgNonCheckIn = Double(nonCheckInMoods.reduce(0) { $0 + $1.rawValue }) / Double(nonCheckInMoods.count)
                allObservations.append(Observation(
                    id: "med-mood-\(med.id.uuidString)",
                    label: "\(med.emoji) \(med.name) — \(String(localized: "心情评分"))",
                    value: String(localized: "打卡日 \(String(format: "%.1f", avgCheckIn)) vs 非打卡日 \(String(format: "%.1f", avgNonCheckIn))"),
                    detail: String(localized: "\(med.name) 打卡日(\(checkInMoods.count)天)平均心情 \(String(format: "%.1f", avgCheckIn)) / 5;非打卡日(\(nonCheckInMoods.count)天)平均 \(String(format: "%.1f", avgNonCheckIn)) / 5。仅描述差异,不推断因果。")))
            }

            let checkInSymptoms = checkInLogs.flatMap { $0.symptoms }
            let nonCheckInSymptoms = nonCheckInLogs.flatMap { $0.symptoms }
            if !checkInSymptoms.isEmpty || !nonCheckInSymptoms.isEmpty {
                let checkInRate = Double(checkInSymptoms.count) / Double(max(1, checkInLogs.count))
                let nonCheckInRate = Double(nonCheckInSymptoms.count) / Double(max(1, nonCheckInLogs.count))
                allObservations.append(Observation(
                    id: "med-symptoms-\(med.id.uuidString)",
                    label: "\(med.emoji) \(med.name) — \(String(localized: "追踪项记录频率"))",
                    value: String(localized: "打卡日 \(String(format: "%.1f", checkInRate)) 项/天 vs 非打卡日 \(String(format: "%.1f", nonCheckInRate)) 项/天"),
                    detail: String(localized: "\(med.name) 打卡日平均每天记录 \(String(format: "%.1f", checkInRate)) 个追踪项,非打卡日平均 \(String(format: "%.1f", nonCheckInRate)) 个。仅描述差异,不推断因果。")))
            }
        }

        if allObservations.isEmpty {
            return Correlation(id: "med-tracker", title: String(localized: "用药打卡与追踪记录"),
                               description: String(localized: "观察用药打卡日与非打卡日的追踪记录差异。"),
                               observations: [], sufficientData: false,
                               sampleSize: uniqueEligibleDayKeys.count)
        }

        return Correlation(id: "med-tracker", title: String(localized: "用药打卡与追踪记录"),
                           description: String(localized: "观察用药打卡日与非打卡日的追踪记录差异。"),
                           observations: allObservations, sufficientData: true,
                           sampleSize: uniqueEligibleDayKeys.count)
    }

    // MARK: - 周期长度 × 体重

    private static func cycleLengthWeightCorrelation(_ input: AnalysisInput) -> Correlation? {
        let completed = input.prediction.cycles.filter { $0.length != nil }
        guard completed.count >= 3 else {
            return Correlation(id: "cycle-weight", title: String(localized: "周期长度与体重"),
                               description: String(localized: "观察周期长度变化与体重之间的关系。"),
                               observations: [], sufficientData: false, sampleSize: completed.count)
        }

        // 每个周期的平均体重
        var cycleWeights: [(length: Int, avgWeight: Double)] = []
        let cal = Cal.current
        for cycle in completed {
            guard let length = cycle.length else { continue }
            let start = Cal.startOfDay(cycle.start)
            let end = cal.date(byAdding: .day, value: length, to: start) ?? Date.distantFuture
            let weights = input.logs.filter { $0.date >= start && $0.date < end }.compactMap { $0.weight }
            if let avg = weights.isEmpty ? nil : weights.reduce(0, +) / Double(weights.count) {
                cycleWeights.append((length, avg))
            }
        }

        guard cycleWeights.count >= 3 else {
            return Correlation(id: "cycle-weight", title: String(localized: "周期长度与体重"),
                               description: String(localized: "观察周期长度变化与体重之间的关系。"),
                               observations: [], sufficientData: false, sampleSize: cycleWeights.count)
        }

        // 简单分组:短周期 vs 长周期
        let median = Double(cycleWeights.map(\.length).sorted()[cycleWeights.count / 2])
        let shortCycles = cycleWeights.filter { Double($0.length) < median }
        let longCycles = cycleWeights.filter { Double($0.length) >= median }

        var observations: [Observation] = []

        if shortCycles.count >= 2 {
            let avgW = shortCycles.reduce(0.0) { $0 + $1.avgWeight } / Double(shortCycles.count)
            observations.append(Observation(
                id: "cycle-weight-short",
                label: String(localized: "较短周期(< \(Int(median)) 天)"),
                value: String(localized: "平均体重 \(String(format: "%.1f", avgW)) kg (\(shortCycles.count) 个周期)"),
                detail: String(localized: "\(shortCycles.count) 个较短周期的平均体重为 \(String(format: "%.1f", avgW)) kg。")))
        }
        if longCycles.count >= 2 {
            let avgW = longCycles.reduce(0.0) { $0 + $1.avgWeight } / Double(longCycles.count)
            observations.append(Observation(
                id: "cycle-weight-long",
                label: String(localized: "较长周期(≥ \(Int(median)) 天)"),
                value: String(localized: "平均体重 \(String(format: "%.1f", avgW)) kg (\(longCycles.count) 个周期)"),
                detail: String(localized: "\(longCycles.count) 个较长周期的平均体重为 \(String(format: "%.1f", avgW)) kg。")))
        }

        return Correlation(id: "cycle-weight", title: String(localized: "周期长度与体重"),
                           description: String(localized: "观察周期长度变化与体重之间的关系。"),
                           observations: observations, sufficientData: observations.count >= 2, sampleSize: cycleWeights.count)
    }

    // MARK: - DEBUG 自检

    @discardableResult
    static func selfCheck() -> Bool {
        let empty = AnalysisInput(periodDays: [], logs: [], prediction: .empty,
                                  medications: [], intakes: [])
        let results = analyze(input: empty)
        // 空数据应全部 insufficient
        guard results.allSatisfy({ !$0.sufficientData }) else { return false }
        return true
    }
}
