import Foundation

/// 独立于 SwiftData 的只读样本数据集,用于 SampleExperienceView。
/// 所有结构体都是 value type(immutable),绝不会写入真实数据库。
enum SampleData {

    // MARK: - 轻量镜像结构体(与 SwiftData 模型同构,但是 struct)

    struct SPeriodDay: Identifiable {
        let dayKey: Int
        let flowRaw: Int
        var id: Int { dayKey }
        var date: Date { DayKey.date(from: dayKey) }
        var flow: FlowLevel { FlowLevel(rawValue: flowRaw) ?? .medium }
    }

    struct SDailyLog: Identifiable {
        let dayKey: Int
        let moodRaw: Int      // 0 = unset
        let energy: Int       // 0 = unset
        let pain: Int         // -1 = unset
        let sleepHours: Double?
        let weight: Double?
        let basalBodyTemperatureCelsius: Double?
        let spotting: Bool?
        let symptoms: [String]
        let note: String
        var id: Int { dayKey }
        var date: Date { DayKey.date(from: dayKey) }
        var mood: Mood? { moodRaw > 0 ? Mood(rawValue: moodRaw) : nil }

        init(dayKey: Int, moodRaw: Int, energy: Int, pain: Int,
             sleepHours: Double?, weight: Double?,
             basalBodyTemperatureCelsius: Double? = nil, spotting: Bool? = nil,
             symptoms: [String], note: String) {
            self.dayKey = dayKey
            self.moodRaw = moodRaw
            self.energy = energy
            self.pain = pain
            self.sleepHours = sleepHours
            self.weight = weight
            self.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
            self.spotting = spotting
            self.symptoms = symptoms
            self.note = note
        }
    }

    struct SMedication {
        let name: String
        let emoji: String
    }

    struct SMedicationIntake {
        let dayKey: Int
        let medicationName: String
    }

    // MARK: - 完整样本数据集

    /// 6 个历史经期(含当前进行中的),模拟约 6 个月数据。
    /// 周期长度:29, 31, 28, 30, 32, 29(均值约 29.8 天,标准差约 1.5 天 →「规律」)。
    /// 经期长度:4–5 天,流量由轻→重→轻。
    static let periodDays: [SPeriodDay] = {
        var result: [SPeriodDay] = []
        let cal = Cal.current
        let today = Cal.startOfDay(Date())

        // 6 段经期起点(距今天数),模拟真实间隔
        let cycleOffsets = [-182, -153, -122, -92, -62, -33]
        let periodSpans = [5, 4, 5, 4, 5, 4] // 每段经期天数
        let flowPatterns: [[FlowLevel]] = [
            [.light, .medium, .heavy, .medium, .light],
            [.light, .medium, .heavy, .light],
            [.spotting, .light, .medium, .heavy, .medium],
            [.light, .medium, .heavy, .light],
            [.spotting, .light, .medium, .heavy, .medium],
            [.light, .medium, .medium, .light],
        ]

        for (i, offset) in cycleOffsets.enumerated() {
            for (j, flow) in flowPatterns[i].enumerated() {
                if let d = cal.date(byAdding: .day, value: offset + j, to: today) {
                    result.append(SPeriodDay(dayKey: DayKey.from(d), flowRaw: flow.rawValue))
                }
            }
        }
        return result
    }()

    /// 跨阶段的每日记录,覆盖经期/卵泡/排卵/黄体四个阶段。
    static let dailyLogs: [SDailyLog] = {
        let cal = Cal.current
        let today = Cal.startOfDay(Date())

        func dk(_ offset: Int) -> Int {
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return 0 }
            return DayKey.from(d)
        }

        return [
            // 周期 1(起点 -182)
            SDailyLog(dayKey: dk(-182), moodRaw: 2, energy: 2, pain: 3, sleepHours: 6.5, weight: 58.2,
                      basalBodyTemperatureCelsius: 36.42, spotting: false,
                      symptoms: ["cramps", "fatigue"], note: ""),
            SDailyLog(dayKey: dk(-180), moodRaw: 2, energy: 2, pain: 2, sleepHours: 6.0, weight: nil,
                      basalBodyTemperatureCelsius: 36.31,
                      symptoms: ["cramps"], note: ""),
            SDailyLog(dayKey: dk(-172), moodRaw: 4, energy: 4, pain: -1, sleepHours: 7.5, weight: 57.8,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-164), moodRaw: 5, energy: 5, pain: -1, sleepHours: 8.0, weight: 57.5,
                      symptoms: [], note: "排卵期感觉很好"),
            SDailyLog(dayKey: dk(-158), moodRaw: 3, energy: 3, pain: -1, sleepHours: 7.0, weight: 58.0,
                      symptoms: ["cravings", "irritable"], note: ""),

            // 周期 2(起点 -153)
            SDailyLog(dayKey: dk(-153), moodRaw: 2, energy: 2, pain: 3, sleepHours: 6.0, weight: 58.5,
                      basalBodyTemperatureCelsius: 36.38, spotting: true,
                      symptoms: ["cramps", "fatigue"], note: ""),
            SDailyLog(dayKey: dk(-151), moodRaw: 1, energy: 1, pain: 3, sleepHours: 5.5, weight: nil,
                      basalBodyTemperatureCelsius: 36.25, spotting: false,
                      symptoms: ["cramps", "headache"], note: "头痛厉害"),
            SDailyLog(dayKey: dk(-143), moodRaw: 4, energy: 5, pain: -1, sleepHours: 7.5, weight: 58.0,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-138), moodRaw: 5, energy: 5, pain: -1, sleepHours: 8.0, weight: 57.6,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-132), moodRaw: 2, energy: 2, pain: -1, sleepHours: 6.5, weight: 58.3,
                      symptoms: ["cravings", "irritable"], note: ""),

            // 周期 3(起点 -122)
            SDailyLog(dayKey: dk(-122), moodRaw: 2, energy: 2, pain: 3, sleepHours: 6.0, weight: 58.6,
                      basalBodyTemperatureCelsius: 36.40,
                      symptoms: ["cramps", "fatigue"], note: ""),
            SDailyLog(dayKey: dk(-120), moodRaw: 2, energy: 2, pain: 2, sleepHours: 5.5, weight: nil,
                      basalBodyTemperatureCelsius: 36.28, spotting: true,
                      symptoms: ["cramps"], note: ""),
            SDailyLog(dayKey: dk(-112), moodRaw: 4, energy: 4, pain: -1, sleepHours: 7.5, weight: 58.1,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-105), moodRaw: 5, energy: 5, pain: -1, sleepHours: 8.0, weight: 57.7,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-98), moodRaw: 3, energy: 3, pain: -1, sleepHours: 7.0, weight: 58.2,
                      symptoms: ["cravings"], note: ""),

            // 周期 4(起点 -92)
            SDailyLog(dayKey: dk(-92), moodRaw: 2, energy: 2, pain: 3, sleepHours: 6.0, weight: 58.8,
                      basalBodyTemperatureCelsius: 36.45, spotting: false,
                      symptoms: ["cramps", "fatigue"], note: ""),
            SDailyLog(dayKey: dk(-90), moodRaw: 2, energy: 2, pain: 2, sleepHours: 5.5, weight: nil,
                      basalBodyTemperatureCelsius: 36.35, spotting: true,
                      symptoms: ["cramps"], note: ""),
            SDailyLog(dayKey: dk(-82), moodRaw: 4, energy: 5, pain: -1, sleepHours: 7.5, weight: 58.2,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-75), moodRaw: 5, energy: 5, pain: -1, sleepHours: 8.0, weight: 57.8,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-68), moodRaw: 3, energy: 3, pain: -1, sleepHours: 7.0, weight: 58.5,
                      symptoms: ["cravings", "irritable"], note: ""),

            // 周期 5(起点 -62)
            SDailyLog(dayKey: dk(-62), moodRaw: 2, energy: 2, pain: 3, sleepHours: 6.0, weight: 59.0,
                      basalBodyTemperatureCelsius: 36.47, spotting: false,
                      symptoms: ["cramps", "fatigue"], note: ""),
            SDailyLog(dayKey: dk(-60), moodRaw: 2, energy: 1, pain: 3, sleepHours: 5.5, weight: nil,
                      basalBodyTemperatureCelsius: 36.33,
                      symptoms: ["cramps", "headache"], note: ""),
            SDailyLog(dayKey: dk(-52), moodRaw: 4, energy: 4, pain: -1, sleepHours: 7.5, weight: 58.4,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-45), moodRaw: 5, energy: 5, pain: -1, sleepHours: 8.0, weight: 58.0,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-38), moodRaw: 3, energy: 3, pain: -1, sleepHours: 7.0, weight: 58.6,
                      symptoms: ["cravings"], note: ""),

            // 周期 6(起点 -33, 进行中)
            SDailyLog(dayKey: dk(-33), moodRaw: 2, energy: 2, pain: 3, sleepHours: 6.0, weight: 59.1,
                      basalBodyTemperatureCelsius: 36.50, spotting: false,
                      symptoms: ["cramps", "fatigue"], note: ""),
            SDailyLog(dayKey: dk(-31), moodRaw: 2, energy: 2, pain: 2, sleepHours: 5.5, weight: nil,
                      basalBodyTemperatureCelsius: 36.37, spotting: true,
                      symptoms: ["cramps"], note: ""),
            SDailyLog(dayKey: dk(-23), moodRaw: 4, energy: 4, pain: -1, sleepHours: 7.5, weight: 58.5,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-16), moodRaw: 5, energy: 5, pain: -1, sleepHours: 8.0, weight: 58.1,
                      symptoms: [], note: ""),
            SDailyLog(dayKey: dk(-10), moodRaw: 3, energy: 3, pain: -1, sleepHours: 7.0, weight: 58.7,
                      symptoms: ["cravings", "irritable"], note: ""),
            // 今天
            SDailyLog(dayKey: dk(0), moodRaw: 4, energy: 3, pain: 1, sleepHours: 7.0, weight: 58.8,
                      basalBodyTemperatureCelsius: 36.58,
                      symptoms: ["fatigue"], note: ""),
        ]
    }()

    /// 两种示例用药。
    static let medications: [SMedication] = [
        SMedication(name: "叶酸", emoji: "💊"),
        SMedication(name: "维生素 D", emoji: "☀️"),
    ]

    /// 近 14 天的用药打卡。
    static let intakes: [SMedicationIntake] = {
        let cal = Cal.current
        let today = Cal.startOfDay(Date())
        var result: [SMedicationIntake] = []
        for i in 0..<14 {
            if let d = cal.date(byAdding: .day, value: -i, to: today) {
                result.append(SMedicationIntake(dayKey: DayKey.from(d), medicationName: "叶酸"))
                if i % 2 == 0 {
                    result.append(SMedicationIntake(dayKey: DayKey.from(d), medicationName: "维生素 D"))
                }
            }
        }
        return result
    }()

    // MARK: - 从样本数据构建 CyclePredictor 所需的虚拟 PeriodDay

    /// 将样本期数据转成 CyclePredictor 能接受的格式(仅用于预测计算,不入 SwiftData)。
    static var virtualPeriodDays: [PeriodDay] {
        periodDays.map { PeriodDay(date: $0.date, flow: $0.flow) }
    }

    /// 生成对应的预测结果(使用样本数据)。
    static var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: virtualPeriodDays, manual: nil)
    }

    // MARK: - DEBUG 自检

    /// 纯函数自检:验证样本数据内部一致性。
    @discardableResult
    static func selfCheck() -> Bool {
        // 经期日 key 唯一
        let keys = periodDays.map(\.dayKey)
        guard Set(keys).count == keys.count else { return false }
        // 每日记录 key 唯一
        let logKeys = dailyLogs.map(\.dayKey)
        guard Set(logKeys).count == logKeys.count else { return false }
        // 至少 3 个周期的经期数据
        guard periodDays.count >= 15 else { return false }
        // 预测能跑通
        let p = prediction
        guard p.observedCycleCount >= 3 else { return false }
        return true
    }
}
