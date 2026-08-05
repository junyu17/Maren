import SwiftUI
import StoreKit

/// 法律文档链接(GitHub Pages 托管,见仓库 `docs/`)。
/// App Store 审核要求订阅 app 在付费墙内提供 EULA / 隐私政策入口(Guideline 3.1.2 / 5.1.1)。
/// 这两个 URL 同时填进 App Store Connect 的 Privacy Policy URL / EULA 字段。
enum LegalLinks {
    static let privacy = URL(string: "https://junyu17.github.io/Maren/privacy.html")!
    static let terms   = URL(string: "https://junyu17.github.io/Maren/terms.html")!
}

/// 付费墙:展示 Maren Premium 的价值与三个产品,处理购买与恢复。
/// 价格 / 周期文案全部取自 StoreKit(随用户地区 storefront 变化),不写死。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Store.shared
    @State private var showResultAlert = false
    @State private var resultMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    featureList
                    Divider()
                    productList
                    restoreButton
                    legalText
                }
                .padding()
            }
            .navigationTitle("Maren Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { if store.products.isEmpty { await store.loadProducts() } }
            .alert("提示", isPresented: $showResultAlert) {
                Button("好") {}
            } message: { Text(resultMsg) }
            // 购买成功 -> premium 翻 true -> 自动关闭付费墙,被锁功能随即解锁。
            .onChange(of: store.premium) { _, isPremium in
                if isPremium { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(FlowLevel.medium.tint)
            Text("Maren Premium")
                .font(.title2.weight(.bold))
            Text("让 Maren 在本机发现属于你的规律。数据从不离开你的设备。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow("wand.and.stars",
                        title: String(localized: "个性化洞察"),
                        body: String(localized: "心情与周期的关联、最常出现的症状、周期稳定度--由你的记录在本机计算。"))
            featureRow("bell.badge.fill",
                        title: String(localized: "高级提醒"),
                        body: String(localized: "多时段用药提醒、经期提前天数自定义、PMS 关怀、按阶段智能提醒--更懂你的节奏。"))
            featureRow("chart.xyaxis.line",
                        title: String(localized: "深度趋势"),
                        body: String(localized: "心情、症状与体重的走势分析,看懂身体的规律。"))
            featureRow("heart.text.square",
                        title: String(localized: "PCOS 专项支持"),
                        body: String(localized: "为不规律 / PCOS 周期而设的追踪与洞察。"))
            featureRow("paintpalette",
                        title: String(localized: "主题与无限自定义追踪项"),
                        body: String(localized: "5 套配色,想追踪什么就加什么,不限数量。"))
            featureRow("lock.shield.fill",
                        title: String(localized: "支持独立开发"),
                        body: String(localized: "直接支持一个不卖你数据的独立开发者。你的记录和导出永远免费。"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(_ icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(FlowLevel.medium.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var productList: some View {
        VStack(spacing: 10) {
            if store.products.isEmpty {
                if store.purchasing {
                    ProgressView()
                } else {
                    Text("暂时无法加载产品。请确认网络;若在本地测试,请在 Xcode 配置 StoreKit Configuration 文件。")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(store.products, id: \.id) { product in
                    productRow(product)
                }
            }
        }
    }

    private func productRow(_ product: Product) -> some View {
        Button {
            Task {
                let ok = await store.purchase(product)
                if !ok, let err = store.lastError {
                    resultMsg = err
                    showResultAlert = true
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.displayName).font(.subheadline.weight(.semibold))
                    Text(product.description).font(.caption2).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
                Text(priceText(product))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(FlowLevel.medium.tint, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(store.purchasing)
        .opacity(store.purchasing ? 0.6 : 1)
    }

    /// 取 StoreKit 的本地化价格 + 周期文案。
    private func priceText(_ product: Product) -> String {
        let price = product.displayPrice
        if let sub = product.subscription {
            return "\(price) / \(periodText(sub.subscriptionPeriod))"
        }
        return "\(price) · \(String(localized: "一次性"))"
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .year:   return String(localized: "年")
        case .month:  return String(localized: "月")
        case .week:   return String(localized: "周")
        case .day:    return String(localized: "日")
        @unknown default: return String(localized: "期")
        }
    }

    private var restoreButton: some View {
        Button {
            Task {
                await store.restore()
                resultMsg = store.premium
                    ? String(localized: "已恢复你的 Premium 权益。")
                    : String(localized: "没有找到可恢复的购买。")
                showResultAlert = true
            }
        } label: {
            Text("恢复购买").font(.subheadline).foregroundStyle(.secondary)
        }
        .disabled(store.purchasing)
    }

    private var legalText: some View {
        VStack(spacing: 6) {
            Text("订阅会自动续期,可在 App Store 账户设置中随时取消。买断为一次性付款,永久有效。所有交易由 Apple 处理,我们不接触你的支付信息。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // 审核要求(Guideline 3.1.2 / 5.1.1):付费墙内提供隐私政策与使用条款入口。
            HStack(spacing: 16) {
                Link("隐私政策", destination: LegalLinks.privacy)
                Link("使用条款", destination: LegalLinks.terms)
            }
            .font(.caption2)
            .foregroundStyle(.blue)
        }
    }
}
