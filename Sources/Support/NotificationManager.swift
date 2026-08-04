import Foundation
import UserNotifications

/// F8 + Pro 高级提醒:本地通知。全部走系统本地通知,**不联网、无推送服务器**,符合本地优先。
///
/// 分层:
/// - 免费:每日记录提醒、经期临近提醒(提前 2 天)、用药单次每日提醒。
/// - Pro:经期提前天数自定义(1–5)、PMS/黄体期关怀提醒、按周期阶段的智能提醒、
///   用药多时段 + 按周几排程。Pro 调度入口都由调用方用 `Store.shared.premium` 把关。
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
    private let pmsId = "vela.pms.selfcare"
    private let smartId = "vela.smart.luteal"

    /// 用户偏好:锁屏上隐藏通知里的敏感健康信息(经期/黄体期等)。
    /// 开启后,经期/PMS/智能提醒的正文改为中性文案,避免旁人瞥见健康细节。
    static let hideSensitiveKey = "notif.hideSensitiveContent"
    static var hideSensitiveContent: Bool {
        get { UserDefaults.standard.bool(forKey: hideSensitiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideSensitiveKey) }
    }

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

    // MARK: - 免费 · 每日记录提醒

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

    // MARK: - 免费 · 经期临近提醒(提前天数 Pro 可自定义)

    /// 经期临近提醒:在预测经期首日前 `advanceDays` 天。
    /// 免费层调用方传 2;Pro 传 1–5(由设置页控制)。
    func schedulePeriodReminder(enabled: Bool, advanceDays: Int, nextPeriodStart: Date?) {
        center.removePendingNotificationRequests(withIdentifiers: [periodId])
        guard enabled, authorized, let start = nextPeriodStart else { return }

        let days = min(max(advanceDays, 1), 5)
        let cal = Cal.current
        guard let fireDate = cal.date(byAdding: .day, value: -days, to: start),
              fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        if Self.hideSensitiveContent {
            content.title = String(localized: "Maren")
            content.body = String(localized: "打开 Maren 查看今天的提醒。")
        } else {
            content.title = String(localized: "经期可能快来了")
            content.body = String(localized: "预测你的经期约在 \(days) 天后,可以提前做点准备。")
        }
        content.sound = .default

        var comps = cal.dateComponents([.year, .month, .day], from: fireDate)
        comps.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: periodId, content: content, trigger: trigger))
    }

    // MARK: - Pro · PMS / 黄体期关怀提醒

    /// 在预测经期前 `pmsLeadDays` 天(黄体期末)给一条「对自己好点」的提醒。
    /// Pro 专用;调用方负责用 `Store.shared.premium` 把关。
    func schedulePMSReminder(enabled: Bool, nextPeriodStart: Date?) {
        center.removePendingNotificationRequests(withIdentifiers: [pmsId])
        guard enabled, authorized, let start = nextPeriodStart else { return }

        let lead = ProReminderSettings.pmsLeadDays
        let cal = Cal.current
        guard let fireDate = cal.date(byAdding: .day, value: -lead, to: start),
              fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        if Self.hideSensitiveContent {
            content.title = String(localized: "Maren")
            content.body = String(localized: "打开 Maren 查看今天的提醒。")
        } else {
            content.title = String(localized: "对自己好一点")
            content.body = String(localized: "经期临近,黄体期里情绪和身体可能起伏,温柔对待自己。")
        }
        content.sound = .default

        var comps = cal.dateComponents([.year, .month, .day], from: fireDate)
        comps.hour = 10
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: pmsId, content: content, trigger: trigger))
    }

    // MARK: - Pro · 按周期阶段的智能提醒

    /// 进入黄体期时,根据用户自己的记录给一条个性化提醒(如「焦虑常在黄体期升高」)。
    /// Pro 专用;调用方负责用 `Store.shared.premium` 把关。
    func scheduleSmartReminders(enabled: Bool,
                                prediction p: CyclePredictor.Prediction,
                                logs: [DailyLog]) {
        center.removePendingNotificationRequests(withIdentifiers: [smartId])
        guard enabled, authorized else { return }
        let reminders = SmartReminderEngine.generate(prediction: p, logs: logs)
        guard let r = reminders.first else { return }

        let content = UNMutableNotificationContent()
        if Self.hideSensitiveContent {
            content.title = String(localized: "Maren")
            content.body = String(localized: "打开 Maren 查看今天的提醒。")
        } else {
            content.title = r.title
            content.body = r.body
        }
        content.sound = .default

        var comps = Cal.current.dateComponents([.year, .month, .day, .hour], from: r.fireDate)
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: smartId, content: content, trigger: trigger))
    }

    // MARK: - 用药提醒(免费单次 + Pro 多时段)

    /// 为单个药安排/取消**单次**每日提醒。药的增删改后调用。
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

    /// Pro:为一个药按多时段 + 周几排程。每个 (时段 × 周几) 一条重复通知。
    /// 调用前应先 `cancelAllMedicationReminders(notificationId:)` 撤掉旧排期。
    /// - Returns: 是否全部排上。iOS 对 pending 本地通知有 **64 条硬上限**,
    ///   多药叠加(2 种药全时段全周几即 84 条)会超限,超出的通知被系统静默丢弃
    ///   (不加也不报错)——所以排程前先统计,超限就截断并返回 false 供界面提示。
    @discardableResult
    func scheduleMedicationSlots(notificationId: String, name: String, slots: [ReminderSlot]) async -> Bool {
        guard authorized, !slots.isEmpty else { return false }
        let content = { () -> UNMutableNotificationContent in
            let c = UNMutableNotificationContent()
            c.title = String(localized: "该吃药啦")
            c.body = String(localized: "记得服用「\(name)」,别忘了在 app 里打个卡。")
            c.sound = .default
            return c
        }
        // 本次要排的通知条数。
        let capped = Array(slots.prefix(MedicationSlotsPolicy.maxSlots))
        var needed = 0
        for slot in capped {
            needed += slot.weekdays.isEmpty ? 1 : slot.weekdays.count
        }
        // 统计当前 pending 总数(含经期/PMS/智能/每日提醒等)。
        let pendingCount = await center.pendingNotificationRequests().count
        let available = 64 - pendingCount
        if available < needed {
            // 超限:只排得下的部分排上,多的丢弃,并告知调用方。
            var budget = max(available, 0)
            for (i, slot) in capped.enumerated() where budget > 0 {
                if slot.weekdays.isEmpty {
                    var c = DateComponents()
                    c.hour = slot.hour; c.minute = slot.minute
                    try? await center.add(UNNotificationRequest(
                        identifier: "\(notificationId).s\(i)", content: content(),
                        trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
                    budget -= 1
                } else {
                    for w in slot.weekdays where budget > 0 {
                        var c = DateComponents()
                        c.hour = slot.hour; c.minute = slot.minute; c.weekday = w
                        try? await center.add(UNNotificationRequest(
                            identifier: "\(notificationId).s\(i).w\(w)", content: content(),
                            trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
                        budget -= 1
                    }
                }
            }
            return false
        }
        for (i, slot) in capped.enumerated() {
            if slot.weekdays.isEmpty {
                var c = DateComponents()
                c.hour = slot.hour; c.minute = slot.minute
                try? await center.add(UNNotificationRequest(
                    identifier: "\(notificationId).s\(i)", content: content(),
                    trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
            } else {
                for w in slot.weekdays {
                    var c = DateComponents()
                    c.hour = slot.hour; c.minute = slot.minute; c.weekday = w
                    try? await center.add(UNNotificationRequest(
                        identifier: "\(notificationId).s\(i).w\(w)", content: content(),
                        trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: true)))
                }
            }
        }
        return true
    }

    /// 撤销某个药的全部通知(单次 + 所有时段/周几)。增删改与删除药时调用。
    /// 用 `allReminderNotificationIds()` 的确定性 id 集合,不需要旧的 slot id,无竞态。
    func cancelAllMedicationReminders(notificationId: String) {
        // notificationId 形如 "vela.med.<uuid>";单次 id 就是它本身,时段 id 是它的前缀扩展。
        // 直接撤掉「单次 + 各下标/周几」全套(不存在的 id 会被忽略)。
        var ids = [notificationId]
        for i in 0..<MedicationSlotsPolicy.maxSlots {
            ids.append("\(notificationId).s\(i)")
            for w in 1...7 { ids.append("\(notificationId).s\(i).w\(w)") }
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 撤销某个药的单次提醒(保留兼容;删除药时用 cancelAll 更彻底)。
    func cancelMedicationReminder(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
