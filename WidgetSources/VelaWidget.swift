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

// MARK: - 配色(小组件自带一份,避免依赖主 app 代码)

private func widgetAccent(_ raw: String) -> Color {
    switch raw {
    case "teal":   return Color(red: 0.20, green: 0.62, blue: 0.56)
    case "violet": return Color(red: 0.45, green: 0.35, blue: 0.80)
    case "amber":  return Color(red: 0.90, green: 0.55, blue: 0.20)
    case "ink":    return Color(red: 0.24, green: 0.34, blue: 0.52)
    default:       return Color(red: 0.82, green: 0.36, blue: 0.42) // rose
    }
}

/// 周期阶段配色(与主 app `CyclePhase.tint` 一致)。key = `CyclePhase.rawValue`。
private func phaseColor(_ key: String?) -> Color {
    switch key ?? "" {
    case "menstrual":  return Color(red: 0.90, green: 0.40, blue: 0.46)
    case "follicular": return Color(red: 0.34, green: 0.70, blue: 0.62)
    case "ovulatory":  return Color(red: 0.38, green: 0.26, blue: 0.74)
    case "luteal":     return Color(red: 0.95, green: 0.66, blue: 0.36)
    default:           return .secondary // unknown / 数据不足
    }
}

// MARK: - 视图

struct VelaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: VelaEntry

    var body: some View {
        let s = entry.snapshot
        let accent = widgetAccent(s.themeRaw)
        let phaseClr = phaseColor(s.phaseKey)

        Group {
            if family == .systemMedium {
                // 2×4:左 = 阶段/提示/下次经期,右 = 鼓励语 + 点开记录
                HStack(alignment: .top, spacing: 12) {
                    coreBlock(s, accent: accent, phaseClr: phaseClr)
                    Divider()
                    mediumExtra(s, accent: accent)
                }
            } else {
                // 2×2:阶段/提示/下次经期(单列)
                coreBlock(s, accent: accent, phaseClr: phaseClr)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        // 点开 widget -> 主 app。中尺寸进「今天」直接记录;小尺寸进「日历」。
        .widgetURL(URL(string: family == .systemMedium ? "maren://today" : "maren://calendar"))
    }

    /// 核心块:今天所处周期 + 该注意什么 + 下次经期。2×2 与 2×4 左列共用。
    @ViewBuilder
    private func coreBlock(_ s: WidgetSnapshot, accent: Color, phaseClr: Color) -> some View {
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
                Text(tip)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 2)

            Text(s.title)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(s.value)
                .font(.title2.bold()).foregroundStyle(accent)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
    }

    /// 2×4 右列:鼓励一句话 + 点开记录今天的提示。
    @ViewBuilder
    private func mediumExtra(_ s: WidgetSnapshot, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !s.note.isEmpty {
                Text(s.note)
                    .font(.caption).italic().foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Image(systemName: "square.and.pencil").font(.caption2)
                Text("点开记录今天").font(.caption2.weight(.medium))
            }
            .foregroundStyle(accent)
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
        .description(Text("查看今天所处周期、注意事项与下次经期;大尺寸可点开记录今天。"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct VelaWidgetBundle: WidgetBundle {
    var body: some Widget {
        VelaWidget()
    }
}
