import SwiftUI

/// 层级 4 · 手表主界面。极简三段:一眼看 → 记经期 → 记心情。
struct WatchRootView: View {
    @EnvironmentObject private var conn: WatchConnectivityManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var justSaved = false

    private var accent: Color {
        let palette = VelaPalette.theme(for: conn.snapshot.themeRaw)
        return VelaPalette.color(light: palette.light, dark: palette.dark, colorScheme: colorScheme)
    }

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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], spacing: 6) {
                        ForEach(0..<4) { raw in
                            Button {
                                conn.send(.period(flowRaw: raw, dayKey: todayKey))
                                flash()
                            } label: {
                                Circle()
                                    .fill(VelaPalette.color(VelaPalette.flow(raw)))
                                    .frame(minWidth: 40, minHeight: 40)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: 40, minHeight: 44)
                            .accessibilityLabel(flowName(raw))
                        }
                    }

                    Divider()

                    // 记心情
                    Text("今天心情").font(.caption2).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], spacing: 6) {
                        ForEach([(5, "😄"), (4, "🙂"), (3, "😐"), (2, "😕"), (1, "😣")], id: \.0) { item in
                            Button {
                                conn.send(.mood(moodRaw: item.0, dayKey: todayKey))
                                flash()
                            } label: {
                                Text(item.1)
                                    .font(.title3)
                                    .frame(minWidth: 40, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(moodName(item.0))
                        }
                    }

                    Text("记录会同步回 iPhone")
                        .font(.caption2).foregroundStyle(.tertiary)
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

private func flowName(_ raw: Int) -> String {
    switch raw {
    case 0: return String(localized: "点滴")
    case 1: return String(localized: "少量")
    case 2: return String(localized: "中量")
    default: return String(localized: "大量")
    }
}

private func moodName(_ raw: Int) -> String {
    switch raw {
    case 5: return String(localized: "很好")
    case 4: return String(localized: "不错")
    case 3: return String(localized: "一般")
    case 2: return String(localized: "低落")
    default: return String(localized: "很糟")
    }
}
