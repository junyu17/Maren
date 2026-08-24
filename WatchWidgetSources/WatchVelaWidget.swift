import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Watch Widget Timeline

struct WatchVelaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let pendingCount: Int
}

struct WatchVelaProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchVelaEntry {
        WatchVelaEntry(date: Date(), snapshot: .placeholder, pendingCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchVelaEntry) -> Void) {
        let s = WatchWidgetSnapshotStore.read()
        let pending = QuickActionQueue.pendingTodayCount(
            for: WatchWidgetSnapshotStore.appGroup, todayKey: QuickActionQueue.todayKey())
        completion(WatchVelaEntry(date: Date(), snapshot: s, pendingCount: pending))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchVelaEntry>) -> Void) {
        let s = WatchWidgetSnapshotStore.read()
        let pending = QuickActionQueue.pendingTodayCount(
            for: WatchWidgetSnapshotStore.appGroup, todayKey: QuickActionQueue.todayKey())
        let entry = WatchVelaEntry(date: Date(), snapshot: s, pendingCount: pending)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Watch Widget View

struct WatchVelaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    var entry: WatchVelaEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .accessoryCorner:
            cornerView
        default:
            rectangularView
        }
    }

    private var accent: Color {
        let palette = VelaPalette.theme(for: entry.snapshot.themeRaw)
        return VelaPalette.color(light: palette.light, dark: palette.dark, colorScheme: colorScheme)
    }

    // MARK: - Circular (Complication) — widgetURL deep link

    private var circularView: some View {
        let s = entry.snapshot
        return ZStack {
            if let label = s.phaseLabel, !label.isEmpty {
                Text(label.prefix(1))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
            }
        }
        .widgetURL(URL(string: "marenwatch://log"))
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - Rectangular (Smart Stack) — interactive buttons

    private var rectangularView: some View {
        let s = entry.snapshot
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
                Text("Maren").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
            }
            if let label = s.phaseLabel, !label.isEmpty {
                Text(label).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(s.value).font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .privacySensitive()
            // 交互按钮:标签明确写入实际记录值(medium flow / good mood)
            HStack(spacing: 6) {
                Button(intent: WatchLogPeriodIntent()) {
                    HStack(spacing: 2) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 8))
                        Text(String(localized: "中量"))
                            .font(.system(size: 8, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Log medium period flow"))

                Button(intent: WatchLogMoodIntent()) {
                    HStack(spacing: 2) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 8))
                        Text(String(localized: "不错"))
                            .font(.system(size: 8, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Log good mood"))
            }
            if entry.pendingCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                    Text(String(localized: "待同步"))
                        .font(.system(size: 8))
                }
                .foregroundStyle(.orange)
                .accessibilityLabel(String(localized: "\(entry.pendingCount) pending, will sync to iPhone"))
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - Inline

    private var inlineView: some View {
        let s = entry.snapshot
        return HStack(spacing: 4) {
            Image(systemName: "sailboat.fill")
                .foregroundStyle(accent)
            if let label = s.phaseLabel, !label.isEmpty {
                Text("\(label) · \(s.value)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            } else {
                Text("Maren · \(s.value)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .foregroundStyle(accent)
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - Corner — widgetURL deep link

    private var cornerView: some View {
        let s = entry.snapshot
        return ZStack {
            if let label = s.phaseLabel, !label.isEmpty {
                Text(label.prefix(1))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(accent)
            }
        }
        .widgetURL(URL(string: "marenwatch://log"))
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }
}

// MARK: - Watch Widget Definition

struct WatchVelaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchVelaWidget", provider: WatchVelaProvider()) { entry in
            WatchVelaWidgetView(entry: entry)
        }
        .configurationDisplayName("Maren")
        .description(String(localized: "Glance your cycle phase and next period on Apple Watch."))
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular,
            .accessoryInline, .accessoryCorner,
        ])
    }
}
