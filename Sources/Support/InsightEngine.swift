import Foundation

/// 层级 1 · 设备端关联洞察(立项书 V2「AI 洞察」的第一步,纯本地统计、不联网、不需要真 AI)。
///
/// 原则:
/// - **只说数据支持得住的话**。每条洞察都有最小样本门槛;样本不足就不生成,绝不编。
/// - 把每条历史记录归到它「当时所处的周期阶段」再做关联,而不是只看当前这一个周期。
/// - 结论用「通常 / 倾向」这类措辞,不吹精准,呼应全 app 的诚实叙事。
enum InsightEngine {

    struct Insight: Identifiable {
        let id: String
        let icon: String     // SF Symbol
        let text: String     // 已本地化
        let strength: Int    // 排序用,越大越靠前
    }

    /// 生成洞察列表(已按重要度排序,最多 4 条)。数据不足时返回空数组。
    static func generate(periodDays: [PeriodDay],
                         logs: [DailyLog],
                         prediction p: CyclePredictor.Prediction) -> [Insight] {
        // 给每条日志算出它当时所处的阶段(排除算不出的)。
        let phased: [(log: DailyLog, phase: CyclePhase)] = logs.compactMap { log in
            let ph = PhaseModel.phaseForPast(log.date, cycles: p.cycles,
                                             avgCycle: p.averageCycleLength,
                                             avgPeriod: p.averagePeriodLength)
            return ph == .unknown ? nil : (log, ph)
        }

        var out: [Insight] = []
        out.append(contentsOf: symptomPhaseInsights(phased))
        if let m = moodByPhaseInsight(phased) { out.append(m) }
        if let e = energyByPhaseInsight(phased) { out.append(e) }
        if let r = regularityInsight(p) { out.append(r) }
        if out.isEmpty, let f = topSymptomFallback(logs) { out.append(f) }

        return Array(out.sorted { $0.strength > $1.strength }.prefix(4))
    }

    // MARK: - 症状 × 阶段

    /// 某症状是否明显集中在某个阶段(出现 >= 3 次,且某阶段占比 >= 50%)。
    private static func symptomPhaseInsights(_ phased: [(log: DailyLog, phase: CyclePhase)]) -> [Insight] {
        // symptomKey -> (phase -> count)
        var table: [String: [CyclePhase: Int]] = [:]
        for (log, phase) in phased {
            for s in log.symptoms { table[s, default: [:]][phase, default: 0] += 1 }
        }
        var results: [Insight] = []
        for (key, byPhase) in table {
            let total = byPhase.values.reduce(0, +)
            guard total >= 3, let top = byPhase.max(by: { $0.value < $1.value }) else { continue }
            guard Double(top.value) / Double(total) >= 0.5 else { continue }
            let text = String(localized: "你在\(top.key.label)最常记录「\(Symptoms.label(for: key))」。")
            results.append(Insight(id: "sym-\(key)", icon: "target",
                                   text: text, strength: 100 + top.value))
        }
        return results
    }

    // MARK: - 心情 × 阶段

    private static func moodByPhaseInsight(_ phased: [(log: DailyLog, phase: CyclePhase)]) -> Insight? {
        let entries = phased.compactMap { item in item.log.mood.map { ($0.rawValue, item.phase) } }
        guard entries.count >= 5 else { return nil }
        let avgs = averageByPhase(entries)
        // 至少两个阶段各有 >= 2 条,且高低差 >= 0.8 才算「明显」。
        guard avgs.count >= 2,
              let low = avgs.min(by: { $0.value.avg < $1.value.avg }),
              let high = avgs.max(by: { $0.value.avg < $1.value.avg }),
              high.value.avg - low.value.avg >= 0.8 else { return nil }
        let text = String(localized: "你的心情在\(low.key.label)通常偏低,在\(high.key.label)相对更好。")
        let strength = 80 + Int((high.value.avg - low.value.avg) * 10)
        return Insight(id: "mood-phase", icon: "face.smiling", text: text, strength: strength)
    }

    // MARK: - 能量 × 阶段

    private static func energyByPhaseInsight(_ phased: [(log: DailyLog, phase: CyclePhase)]) -> Insight? {
        let entries = phased.compactMap { item in item.log.energy > 0 ? (item.log.energy, item.phase) : nil }
        guard entries.count >= 5 else { return nil }
        let avgs = averageByPhase(entries)
        guard avgs.count >= 2,
              let low = avgs.min(by: { $0.value.avg < $1.value.avg }),
              let high = avgs.max(by: { $0.value.avg < $1.value.avg }),
              high.value.avg - low.value.avg >= 0.9 else { return nil }
        let text = String(localized: "你的能量在\(low.key.label)通常较低。")
        let strength = 70 + Int((high.value.avg - low.value.avg) * 10)
        return Insight(id: "energy-phase", icon: "bolt", text: text, strength: strength)
    }

    /// 按阶段求均值,只保留样本 >= 2 的阶段。
    private static func averageByPhase(_ entries: [(Int, CyclePhase)]) -> [CyclePhase: (avg: Double, n: Int)] {
        var sum: [CyclePhase: Int] = [:], cnt: [CyclePhase: Int] = [:]
        for (v, ph) in entries { sum[ph, default: 0] += v; cnt[ph, default: 0] += 1 }
        var result: [CyclePhase: (avg: Double, n: Int)] = [:]
        for (ph, n) in cnt where n >= 2 {
            result[ph] = (Double(sum[ph] ?? 0) / Double(n), n)
        }
        return result
    }

    // MARK: - 周期规律度

    private static func regularityInsight(_ p: CyclePredictor.Prediction) -> Insight? {
        let lengths = p.cycles.compactMap { $0.length }.filter { $0 >= 15 && $0 <= 120 }
        guard lengths.count >= 3, let lo = lengths.min(), let hi = lengths.max() else { return nil }
        let text: String
        if hi - lo <= 3, let avg = p.averageCycleLength {
            text = String(localized: "你的周期很规律,稳定在 \(Int(avg.rounded())) 天左右。")
        } else {
            text = String(localized: "最近 \(lengths.count) 个周期长度在 \(lo)–\(hi) 天之间波动。")
        }
        return Insight(id: "regularity", icon: "waveform.path.ecg", text: text, strength: 60)
    }

    // MARK: - 兜底:记录最多的症状

    private static func topSymptomFallback(_ logs: [DailyLog]) -> Insight? {
        var counts: [String: Int] = [:]
        for log in logs { for s in log.symptoms { counts[s, default: 0] += 1 } }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value >= 2 else { return nil }
        let text = String(localized: "你记录最多的追踪项是「\(Symptoms.label(for: top.key))」,共 \(top.value) 次。")
        return Insight(id: "top-symptom", icon: "list.bullet", text: text, strength: 10)
    }
}
