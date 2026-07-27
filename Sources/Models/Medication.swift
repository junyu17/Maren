import Foundation
import SwiftData

/// 层级 2 · 用药 / 补剂定义(立项书 F8 提到的「吃药提醒」;PCOS 常吃二甲双胍/肌醇,ADHD 人群也需要)。
@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var reminderEnabled: Bool
    var reminderHour: Int      // 0...23
    var reminderMinute: Int    // 0/30 等
    var createdAt: Date

    init(name: String, emoji: String = "💊",
         reminderEnabled: Bool = false, reminderHour: Int = 9, reminderMinute: Int = 0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.createdAt = Date()
    }

    /// 通知标识符,便于按药增删排期。
    var notificationId: String { "vela.med.\(id.uuidString)" }
}

/// 某天某药「已服用」的打卡记录。存在即表示当天已吃。
@Model
final class MedicationIntake {
    /// 唯一键 = 药 id + 日键,防止一天重复打卡。
    @Attribute(.unique) var key: String
    var medicationId: UUID
    var dayKey: Int
    var takenAt: Date

    init(medicationId: UUID, dayKey: Int) {
        self.key = "\(medicationId.uuidString)-\(dayKey)"
        self.medicationId = medicationId
        self.dayKey = dayKey
        self.takenAt = Date()
    }
}
