import SwiftUI

/// 层级 3 · 首次启动引导。第一印象就把「隐私」这个主卖点打出来。
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page = 0
    @State private var showSampleExperience = false

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let body: String
    }

    private var pages: [Page] {
        let accent = AppTheme.current.accent
        return [
            Page(icon: "sailboat.fill", tint: accent,
                 title: String(localized: "欢迎来到 Maren"),
                 body: String(localized: "一个隐私优先的经期、情绪与身体记录工具。为不规律 / PCOS 周期而生。")),
            Page(icon: "lock.shield.fill", tint: accent.opacity(0.88),
                 title: String(localized: "你的数据永远属于你"),
                 body: String(localized: "Maren 记录默认只存在这台设备上。只有当你主动使用导出、Apple 健康或配对 Apple Watch 时,相关数据才会交给你选择的 Apple 功能;绝不发送给我们的服务器或用于广告。可随时导出或彻底删除。")),
            Page(icon: "wand.and.stars", tint: accent.opacity(0.76),
                 title: String(localized: "越用越懂你"),
                 body: String(localized: "预测只学习你自己的真实周期,不套用「第 14 天」模板;还会在本机发现属于你的规律。不吹精准,如实呈现区间。")),
            Page(icon: "square.and.pencil", tint: accent.opacity(0.64),
                 title: String(localized: "3 秒记一次"),
                 body: String(localized: "在「日历」标记经期,在「今天」记录心情、症状、体重和用药,任何你想追踪的都能自己加。开始建立属于你的记录吧。"))
        ]
    }

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                    // AX5 descriptions can be several screens tall.  Keep
                    // the page indicator and controls visible while allowing
                    // the page content itself to scroll instead of clipping.
                    ScrollView(.vertical) {
                        VStack(spacing: 18) {
                            Image(systemName: p.icon)
                                .font(.system(size: 60))
                                .foregroundStyle(p.tint)
                                .accessibilityHidden(true)
                            Text(p.title)
                                .font(.title2.weight(.bold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(p.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 28)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.vertical, 24)
                    }
                    .scrollIndicators(.hidden)
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
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.current.accent)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button("跳过") { onDone() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            Button {
                showSampleExperience = true
            } label: {
                Label(String(localized: "先看看样本"), systemImage: "sparkles.rectangle.stack")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showSampleExperience) {
            SampleExperienceView()
        }
    }
}
