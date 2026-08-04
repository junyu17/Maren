import SwiftUI

/// 层级 4 · 手表主界面。极简三段:一眼看 → 记经期 → 记心情。
struct WatchRootView: View {
    @EnvironmentObject private var conn: WatchConnectivityManager
    @State private var justSaved = false

    private var accent: Color { watchAccent(conn.snapshot.themeRaw) }

    /// 手表按自己所在时区算「今天」,与手机的 DayKey 编码一致(固定公历,不跟随日历偏好)。
    private var todayKey: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 1970) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // 一眼看
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conn.snapshot.title)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(conn.snapshot.value)
                            .font(.title3.bold()).foregroundStyle(accent)
                            .minimumScaleFactor(0.7).lineLimit(1)
                    }

                    if justSaved {
                        Label("已记录", systemImage: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green)
                    }

                    Divider()

                    // 记经期
                    Text("记录经期").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(0..<4) { raw in
                            Button {
                                conn.send(.period(flowRaw: raw, dayKey: todayKey))
                                flash()
                            } label: {
                                Circle()
                                    .fill(flowColor(raw))
                                    .frame(height: 26)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(flowName(raw))
                        }
                    }

                    Divider()

                    // 记心情
                    Text("今天心情").font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach([(5, "😄"), (4, "🙂"), (3, "😐"), (2, "😕"), (1, "😣")], id: \.0) { item in
                            Button {
                                conn.send(.mood(moodRaw: item.0, dayKey: todayKey))
                                flash()
                            } label: {
                                Text(item.1).font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("记录会同步回 iPhone")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Maren")
        }
    }

    private func flash() {
        withAnimation { justSaved = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { justSaved = false }
        }
    }
}

// 手表侧自带一份配色,避免依赖主 app 代码。
private func watchAccent(_ raw: String) -> Color {
    switch raw {
    case "teal":   return Color(red: 0.20, green: 0.62, blue: 0.56)
    case "violet": return Color(red: 0.45, green: 0.35, blue: 0.80)
    case "amber":  return Color(red: 0.90, green: 0.55, blue: 0.20)
    case "ink":    return Color(red: 0.34, green: 0.48, blue: 0.72)
    default:       return Color(red: 0.90, green: 0.45, blue: 0.52)
    }
}

private func flowColor(_ raw: Int) -> Color {
    switch raw {
    case 0: return Color(red: 0.95, green: 0.72, blue: 0.72)
    case 1: return Color(red: 0.90, green: 0.55, blue: 0.58)
    case 2: return Color(red: 0.82, green: 0.36, blue: 0.42)
    default: return Color(red: 0.66, green: 0.20, blue: 0.28)
    }
}

private func flowName(_ raw: Int) -> String {
    switch raw {
    case 0: return String(localized: "点滴")
    case 1: return String(localized: "少量")
    case 2: return String(localized: "中量")
    default: return String(localized: "大量")
    }
}
