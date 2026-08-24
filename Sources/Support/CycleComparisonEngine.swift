import Foundation

/// 「最近完成的周期有什么变化」—— 对比最近完成周期 vs 前 3–6 个周期的历史基线。
/// 确定性纯函数,不联网,不存数据。使用 neutral correlation language,无因果/诊断声明。
enum CycleComparisonEngine {

    struct ComparisonResult {
        let hasEnoughData: Bool
        let message: String          // 数据不足时的提示
        let sampleSize: Int          // 对比了多少个历史周期
        let latestCompletedStart: Date?
        let metrics: [Metric]
    }

    struct Metric: Identifiable {
        let id: String
        let label: String
        let current: String
        let baseline: String
        let change: ChangeDirection
        let note: String

        enum ChangeDirection {
            case shorter, longer, higher, lower, unchanged
        }
    }

    /// 主入口:传入所有经期日和每日记录,返回对比结果。
    static func compare(prediction: CyclePredictor.Prediction,
                        logs: [DailyLog]) -> ComparisonResult {
        // CyclePredictor normally returns cycles in ascending order, but this
        // is a public analysis boundary and callers can construct Prediction
        // values themselves (as tests/imports do).  Select the latest cycle by
        // date so that the comparison semantics do not depend on array order.
        // Exclude cycles with lengths outside 15...120 days — those are likely
        // recording gaps or irregular outliers that would distort comparisons.
        let validRange = 15...120
        let completed = prediction.cycles
            .filter { $0.length != nil && validRange.contains($0.length!) }
            .sorted { $0.start < $1.start }
        // 需要至少 4 个完成周期:最近完成的 + 至少 3 个历史
        guard completed.count >= 4 else {
            return ComparisonResult(
                hasEnoughData: false,
                message: String(localized: "需要至少 4 个完整周期(最近完成 + 3 个历史)才能进行对比分析。继续记录,这里会自动生成你的周期变化报告。"),
                sampleSize: 0,
                latestCompletedStart: nil,
                metrics: [])
        }

        // 最近完成的周期 = 对比目标
        guard let currentCycle = completed.last,
              let currentLength = currentCycle.length else {
            return ComparisonResult(hasEnoughData: false, message: String(localized: "最近完成周期尚未结束。"),
                                    sampleSize: 0, latestCompletedStart: nil, metrics: [])
        }

        // 历史基线 = 前面的周期(最多取 6 个)
        let historical = Array(completed.dropLast())
        let recentHistorical = Array(historical.suffix(6))
        // This is deliberately the number of historical cycles, rather than
        // the number of logs/symptoms.  A cycle with no matching log still
        // contributes a zero to the per-cycle historical frequency.
        let historicalCycleCount = recentHistorical.count
        let sampleSize = historicalCycleCount

        var metrics: [Metric] = []

        // 1. 周期长度变化
        let validLengths = recentHistorical.compactMap { $0.length }
        if let avgHistory = avg(validLengths) {
            let diff = Double(currentLength) - avgHistory
            let dir: Metric.ChangeDirection = diff < 0 ? .shorter : diff > 0 ? .longer : .unchanged
            let note: String
            if abs(diff) <= 2 {
                note = String(localized: "与近期平均值基本一致。")
            } else if diff < 0 {
                note = String(localized: "比近期平均值短 \(Int(abs(diff).rounded())) 天。")
            } else {
                note = String(localized: "比近期平均值长 \(Int(abs(diff).rounded())) 天。")
            }
            metrics.append(Metric(
                id: "cycle-length",
                label: String(localized: "周期长度"),
                current: String(localized: "\(currentLength) 天"),
                baseline: String(localized: "平均 \(Int(avgHistory.rounded())) 天"),
                change: dir,
                note: note))
        }

        // 2. 经期持续天数变化
        let currentPeriodDays = currentCycle.periodDays
        let historicalPeriodDays = recentHistorical.map(\.periodDays)
        if let avgHistory = avg(historicalPeriodDays) {
            let diff = Double(currentPeriodDays) - avgHistory
            let dir: Metric.ChangeDirection = diff < 0 ? .shorter : diff > 0 ? .longer : .unchanged
            let note: String
            if abs(diff) < 1.0 {
                note = String(localized: "与近期平均值基本一致。")
            } else {
                note = String(localized: "比近期平均值\(diff > 0 ? "长" : "短") \(String(format: "%.1f", abs(diff))) 天。")
            }
            metrics.append(Metric(
                id: "period-length",
                label: String(localized: "经期持续天数"),
                current: String(localized: "\(currentPeriodDays) 天"),
                baseline: String(localized: "平均 \(String(format: "%.1f", avgHistory)) 天"),
                change: dir,
                note: note))
        }

        // 3. 心情对比
        let currentMoods = logsForCycle(currentCycle, logs: logs).compactMap { $0.mood }
        let historicalMoods = recentHistorical.flatMap { cycle in logsForCycle(cycle, logs: logs).compactMap { $0.mood } }
        if !currentMoods.isEmpty && !historicalMoods.isEmpty {
            let currentAvg = Double(currentMoods.reduce(0) { $0 + $1.rawValue }) / Double(currentMoods.count)
            let histAvg = Double(historicalMoods.reduce(0) { $0 + $1.rawValue }) / Double(historicalMoods.count)
            let diff = currentAvg - histAvg
            let dir: Metric.ChangeDirection = diff < -0.3 ? .lower : diff > 0.3 ? .higher : .unchanged
            let note = abs(diff) < 0.3
                ? String(localized: "与近期心情平均值基本一致。")
                : String(localized: "比近期平均值\(diff > 0 ? "高" : "低") \(String(format: "%.1f", abs(diff))) 分。")
            metrics.append(Metric(
                id: "mood",
                label: String(localized: "心情"),
                current: String(localized: "平均 \(String(format: "%.1f", currentAvg)) 分"),
                baseline: String(localized: "近期平均 \(String(format: "%.1f", histAvg)) 分"),
                change: dir,
                note: note))
        }

        // 4. 睡眠对比
        let currentSleeps = logsForCycle(currentCycle, logs: logs).compactMap { $0.sleepHours }
        let historicalSleeps = recentHistorical.flatMap { cycle in logsForCycle(cycle, logs: logs).compactMap { $0.sleepHours } }
        if !currentSleeps.isEmpty && !historicalSleeps.isEmpty {
            let currentAvg = currentSleeps.reduce(0, +) / Double(currentSleeps.count)
            let histAvg = historicalSleeps.reduce(0, +) / Double(historicalSleeps.count)
            let diff = currentAvg - histAvg
            let dir: Metric.ChangeDirection = diff < -0.3 ? .lower : diff > 0.3 ? .higher : .unchanged
            let note = abs(diff) < 0.3
                ? String(localized: "与近期睡眠平均值基本一致。")
                : String(localized: "比近期平均值\(diff > 0 ? "多" : "少") \(String(format: "%.1f", abs(diff))) 小时。")
            metrics.append(Metric(
                id: "sleep",
                label: String(localized: "睡眠"),
                current: String(localized: "平均 \(String(format: "%.1f", currentAvg)) 小时"),
                baseline: String(localized: "近期平均 \(String(format: "%.1f", histAvg)) 小时"),
                change: dir,
                note: note))
        }

        // 5. 体重对比
        let currentWeights = logsForCycle(currentCycle, logs: logs).compactMap { $0.weight }
        let historicalWeights = recentHistorical.flatMap { cycle in logsForCycle(cycle, logs: logs).compactMap { $0.weight } }
        if !currentWeights.isEmpty && !historicalWeights.isEmpty {
            let currentAvg = currentWeights.reduce(0, +) / Double(currentWeights.count)
            let histAvg = historicalWeights.reduce(0, +) / Double(historicalWeights.count)
            let diff = currentAvg - histAvg
            let dir: Metric.ChangeDirection = diff < -0.5 ? .lower : diff > 0.5 ? .higher : .unchanged
            let note = abs(diff) < 0.5
                ? String(localized: "与近期体重平均值基本一致。")
                : String(localized: "比近期平均值\(diff > 0 ? "高" : "低") \(String(format: "%.1f", abs(diff))) kg。")
            metrics.append(Metric(
                id: "weight",
                label: String(localized: "体重"),
                current: String(localized: "平均 \(String(format: "%.1f", currentAvg)) kg"),
                baseline: String(localized: "近期平均 \(String(format: "%.1f", histAvg)) kg"),
                change: dir,
                note: note))
        }

        // 6. 追踪项频次对比 —— 按历史周期数归一化为每周期平均次数
        let currentSymptoms = logsForCycle(currentCycle, logs: logs).flatMap { $0.symptoms }
        if !currentSymptoms.isEmpty {
            let currentCounts = frequency(currentSymptoms)
            let histSymptomsTotal = recentHistorical.flatMap { cycle in logsForCycle(cycle, logs: logs).flatMap { $0.symptoms } }
            let histCountsTotal = frequency(histSymptomsTotal)
            let histCountPerCycle = histCountsTotal.map {
                (key: $0.key, count: Double($0.count) / Double(historicalCycleCount))
            }
            let histDict = Dictionary(uniqueKeysWithValues: histCountPerCycle.map { ($0.key, $0.count) })
            let topCurrent = currentCounts.prefix(3)
            for (key, count) in topCurrent {
                let histAvg = histDict[key] ?? 0
                let note: String
                if histAvg < 0.5 {
                    note = String(localized: "这是近期较少记录的追踪项。")
                } else {
                    note = String(localized: "与近期每周期约 \(String(format: "%.1f", histAvg)) 次的记录频率相近。")
                }
                metrics.append(Metric(
                    id: "tracker-\(key)",
                    label: Symptoms.label(for: key),
                    current: String(format: String(localized: "最近完成周期 %lld 次"), count),
                    baseline: String(localized: "近期每周期约 \(String(format: "%.1f", histAvg)) 次"),
                    change: Double(count) > histAvg + 0.5 ? .higher : Double(count) < histAvg - 0.5 ? .lower : .unchanged,
                    note: note))
            }
        }

        return ComparisonResult(
            hasEnoughData: true,
            message: "",
            sampleSize: sampleSize,
            latestCompletedStart: currentCycle.start,
            metrics: metrics)
    }

    // MARK: - 工具函数

    /// 找出某个周期范围内的 DailyLog。
    private static func logsForCycle(_ cycle: CyclePredictor.CycleRecord, logs: [DailyLog]) -> [DailyLog] {
        let cal = Cal.current
        let start = Cal.startOfDay(cycle.start)
        guard let length = cycle.length else { return [] }
        let end = cal.date(byAdding: .day, value: length, to: start) ?? Date.distantFuture
        return logs.filter { let d = $0.date; return d >= start && d < end }
    }

    private static func avg(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func frequency(_ items: [String]) -> [(key: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.map { (key: $0.key, count: $0.value) }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.key < $1.key
        }
    }

    // MARK: - DEBUG 自检

    @discardableResult
    static func selfCheck() -> Bool {
        // 空数据不崩溃
        let result = compare(prediction: .empty, logs: [])
        guard !result.hasEnoughData else { return false }
        return true
    }
}
