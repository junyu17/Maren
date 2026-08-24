import Foundation

// MARK: - 用药多时段排程模型

/// Pro 高级提醒:用药「一天多次 / 按周几」排程里的单个时间点。
///
/// 存储方式:编码成 JSON 存在 `Medication.scheduleSlotsJSON`(SwiftData 单字段,
/// 避免为每个时段建关系表)。
struct ReminderSlot: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var hour: Int      // 0...23
    var minute: Int    // 0...59
    /// 仅在这些周几触发,取值 1...7(1=周日,依 `Calendar.weekday`)。空数组 = 每天。
    var weekdays: [Int]

    init(id: UUID = UUID(), hour: Int = 9, minute: Int = 0, weekdays: [Int] = []) {
        self.id = id
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekdays = weekdays.sorted()
    }

    /// 周几显示文案(如「周一周三」),空数组返回「每天」。用系统本地化的 weekday 符号。
    var weekdaysLabel: String {
        if weekdays.isEmpty { return String(localized: "每天") }
        let symbols = Cal.current.shortWeekdaySymbols // [Sun, Mon, ...] 下标 0-6;weekday 1=Sunday
        let parts = weekdays.sorted().compactMap { w -> String? in
            let idx = w - 1
            return symbols.indices.contains(idx) ? symbols[idx] : nil
        }
        return parts.isEmpty ? String(localized: "每天") : parts.joined(separator: " ")
    }
}

/// Pro 用药排程的单药最多时段数。受系统 64 条 pending 通知上限约束
/// (6 时段 × 7 周几 = 42,加上经期 / PMS / 智能 / 每日提醒仍在 64 内)。
enum MedicationSlotsPolicy {
    static let maxSlots = 6
}

// MARK: - Pro 提醒设置(读写本机 UserDefaults)

/// Pro 高级提醒的开关与参数。免费层不读这些(经期提前固定 2 天)。
enum ProReminderSettings {
    enum Keys {
        static let periodAdvanceDays = "notif.periodAdvanceDays" // 1...5,免费层忽略
        static let pmsEnabled        = "notif.pmsEnabled"
        static let smartEnabled      = "notif.smartEnabled"
        static let pmsLeadDays        = "notif.pmsLeadDays"      // PMS 提前天数,默认 4
    }

    static let advanceRange = 1...5

    /// 经期提前提醒天数。Pro 可改 1–5;免费层始终当 2 用。
    static var periodAdvanceDays: Int {
        let v = UserDefaults.standard.integer(forKey: Keys.periodAdvanceDays)
        return advanceRange.contains(v) ? v : 2
    }
    static var pmsEnabled: Bool { UserDefaults.standard.bool(forKey: Keys.pmsEnabled) }
    static var smartEnabled: Bool { UserDefaults.standard.bool(forKey: Keys.smartEnabled) }
    static var pmsLeadDays: Int {
        let v = UserDefaults.standard.integer(forKey: Keys.pmsLeadDays)
        return (1...10).contains(v) ? v : 4
    }
}

// MARK: - 按周期阶段的智能提醒

/// Pro:基于用户自己的记录,在「进入黄体期」时给一条个性化提醒。
///
/// 复用 `InsightEngine` 的「症状 × 阶段」思路,但只取黄体期:
/// 若某症状明显集中在黄体期(出现 ≥3 次、占比 ≥50%),就提示「你的「焦虑」常在黄体期升高」;
/// 否则若心情在黄体期偏低,提示情绪关怀;都没有就给一条通用的黄体期关怀。
///
/// 触发点 = 预测的下次经期首日 − 黄体期长度(14,见 `PhaseModel`)。
/// 不写死排卵/安全期,只做「趋势关怀」话术,符合全 app 的诚实叙事与免责红线。
enum SmartReminderEngine {

    struct SmartReminder: Identifiable {
        let id: String
        let fireDate: Date   // 已含触发时刻(本地)
        let title: String    // 已本地化
        let body: String     // 已本地化
    }

    /// 黄体期典型长度(天),与 `PhaseModel` 的倒推口径一致。
    private static let lutealLength = 14

    /// 生成进入黄体期的智能提醒(最多 1 条)。数据不足 / 已过期则返回空。
    static func generate(prediction p: CyclePredictor.Prediction,
                         logs: [DailyLog],
                         fireHour: Int = 9) -> [SmartReminder] {
        guard p.hasEnoughData, let nextStart = p.nextPeriodStart else { return [] }
        let cal = Cal.current
        guard let lutealStart = cal.date(byAdding: .day, value: -lutealLength, to: nextStart),
              lutealStart > Cal.startOfDay(Date()) else { return [] }

        let fireDate = fireAt(lutealStart, hour: fireHour)

        // 把每条历史记录归到它当时的阶段(排除算不出的),只关心黄体期。
        let phased = logs.compactMap { log -> (DailyLog, CyclePhase)? in
            let ph = PhaseModel.phaseForPast(log.date, cycles: p.cycles,
                                             avgCycle: p.averageCycleLength,
                                             avgPeriod: p.averagePeriodLength)
            return ph == .unknown ? nil : (log, ph)
        }

        let title = String(localized: "进入黄体期")
        let body: String
        if let sym = topSymptomInLuteal(phased) {
            // 如:你的「焦虑」常在黄体期升高,这几天注意休息。
            body = String(localized: "「\(sym)」在你的黄体期出现得更多,这几天多留意自己。")
        } else if moodLowerInLuteal(phased) {
            body = String(localized: "你的心情在黄体期通常偏低,这几天多关照自己。")
        } else {
            body = String(localized: "黄体期情绪和身体容易起伏,对自己温柔一点。")
        }
        return [SmartReminder(id: "vela.smart.luteal", fireDate: fireDate, title: title, body: body)]
    }

    /// 仅用于设置页预览(不调度),返回当前数据下会显示的文案;数据不足返回 nil。
    static func preview(prediction p: CyclePredictor.Prediction, logs: [DailyLog]) -> String? {
        generate(prediction: p, logs: logs).first?.body
    }

    // MARK: - 私有统计

    private static func fireAt(_ day: Date, hour: Int) -> Date {
        var c = Cal.current.dateComponents([.year, .month, .day], from: day)
        c.hour = min(max(hour, 0), 23)
        c.minute = 0
        return Cal.current.date(from: c) ?? day
    }

    /// 找出明显集中在黄体期的症状(出现 ≥3 次、黄体期占比 ≥50%),返回显示名。
    private static func topSymptomInLuteal(_ phased: [(DailyLog, CyclePhase)]) -> String? {
        var counts: [String: (inLuteal: Int, total: Int)] = [:]
        for (log, ph) in phased {
            for s in log.symptoms {
                var e = counts[s] ?? (0, 0)
                e.total += 1
                if ph == .luteal { e.inLuteal += 1 }
                counts[s] = e
            }
        }
        let best = counts.first { _, v in v.total >= 3 && Double(v.inLuteal) / Double(v.total) >= 0.5 }
        return best.map { Symptoms.label(for: $0.key) }
    }

    /// 心情在黄体期是否明显偏低(黄体期与他期各 ≥3 条,他期均值 − 黄体期均值 ≥ 0.6)。
    private static func moodLowerInLuteal(_ phased: [(DailyLog, CyclePhase)]) -> Bool {
        let entries = phased.compactMap { item -> (Int, CyclePhase)? in
            guard let m = item.0.mood else { return nil }
            return (m.rawValue, item.1)
        }
        let luteal = entries.filter { $0.1 == .luteal }.map(\.0)
        let others = entries.filter { $0.1 != .luteal }.map(\.0)
        guard luteal.count >= 3, others.count >= 3 else { return false }
        let lutealAvg = Double(luteal.reduce(0, +)) / Double(luteal.count)
        let otherAvg = Double(others.reduce(0, +)) / Double(others.count)
        return (otherAvg - lutealAvg) >= 0.6
    }
}
