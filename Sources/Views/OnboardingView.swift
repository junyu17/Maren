import SwiftUI

/// 层级 3 · 首次启动引导。第一印象就把「隐私」这个主卖点打出来。
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let body: String
    }

    private var pages: [Page] {
        [
            Page(icon: "sailboat.fill", tint: FlowLevel.medium.tint,
                 title: String(localized: "欢迎来到 Maren"),
                 body: String(localized: "一个隐私优先的经期、情绪与身体记录工具。为不规律 / PCOS 周期而生。")),
            Page(icon: "lock.shield.fill", tint: Color(red: 0.34, green: 0.70, blue: 0.62),
                 title: String(localized: "你的数据永远属于你"),
                 body: String(localized: "健康数据只存在这台设备上。我们没有存你数据的服务器,看不到、也绝不共享给第三方或用于广告。可随时导出或彻底删除。")),
            Page(icon: "wand.and.stars", tint: Color(red: 0.38, green: 0.26, blue: 0.74),
                 title: String(localized: "越用越懂你"),
                 body: String(localized: "预测只学习你自己的真实周期,不套用「第 14 天」模板;还会在本机发现属于你的规律。不吹精准,如实呈现区间。")),
            Page(icon: "square.and.pencil", tint: Color(red: 0.95, green: 0.66, blue: 0.36),
                 title: String(localized: "3 秒记一次"),
                 body: String(localized: "在「日历」标记经期,在「今天」记录心情、症状、体重和用药。开始建立属于你的记录吧。"))
        ]
    }

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: p.icon)
                            .font(.system(size: 76))
                            .foregroundStyle(p.tint)
                        Text(p.title).font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(p.body)
                            .font(.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? String(localized: "继续") : String(localized: "开始使用"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(FlowLevel.medium.tint)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button("跳过") { onDone() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }
}
