import AppIntents
import WidgetKit

/// 手表侧快速记录 Intent。写入手表独立 App Group 队列,
/// 由 WatchConnectivityManager.drainWatchQueue() peek 后经 WCSession 发回手机。
/// 只在 watchOS 上暴露;iOS 有独立的 LogPeriodIntent / LogMoodIntent。
struct WatchLogPeriodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Period Flow"
    static var description = IntentDescription(
        "Quickly log your period flow on Apple Watch. The entry is queued and synced to iPhone when Maren is open.")

    @Parameter(title: "Flow Level", default: .medium)
    var flow: FlowLevelAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let todayKey = QuickActionQueue.todayKey()
        let entry = QuickActionEntry.period(flowRaw: flow.flowRaw, dayKey: todayKey)
        let success = QuickActionQueue.append(entry, to: WatchWidgetSnapshotStore.appGroup)
        WidgetCenter.shared.reloadAllTimelines()

        if success {
            return .result(value: true, dialog: IntentDialog(
                "Logged \(flow.rawValue) period flow. It will sync to iPhone when Maren opens."))
        } else {
            throw QuickLogError.persistenceFailed(
                String(localized: "Failed to save period entry. Please try again."))
        }
    }
}

struct WatchLogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Mood"
    static var description = IntentDescription(
        "Quickly log your mood on Apple Watch. The entry is queued and synced to iPhone when Maren is open.")

    @Parameter(title: "Mood", default: .good)
    var mood: MoodAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let todayKey = QuickActionQueue.todayKey()
        let entry = QuickActionEntry.mood(moodRaw: mood.moodRaw, dayKey: todayKey)
        let success = QuickActionQueue.append(entry, to: WatchWidgetSnapshotStore.appGroup)
        WidgetCenter.shared.reloadAllTimelines()

        if success {
            return .result(value: true, dialog: IntentDialog(
                "Logged \(mood.rawValue) mood. It will sync to iPhone when Maren opens."))
        } else {
            throw QuickLogError.persistenceFailed(
                String(localized: "Failed to save mood entry. Please try again."))
        }
    }
}
