import Foundation
import SwiftData

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
}
