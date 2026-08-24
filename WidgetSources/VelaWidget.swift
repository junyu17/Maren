import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 时间线

struct VelaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// 当天待处理的快速操作数(来自 App Group 队列)。
    let pendingCount: Int
}

struct VelaProvider: TimelineProvider {
    func placeholder(in context: Context) -> VelaEntry {
        VelaEntry(date: Date(), snapshot: .placeholder, pendingCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (VelaEntry) -> Void) {
        let s = WidgetSnapshotStore.read()
        let pending = QuickActionQueue.pendingTodayCount(
            for: WidgetSnapshotStore.appGroup, todayKey: QuickActionQueue.todayKey())
        completion(VelaEntry(date: Date(), snapshot: s, pendingCount: pending))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VelaEntry>) -> Void) {
        let s = WidgetSnapshotStore.read()
        let pending = QuickActionQueue.pendingTodayCount(
            for: WidgetSnapshotStore.appGroup, todayKey: QuickActionQueue.todayKey())
        let entry = VelaEntry(date: Date(), snapshot: s, pendingCount: pending)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 配色

private func widgetAccent(_ raw: String) -> Color {
    let palette = VelaPalette.theme(for: raw)
    return VelaPalette.dynamicColor(light: palette.light, dark: palette.dark)
}

private func phaseColor(_ key: String?) -> Color {
    switch key ?? "" {
    case "menstrual":  return Color(red: 0.90, green: 0.40, blue: 0.46)
    case "follicular": return Color(red: 0.34, green: 0.70, blue: 0.62)
    case "ovulatory":  return Color(red: 0.38, green: 0.26, blue: 0.74)
    case "luteal":     return Color(red: 0.95, green: 0.66, blue: 0.36)
    default:           return .secondary
    }
}

// MARK: - 视图

struct VelaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: VelaEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
    }

    // MARK: - Small (2×2)

    private var smallView: some View {
        let s = entry.snapshot
        let accent = widgetAccent(s.themeRaw)
        let phaseClr = phaseColor(s.phaseKey)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "sailboat.fill").font(.caption2)
                Text("Maren").font(.caption2.weight(.bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(accent)

            if let label = s.phaseLabel, !label.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(phaseClr).frame(width: 8, height: 8)
                    Text(label).font(.caption.weight(.semibold)).foregroundStyle(phaseClr)
                }
            }
            if let tip = s.phaseTip, !tip.isEmpty {
                Text(tip).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 2)
            Text(s.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(s.value).font(.title2.bold()).foregroundStyle(accent)
                .minimumScaleFactor(0.6).lineLimit(1)
            pendingBadge
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "maren://calendar"))
        .privacySensitive()
    }

    // MARK: - Medium (2×4)

    private var mediumView: some View {
        let s = entry.snapshot
        let accent = widgetAccent(s.themeRaw)
        let phaseClr = phaseColor(s.phaseKey)
        return HStack(alignment: .top, spacing: 12) {
            // 左列:阶段 + 下次经期
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "sailboat.fill").font(.caption2)
                    Text("Maren").font(.caption2.weight(.bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(accent)
                if let label = s.phaseLabel, !label.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(phaseClr).frame(width: 8, height: 8)
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(phaseClr)
                    }
                }
                if let tip = s.phaseTip, !tip.isEmpty {
                    Text(tip).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                Text(s.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(s.value).font(.title2.bold()).foregroundStyle(accent)
                    .minimumScaleFactor(0.6).lineLimit(1)
                pendingBadge
            }
            .privacySensitive()
            Divider()
            // 右列:快速操作按钮(标签明确写入实际记录的值,无隐藏默认值)
            VStack(alignment: .leading, spacing: 8) {
                if !s.note.isEmpty {
                    Text(s.note).font(.caption).italic().foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                // 记经期按钮——标签明确写「中量」(medium flow),消除歧义
                Button(intent: LogPeriodIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill").font(.caption2)
                        Text(String(localized: "经期 · 中量")).font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Log medium period flow"))
                .accessibilityHint(String(localized: "Queues a medium flow period entry to save when Maren opens."))
                // 记心情按钮——标签明确写「不错」(good mood),消除歧义
                Button(intent: LogMoodIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: "face.smiling").font(.caption2)
                        Text(String(localized: "心情 · 不错")).font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Log good mood"))
                .accessibilityHint(String(localized: "Queues a good mood entry to save when Maren opens."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - Accessory Circular (Watch Complication)

    private var circularView: some View {
        let s = entry.snapshot
        let accent = widgetAccent(s.themeRaw)
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
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - Accessory Rectangular (Watch Smart Stack)

    private var rectangularView: some View {
        let s = entry.snapshot
        let accent = widgetAccent(s.themeRaw)
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
            }
            Text(s.value).font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - Accessory Inline

    private var inlineView: some View {
        let s = entry.snapshot
        let accent = widgetAccent(s.themeRaw)
        return HStack(spacing: 4) {
            Image(systemName: "sailboat.fill")
                .foregroundStyle(accent)
            if let label = s.phaseLabel, !label.isEmpty {
                Text("\(label) · \(s.value)")
            } else {
                Text("Maren · \(s.value)")
            }
        }
        .foregroundStyle(accent)
        .containerBackground(.fill.tertiary, for: .widget)
        .privacySensitive()
    }

    // MARK: - 待处理标记

    @ViewBuilder
    private var pendingBadge: some View {
        if entry.pendingCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 9))
                Text(String(localized: "待保存(\(entry.pendingCount))"))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.orange)
            .accessibilityLabel(String(localized: "\(entry.pendingCount) pending, will save when Maren is open"))
        }
    }
}

// MARK: - 组件定义

struct VelaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VelaWidget", provider: VelaProvider()) { entry in
            VelaWidgetView(entry: entry)
        }
        .configurationDisplayName("Maren")
        .description(String(localized: "查看周期、阶段与下次经期;中尺寸可快速记录经期和心情。"))
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

@main
struct VelaWidgetBundle: WidgetBundle {
    var body: some Widget {
        VelaWidget()
    }
}
