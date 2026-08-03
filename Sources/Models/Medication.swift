import Foundation
import SwiftData

/// 层级 2 · 用药 / 补剂定义(立项书 F8 提到的「吃药提醒」;PCOS 常吃二甲双胍/肌醇,ADHD 人群也需要)。
///
/// 提醒分两档:
/// - 免费:单次每日提醒(`reminderEnabled` / `reminderHour` / `reminderMinute`)。
/// - Pro:多时段 + 按周几(`proScheduleEnabled` + `scheduleSlotsJSON`),覆盖单次提醒。
@Model
final class Medication {
    /// 本 app 内的稳定标识(UUID,创建时生成)。不用 `@Attribute(.unique)`(CloudKit 不支持)。
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "💊"
    var reminderEnabled: Bool = false
    var reminderHour: Int = 9      // 0...23
    var reminderMinute: Int = 0    // 0/30 等
    /// Pro:启用多时段 / 按周几的高级排程(开启后覆盖单次提醒)。
    var proScheduleEnabled: Bool = false
    /// Pro:`[ReminderSlot]` 的 JSON。非 Pro 或未启用时为 "[]"。
    var scheduleSlotsJSON: String = "[]"
    var createdAt: Date = Date.now

    init(name: String, emoji: String = "💊",
         reminderEnabled: Bool = false, reminderHour: Int = 9, reminderMinute: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.proScheduleEnabled = false
        self.scheduleSlotsJSON = "[]"
        self.createdAt = Date()
    }

    /// 通知标识符,便于按药增删排期(单次提醒用)。
    var notificationId: String { "vela.med.\(id.uuidString)" }

    /// Pro 排程时段(解码;失败返回空)。
    var slots: [ReminderSlot] {
        guard let data = scheduleSlotsJSON.data(using: .utf8),
              let arr = try? JSONDecoder().decode([ReminderSlot].self, from: data) else { return [] }
        return arr
    }

    /// Pro 排程时段编码写入。
    func setSlots(_ slots: [ReminderSlot]) {
        let capped = Array(slots.prefix(MedicationSlotsPolicy.maxSlots))
        if let data = try? JSONEncoder().encode(capped),
           let s = String(data: data, encoding: .utf8) {
            scheduleSlotsJSON = s
        } else {
            scheduleSlotsJSON = "[]"
        }
    }

    /// 该药当前所有可能的通知标识符(单次 + 各时段 × 各周几),供「先全撤再重排」用。
    /// 用确定性的下标方案,不依赖旧的 slot id,避免增删后残留。
    func allReminderNotificationIds() -> [String] {
        var ids = [notificationId] // 单次
        for i in 0..<MedicationSlotsPolicy.maxSlots {
            ids.append("\(notificationId).s\(i)")                 // 该时段每天
            for w in 1...7 { ids.append("\(notificationId).s\(i).w\(w)") } // 该时段某周几
        }
        return ids
    }
}

/// 某天某药「已服用」的打卡记录。存在即表示当天已吃。
@Model
final class MedicationIntake {
    /// 逻辑唯一键 = 药 id + 日键,防止一天重复打卡。
    /// ⚠️ 不用 `@Attribute(.unique)`(CloudKit 不支持);去重由 `DailyLogView.toggleMed` 先查后写。
    var key: String = ""
    var medicationId: UUID = UUID()
    var dayKey: Int = 0
    var takenAt: Date = Date.now

    init(medicationId: UUID, dayKey: Int) {
        self.key = "\(medicationId.uuidString)-\(dayKey)"
        self.medicationId = medicationId
        self.dayKey = dayKey
        self.takenAt = Date()
    }
}
