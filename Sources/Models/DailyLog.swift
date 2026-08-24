import Foundation
import SwiftData

/// F3:每日情绪 + 症状打卡。一天一条,3 秒记录。
@Model
final class DailyLog {
    /// 逻辑唯一键:yyyymmdd 整数(见 `DayKey`),与时区无关。
    /// 一天一条;去重由写入路径手动完成(`DailyLogView.save` / `QuickLogApplier`,
    /// 先查后写),启动时再由 `DedupSweep` 兜底合并。
    var dayKey: Int = 0

    /// 心情原始值(1...5),0 表示未选。
    var moodRaw: Int = 0
    /// 能量 1...5,0 表示未选。
    var energy: Int = 0
    /// 疼痛 1...5,-1 表示未选。
    var pain: Int = -1
    /// 睡眠小时数,nil 表示未记录。
    var sleepHours: Double?
    /// 体重(kg),nil 表示未记录。PCOS 相关追踪项。
    var weight: Double?
    /// 当天步数,nil 表示未记录。
    var steps: Int?
    /// 当天锻炼分钟数,nil 表示未记录。
    var exerciseMinutes: Int?
    /// 基础体温(℃),nil 表示未记录。
    var basalBodyTemperatureCelsius: Double?
    /// 点滴出血/经间期出血记录。nil = 未记录;true = 有;false = 无(显式记录无)。
    var spotting: Bool?
    /// 来源标记:由 Apple Health 导入的字段名集合,用于防回写与不覆盖手动值。
    /// 可能值: "sleep", "weight", "basalBodyTemperature", "spotting", "steps", "exercise"
    var healthImportedFields: [String] = []
    /// 已选症状标签(存标签的 key)。
    var symptoms: [String] = []
    /// 自由备注。
    var note: String = ""
    var updatedAt: Date = Date.now

    /// 该日在当前时区下的零点。派生属性,不入库。
    var date: Date { DayKey.date(from: dayKey) }

    var mood: Mood? {
        get { Mood(rawValue: moodRaw) }
        set { moodRaw = newValue?.rawValue ?? 0 }
    }

    /// 是否有任何有效内容(用于判断这一天是否「记过」)。
    var hasContent: Bool {
        moodRaw != 0 || energy != 0 || pain >= 0 || sleepHours != nil || weight != nil
            || steps != nil || exerciseMinutes != nil
            || basalBodyTemperatureCelsius != nil || spotting != nil
            || !symptoms.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(date: Date,
         mood: Mood? = nil,
         energy: Int = 0,
         pain: Int = -1,
         sleepHours: Double? = nil,
         weight: Double? = nil,
         steps: Int? = nil,
         exerciseMinutes: Int? = nil,
         basalBodyTemperatureCelsius: Double? = nil,
         spotting: Bool? = nil,
         symptoms: [String] = [],
         note: String = "") {
        self.dayKey = DayKey.from(date)
        self.moodRaw = mood?.rawValue ?? 0
        self.energy = energy
        self.pain = pain
        self.sleepHours = sleepHours
        self.weight = weight
        self.steps = steps
        self.exerciseMinutes = exerciseMinutes
        self.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
        self.spotting = spotting
        self.symptoms = symptoms
        self.note = note
        self.updatedAt = Date()
    }
}
