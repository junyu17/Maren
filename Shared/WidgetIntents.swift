import AppIntents
import WidgetKit

// MARK: - AppEnum 参数枚举 (cross-platform)

/// 流量级别 AppEnum,供 AppShortcuts / Siri / Widget Button 使用。
enum FlowLevelAppEnum: String, AppEnum {
    case spotting, light, medium, heavy

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Flow Level")
    static var caseDisplayRepresentations: [FlowLevelAppEnum: DisplayRepresentation] = [
        .spotting: "Spotting",
        .light:    "Light",
        .medium:   "Medium",
        .heavy:    "Heavy",
    ]

    var flowRaw: Int {
        switch self {
        case .spotting: return 0
        case .light:    return 1
        case .medium:   return 2
        case .heavy:    return 3
        }
    }

    init?(flowRaw: Int) {
        switch flowRaw {
        case 0: self = .spotting
        case 1: self = .light
        case 2: self = .medium
        case 3: self = .heavy
        default: return nil
        }
    }
}

/// 心情 AppEnum。
enum MoodAppEnum: String, AppEnum {
    case great, good, okay, low, bad

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Mood")
    static var caseDisplayRepresentations: [MoodAppEnum: DisplayRepresentation] = [
        .great: "Great",
        .good:  "Good",
        .okay:  "Okay",
        .low:   "Low",
        .bad:   "Bad",
    ]

    var moodRaw: Int {
        switch self {
        case .great: return 5
        case .good:  return 4
        case .okay:  return 3
        case .low:   return 2
        case .bad:   return 1
        }
    }

    init?(moodRaw: Int) {
        switch moodRaw {
        case 5: self = .great
        case 4: self = .good
        case 3: self = .okay
        case 2: self = .low
        case 1: self = .bad
        default: return nil
        }
    }
}

// MARK: - 记录经期 Intent (iOS only)

/// 从 Shortcuts / Siri / Widget 按钮快速记录经期。
/// 数据通过 App Group 队列暂存,主 app 启动/激活时落库。
/// 只在 iOS 上暴露:widget 使用 App Group,watch 有独立的 WatchLogPeriodIntent。
#if os(iOS)
struct LogPeriodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Period Flow"
    static var description = IntentDescription(
        "Quickly log your period flow level in Maren. The entry is queued and saved when Maren is open.")
    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$flow) period flow")
    }

    @Parameter(title: "Flow Level", default: .medium)
    var flow: FlowLevelAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let todayKey = QuickActionQueue.todayKey()
        let entry = QuickActionEntry.period(flowRaw: flow.flowRaw, dayKey: todayKey)
        let groupID = WidgetSnapshotStore.appGroup
        let success = QuickActionQueue.append(entry, to: groupID)
        WidgetCenter.shared.reloadAllTimelines()

        if success {
            return .result(value: true, dialog: IntentDialog(
                "Logged \(flow.rawValue) period flow for today. It will be saved when Maren opens."))
        } else {
            throw QuickLogError.persistenceFailed(
                String(localized: "Failed to save period entry. Please try again."))
        }
    }
}
#endif

// MARK: - 记录心情 Intent (iOS only)

#if os(iOS)
struct LogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Mood"
    static var description = IntentDescription(
        "Quickly log your mood in Maren. The entry is queued and saved when Maren is open.")
    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$mood) mood")
    }

    @Parameter(title: "Mood", default: .good)
    var mood: MoodAppEnum

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let todayKey = QuickActionQueue.todayKey()
        let entry = QuickActionEntry.mood(moodRaw: mood.moodRaw, dayKey: todayKey)
        let groupID = WidgetSnapshotStore.appGroup
        let success = QuickActionQueue.append(entry, to: groupID)
        WidgetCenter.shared.reloadAllTimelines()

        if success {
            return .result(value: true, dialog: IntentDialog(
                "Logged \(mood.rawValue) mood for today. It will be saved when Maren opens."))
        } else {
            throw QuickLogError.persistenceFailed(
                String(localized: "Failed to save mood entry. Please try again."))
        }
    }
}
#endif

// MARK: - Intent 错误

enum QuickLogError: LocalizedError {
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let msg): return msg
        }
    }
}

// MARK: - AppShortcutsProvider (iOS only)

/// Siri / Shortcuts 可发现的快捷指令。包含中英文应用名称关键词以提高可发现性。
#if os(iOS)
struct MarenShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPeriodIntent(),
            phrases: [
                "Log period flow in \(.applicationName)",
                "Record my period in \(.applicationName)",
                "Track period in \(.applicationName)",
                "Mark period day in \(.applicationName)",
                "在\(.applicationName)记录经期",
                "在\(.applicationName)标记经期",
                "在\(.applicationName)记录月经",
            ],
            shortTitle: "Log Period",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogMoodIntent(),
            phrases: [
                "Log my mood in \(.applicationName)",
                "Record mood in \(.applicationName)",
                "Track my mood in \(.applicationName)",
                "How am I feeling in \(.applicationName)",
                "在\(.applicationName)记录心情",
                "在\(.applicationName)记录今日心情",
            ],
            shortTitle: "Log Mood",
            systemImageName: "face.smiling"
        )
    }
}
#endif
