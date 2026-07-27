import Foundation
import UserNotifications

/// F8:本地提醒通知。全部走系统本地通知,**不联网、无推送服务器**,符合本地优先。
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var authorized: Bool = false
    /// 用户明确拒绝过通知权限。此时再调 requestAuthorization 系统不会再弹窗,
    /// 必须引导用户去「系统设置」里手动打开,否则按钮就是个死胡同。
    @Published var denied: Bool = false

    private let center = UNUserNotificationCenter.current()
    private let dailyId = "vela.daily.log"
    private let periodId = "vela.period.upcoming"

    func refreshAuthorization() {
        center.getNotificationSettings { settings in
            Task { @MainActor in
                self.authorized = (settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional)
                self.denied = (settings.authorizationStatus == .denied)
            }
        }
    }

    /// 请求授权。
    func requestAuthorization() async {
        do {
            authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorized = false
        }
        refreshAuthorization() // 同步 denied 状态
    }

    /// 每日记录提醒:每天固定时刻。
    func scheduleDailyReminder(enabled: Bool, hour: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [dailyId])
        guard enabled, authorized else { return }

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0

        let content = UNMutableNotificationContent()
        content.title = String(localized: "记录一下今天")
        content.body = String(localized: "花 3 秒记下今天的心情和身体感受吧。")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyId, content: content, trigger: trigger))
    }

    /// 经期临近提醒:在预测经期首日前 2 天。
    func schedulePeriodReminder(enabled: Bool, nextPeriodStart: Date?) {
        center.removePendingNotificationRequests(withIdentifiers: [periodId])
        guard enabled, authorized, let start = nextPeriodStart else { return }

        let cal = Cal.current
        guard let fireDate = cal.date(byAdding: .day, value: -2, to: start),
              fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "经期可能快来了")
        content.body = String(localized: "预测你的经期约在两天后,可以提前做点准备。")
        content.sound = .default

        var comps = cal.dateComponents([.year, .month, .day], from: fireDate)
        comps.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: periodId, content: content, trigger: trigger))
    }

    // MARK: - 层级 2 · 用药提醒

    /// 为单个药安排/取消每日提醒。药的增删改后调用。
    func scheduleMedicationReminder(id: String, name: String,
                                    enabled: Bool, hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled, authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "该吃药啦")
        content.body = String(localized: "记得服用「\(name)」,别忘了在 app 里打个卡。")
        content.sound = .default

        var comps = DateComponents()
        // 防御性 clamp:若有越界值(导入/手表写入),UNCalendarNotificationTrigger 会静默不触发。
        comps.hour = min(max(hour, 0), 23)
        comps.minute = min(max(minute, 0), 59)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// 撤销某个药的提醒(删除药时)。
    func cancelMedicationReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
