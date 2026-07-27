import WidgetKit
import SwiftUI

// MARK: - 时间线

struct VelaEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct VelaProvider: TimelineProvider {
    func placeholder(in context: Context) -> VelaEntry {
        VelaEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (VelaEntry) -> Void) {
        completion(VelaEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VelaEntry>) -> Void) {
        let entry = VelaEntry(date: Date(), snapshot: WidgetSnapshotStore.read())
        // 主 app 数据变化时会主动 reload;这里再兜底每 2 小时刷新一次。
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 主题色(小组件自带一份,避免依赖主 app 代码)

private func widgetAccent(_ raw: String) -> Color {
    switch raw {
    case "teal":   return Color(red: 0.20, green: 0.62, blue: 0.56)
    case "violet": return Color(red: 0.45, green: 0.35, blue: 0.80)
    case "amber":  return Color(red: 0.90, green: 0.55, blue: 0.20)
    case "ink":    return Color(red: 0.24, green: 0.34, blue: 0.52)
    default:       return Color(red: 0.82, green: 0.36, blue: 0.42) // rose
    }
}

// MARK: - 视图

struct VelaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: VelaEntry

    var body: some View {
        let accent = widgetAccent(entry.snapshot.themeRaw)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sailboat.fill").font(.caption2)
                Text("Maren").font(.caption2.weight(.bold))
            }
            .foregroundStyle(accent)

            Spacer(minLength: 2)

            Text(entry.snapshot.title)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.snapshot.value)
                .font(.title2.bold()).foregroundStyle(accent)
                .minimumScaleFactor(0.7).lineLimit(1)

            if family != .systemSmall && !entry.snapshot.note.isEmpty {
                Spacer(minLength: 2)
                Text(entry.snapshot.note)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 组件定义

struct VelaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VelaWidget", provider: VelaProvider()) { entry in
            VelaWidgetView(entry: entry)
        }
        .configurationDisplayName("Maren")
        .description(Text("查看距下次经期还有几天,以及今天的一句话。"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct VelaWidgetBundle: WidgetBundle {
    var body: some Widget {
        VelaWidget()
    }
}
