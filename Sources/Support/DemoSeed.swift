import Foundation
import SwiftData

/// 仅用于 App Store 截图:启动参数 `--shot <route>` 直接打开对应界面。
/// Release 构建里恒为 nil,所以线上包没有任何可达的跳转。
enum ScreenshotRoute: String {
    case calendar, perimenopause, today, trends, trackers, paywall, library, search, settings

    static let current: ScreenshotRoute? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--shot"), i + 1 < args.count else { return nil }
        return ScreenshotRoute(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }()

    /// `--shot-query <text>`:搜索截图预填的关键词(随截图语言传入)。
    static let searchQuery: String = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--shot-query"), i + 1 < args.count else { return "" }
        return args[i + 1]
        #else
        return ""
        #endif
    }()

    var tab: Int {
        switch self {
        case .calendar, .search: return 0
        case .today, .trackers, .library: return 1
        case .perimenopause, .trends: return 2
        case .paywall, .settings: return 3
        }
    }
}

/// 仅用于开发自测:传入启动参数 `--seed-demo` 时,写入一批示例数据。
/// 走的是与 UI 完全相同的 insert/save 路径,因此能验证数据模型可写可读。
/// 生产环境不会触发(除非显式带该参数)。
enum DemoSeed {
    static func runIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-demo") else { return }
        let context = ModelContext(container)

        // 幂等:已有经期数据就不重复播种。
        let existing = (try? context.fetch(FetchDescriptor<PeriodDay>())) ?? []
        guard existing.isEmpty else { return }

        let cal = Cal.current
        let today = Cal.startOfDay(Date())

        // 3 段历史经期(相隔约 29–32 天),让预测引擎有 ≥2 个完整周期可学习。
        // 每段 5 天,流量由轻转重再转轻 —— 体现按天记录、不规律友好。
        let spanFlows: [FlowLevel] = [.light, .medium, .heavy, .medium, .light]
        let cycleStartOffsets = [-90, -58, -29] // 距今天数;周期长度 32、29 天
        for startOffset in cycleStartOffsets {
            for (i, flow) in spanFlows.enumerated() {
                if let d = cal.date(byAdding: .day, value: startOffset + i, to: today) {
                    context.insert(PeriodDay(date: d, flow: flow))
                }
            }
        }

        // 跨阶段的每日记录,让「关联洞察」有料可算:
        //   经期日:痛经 + 疲惫、心情/能量偏低;
        //   卵泡/排卵期:心情好、能量高;
        //   黄体期(临近下次经期):食欲变化 + 易怒、心情/能量偏低。
        // 这样能稳定得出「痛经多在经期」「心情在黄体期偏低」等洞察。
        func log(_ offset: Int, mood: Mood, energy: Int, pain: Int, _ symptoms: [String]) {
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return }
            context.insert(DailyLog(date: d, mood: mood, energy: energy, pain: pain,
                                    sleepHours: nil, symptoms: symptoms, note: ""))
        }
        // 周期 1(起点 -90)
        log(-90, mood: .low,   energy: 2, pain: 3, ["cramps", "fatigue"])
        log(-88, mood: .low,   energy: 2, pain: 2, ["cramps"])
        log(-80, mood: .good,  energy: 5, pain: -1, [])
        log(-60, mood: .low,   energy: 2, pain: -1, ["cravings", "irritable"])
        // 周期 2(起点 -58)
        log(-58, mood: .low,   energy: 2, pain: 3, ["cramps", "fatigue"])
        log(-56, mood: .bad,   energy: 1, pain: 3, ["cramps"])
        log(-48, mood: .good,  energy: 5, pain: -1, [])
        log(-43, mood: .great, energy: 5, pain: -1, [])
        log(-31, mood: .low,   energy: 2, pain: -1, ["cravings", "irritable"])
        // 周期 3(起点 -29)
        log(-29, mood: .low,   energy: 2, pain: 3, ["cramps", "fatigue"])
        log(-27, mood: .low,   energy: 2, pain: 2, ["cramps"])
        log(-18, mood: .good,  energy: 4, pain: -1, [])
        log(-3,  mood: .low,   energy: 2, pain: -1, ["cravings"])
        // 今天
        log(0, mood: .good, energy: 3, pain: 1, ["fatigue"])

        try? context.save()
    }

    /// App Store 截图:`--seed-screenshots` 写入 4 段不规律周期(26、41、33 天)和近 90 天
    /// 约九成天数的每日记录,围绝经期症状在最近 30 天明显增多,让摘要、趋势和搜索都有真实内容。
    static func seedScreenshotsIfRequested(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-screenshots") else { return }
        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<PeriodDay>())) ?? []
        guard existing.isEmpty else { return }

        let cal = Cal.current
        let today = Cal.startOfDay(Date())
        func day(_ offset: Int) -> Date? { cal.date(byAdding: .day, value: offset, to: today) }

        // 最近一段经期锚定在本月初,否则在月中截图时,日历页整月一条经期记录都没有
        // ——第一张商店截图就会像一个没人用过的 App。周期间隔仍是 26、41、33 天。
        let dayOfMonth = cal.component(.day, from: today)
        let latestStart = dayOfMonth >= 8 ? -(dayOfMonth - 3) : -5
        let periods: [(start: Int, flows: [FlowLevel])] = [
            (latestStart - 100, [.medium, .heavy, .medium, .light, .light]),
            (latestStart - 74, [.light, .heavy, .heavy, .medium, .light]),
            (latestStart - 33, [.medium, .heavy, .medium, .light]),
            (latestStart, [.medium, .heavy, .medium, .light, .spotting]),
        ]
        var periodDay: [Int: Int] = [:]  // offset -> 周期第几天(0 起)
        for period in periods {
            for (i, flow) in period.flows.enumerated() {
                if let d = day(period.start + i) { context.insert(PeriodDay(date: d, flow: flow)) }
                periodDay[period.start + i] = i
            }
        }
        let starts = periods.map(\.start)

        for offset in -89...(-1) where (offset * 7) % 9 != 0 {
            let recent = offset >= -29
            let dayInPeriod = periodDay[offset]
            let nextStart = starts.first { $0 > offset } ?? 9
            let lateLuteal = nextStart - offset <= 4

            var symptoms: [String] = []
            if dayInPeriod != nil { symptoms.append("cramps") }
            if let d = dayInPeriod, d < 2 { symptoms.append("fatigue") }
            if lateLuteal { symptoms += ["bloating", "irritable"] }
            if offset % (recent ? 2 : 5) == 0 { symptoms.append("hotFlashes") }
            if offset % (recent ? 4 : 7) == 0 { symptoms.append("nightSweats") }
            if offset % 6 == -1 { symptoms.append("insomnia") }
            if offset % 8 == -2 { symptoms.append("brainFog") }
            if recent && offset % 9 == -4 { symptoms.append("jointPain") }
            if offset % 4 == -1 { symptoms.append("walking") }
            if offset % 7 == -3 { symptoms.append("yoga") }

            let mood: Mood
            let energy: Int
            if let d = dayInPeriod {
                mood = d < 2 ? .low : .okay
                energy = d < 2 ? 2 : 3
            } else if lateLuteal {
                mood = offset % 2 == 0 ? .low : .okay
                energy = 2
            } else {
                mood = offset % 3 == 0 ? .great : .good
                energy = offset % 3 == 0 ? 5 : 4
            }
            let pain = dayInPeriod.map { $0 < 2 ? 3 : 1 } ?? -1
            let sleep = symptoms.contains("nightSweats") || symptoms.contains("insomnia")
                ? 5.5 + Double((-offset) % 3) * 0.25
                : 6.75 + Double((-offset) % 4) * 0.25
            let weight = offset % 3 == 0 ? 64.0 + Double((-offset) % 5) * 0.1 : nil

            if let d = day(offset) {
                context.insert(DailyLog(date: d, mood: mood, energy: energy, pain: pain,
                                        sleepHours: sleep, weight: weight, symptoms: symptoms))
            }
        }

        context.insert(DailyLog(date: today, mood: .good, energy: 3, pain: 2,
                                sleepHours: 6.5, weight: 64.2, basalBodyTemperatureCelsius: 36.5,
                                spotting: false, symptoms: ["hotFlashes", "nightSweats", "walking"]))
        try? context.save()
    }

    /// 开发自测:`--seed-dups` 为已存在的某天再插一条重复 `PeriodDay` / `DailyLog`,
    /// 模拟异常导入/快速重复写入产生的重复。`DedupSweep` 启动时会折叠它们。
    /// DailyLog 重复记录除症状外加 headache、其余字段留空,专门验证 sweep 的字段回填与症状并集。
    static func seedDuplicates(_ container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-dups") else { return }
        let context = ModelContext(container)

        if let first = (try? context.fetch(FetchDescriptor<PeriodDay>(sortBy: [.init(\.dayKey)])))?.first {
            context.insert(PeriodDay(date: first.date, flow: first.flow == .heavy ? .light : .heavy))
        }
        if let first = (try? context.fetch(FetchDescriptor<DailyLog>(sortBy: [.init(\.dayKey)])))?.first {
            let dup = DailyLog(date: first.date, mood: nil, energy: 0, pain: -1,
                               sleepHours: nil, weight: nil, symptoms: ["headache"], note: "")
            context.insert(dup)
        }
        try? context.save()
    }
}
