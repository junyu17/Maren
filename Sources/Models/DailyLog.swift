import Foundation
import SwiftData

/// F3:每日情绪 + 症状打卡。一天一条,3 秒记录。
@Model
final class DailyLog {
    /// 逻辑唯一键:yyyymmdd 整数(见 `DayKey`),与时区无关。
    /// ⚠️ 不用 `@Attribute(.unique)`(CloudKit 不支持);去重由写入路径手动完成
    ///(`DailyLogView.save` / `QuickLogApplier`,先查后写)。
    var dayKey: Int

    /// 心情原始值(1...5),0 表示未选。
    var moodRaw: Int
    /// 能量 1...5,0 表示未选。
    var energy: Int
    /// 疼痛 1...5,-1 表示未选。
    var pain: Int
    /// 睡眠小时数,nil 表示未记录。
    var sleepHours: Double?
    /// 体重(kg),nil 表示未记录。PCOS 相关追踪项。
    var weight: Double?
    /// 已选症状标签(存标签的 key)。
    var symptoms: [String]
    /// 自由备注。
    var note: String
    var updatedAt: Date

    /// 该日在当前时区下的零点。派生属性,不入库。
    var date: Date { DayKey.date(from: dayKey) }

    var mood: Mood? {
        get { Mood(rawValue: moodRaw) }
        set { moodRaw = newValue?.rawValue ?? 0 }
    }

    /// 是否有任何有效内容(用于判断这一天是否「记过」)。
    var hasContent: Bool {
        moodRaw != 0 || energy != 0 || pain >= 0 || sleepHours != nil || weight != nil
            || !symptoms.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(date: Date,
         mood: Mood? = nil,
         energy: Int = 0,
         pain: Int = -1,
         sleepHours: Double? = nil,
         weight: Double? = nil,
         symptoms: [String] = [],
         note: String = "") {
        self.dayKey = DayKey.from(date)
        self.moodRaw = mood?.rawValue ?? 0
        self.energy = energy
        self.pain = pain
        self.sleepHours = sleepHours
        self.weight = weight
        self.symptoms = symptoms
        self.note = note
        self.updatedAt = Date()
    }
}
