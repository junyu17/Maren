import SwiftUI
import StoreKit

/// 法律文档链接(GitHub Pages 托管,见仓库 `docs/`)。
/// App Store 审核要求订阅 app 在付费墙内提供 EULA / 隐私政策入口(Guideline 3.1.2 / 5.1.1)。
/// 这两个 URL 同时填进 App Store Connect 的 Privacy Policy URL / EULA 字段。
enum LegalLinks {
    static let privacy = URL(string: "https://junyu17.github.io/Maren/privacy.html")!
    static let terms   = URL(string: "https://junyu17.github.io/Maren/terms.html")!
}

/// Product presentation is deliberately independent of StoreKit so its most
/// important purchase promises can be tested without constructing `Product`.
enum PaywallPlanKind: Equatable {
    case yearly
    case monthly
    case lifetime
}

enum PaywallCTA: Equatable {
    case startTrial(days: Int)
    case subscribe
    case purchase
}

enum PaywallBillingDisclosure: Equatable {
    case automaticRenewal(trialDays: Int?, postTrialPrice: String?)
    case oneTime
}

struct PaywallProductPresentation: Equatable {
    let kind: PaywallPlanKind
    let displayName: String
    let displayPrice: String
    let cta: PaywallCTA
    let billingDisclosure: PaywallBillingDisclosure

    var trialDays: Int? {
        guard case .startTrial(let days) = cta else { return nil }
        return days
    }
}

/// Pure presentation policy for the three products exposed by the paywall.
/// StoreKit remains the source of truth for names, prices, and trial metadata;
/// this policy only decides which wording is legal for that metadata.
enum PaywallPurchaseStrategy {
    static func presentation(
        productID: String,
        displayName: String,
        displayPrice: String,
        eligibleTrialDays: Int?
    ) -> PaywallProductPresentation? {
        switch productID {
        case Store.ProductID.yearly:
            // Whatever free trial StoreKit reports for this account, of any
            // length. Pinning this to "exactly 7 days" meant changing the offer
            // in App Store Connect silently dropped every trial wording while
            // Apple still charged nothing — no error, no failing test.
            return PaywallProductPresentation(
                kind: .yearly,
                displayName: displayName,
                displayPrice: displayPrice,
                cta: eligibleTrialDays.map { .startTrial(days: $0) } ?? .subscribe,
                billingDisclosure: .automaticRenewal(
                    trialDays: eligibleTrialDays,
                    postTrialPrice: eligibleTrialDays == nil ? nil : displayPrice
                )
            )
        case Store.ProductID.monthly:
            // The monthly plan carries no trial today, but it can be given one
            // from App Store Connect without a release, so read it too.
            return PaywallProductPresentation(
                kind: .monthly,
                displayName: displayName,
                displayPrice: displayPrice,
                cta: eligibleTrialDays.map { .startTrial(days: $0) } ?? .subscribe,
                billingDisclosure: .automaticRenewal(
                    trialDays: eligibleTrialDays,
                    postTrialPrice: eligibleTrialDays == nil ? nil : displayPrice
                )
            )
        case Store.ProductID.lifetime:
            return PaywallProductPresentation(
                kind: .lifetime,
                displayName: displayName,
                displayPrice: displayPrice,
                cta: .purchase,
                billingDisclosure: .oneTime
            )
        default:
            return nil
        }
    }
}

/// Picks a usable default as soon as StoreKit returns product identifiers.
/// This is intentionally independent of introductory-offer eligibility: that
/// account lookup may be slow on a physical device and must not leave the CTA
/// in its disabled "Choose a plan" state.
enum PaywallSelectionPolicy {
    static func defaultProductID(availableProductIDs: [String]) -> String? {
        Store.ProductID.all.first { availableProductIDs.contains($0) }
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = Store.shared
    @State private var selectedProductID: String?
    @State private var showResultAlert = false
    @State private var resultMsg = ""

    private var accent: Color { AppTheme.current.accent }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    benefitsSection
                    freeSection
                    planSection
                    purchaseButton
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
            .task {
                if store.products.isEmpty { await store.loadProducts() }
                if selectedProductID == nil { selectDefaultProduct() }
                // Trial eligibility is account-specific and can be slow on a
                // real device. It must not delay the default selection/CTA.
                await store.refreshTrialEligibility()
            }
            .alert("提示", isPresented: $showResultAlert) {
                Button("好") {}
            } message: { Text(resultMsg) }
            .onChange(of: store.premium) { _, isPremium in
                if isPremium { dismiss() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { @MainActor in
                    await store.refreshTrialEligibility()
                }
            }
        }
    }

    private func selectDefaultProduct() {
        selectedProductID = PaywallSelectionPolicy.defaultProductID(
            availableProductIDs: store.products.map(\.id)
        )
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(accent)
            Text("更懂自己的身体节律，不交出健康数据")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("你的每日记录会变成趋势、提醒和可分享的摘要；所有分析在设备端完成。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            benefitGroup(
                icon: "chart.xyaxis.line",
                title: String(localized: "看懂规律"),
                items: [
                    String(localized: "心情与周期的关联趋势"),
                    String(localized: "最常记录的追踪项排行"),
                    String(localized: "周期规律度观察"),
                ]
            )
            benefitGroup(
                icon: "bell.badge.fill",
                title: String(localized: "提前准备"),
                items: [
                    String(localized: "多时段用药提醒"),
                    String(localized: "经期提前天数自定义"),
                    String(localized: "PMS 关怀与按阶段智能提醒"),
                ]
            )
            benefitGroup(
                icon: "doc.text.fill",
                title: String(localized: "带更清晰的记录去看诊"),
                items: [
                    String(localized: "自定义日期范围生成结构化 PDF"),
                    String(localized: "免费版固定近 6 个月范围"),
                ]
            )
            benefitGroup(
                icon: "paintpalette",
                title: String(localized: "按你的方式追踪"),
                items: [
                    String(localized: "5 套配色主题"),
                    String(localized: "无限自定义追踪项"),
                ]
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitGroup(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(FlowLevel.medium.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.self) { item in
                    Text("· " + item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 24)
        }
    }

    // MARK: - Free Tier Trust

    private var freeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("免费版始终包含").font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(freeFeatures, id: \.self) { feature in
                    Text("· " + feature)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 24)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var freeFeatures: [String] {
        [
            String(localized: "经期与周期日历"),
            String(localized: "每日心情 / 症状打卡"),
            String(localized: "基础提醒通知"),
            String(localized: "数据导出、备份与删除"),
        ]
    }

    // MARK: - Plan Selector

    private var planSection: some View {
        VStack(spacing: 10) {
            if store.products.isEmpty {
                if store.purchasing {
                    ProgressView()
                } else {
                    Text("暂时无法加载产品。请确认网络；若在本地测试，请在 Xcode 配置 StoreKit Configuration 文件。")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(store.products, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.id == Store.ProductID.yearly
        let isLifetime = product.id == Store.ProductID.lifetime
        let presentation = presentation(for: product)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProductID = product.id
            }
        } label: {
            HStack(alignment: .top) {
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? accent : .secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.subheadline.weight(.semibold))
                        if isYearly {
                            Text("最划算")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.opacity(0.15), in: Capsule())
                        }
                    }
                    if let trialDays = presentation?.trialDays {
                        // Parameterized, so a different offer length in App Store
                        // Connect shows the real number instead of a stale "7".
                        Text(String(localized: "\(trialDays) 天免费试用"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else if isLifetime {
                        Text(String(localized: "一次性付款，永久有效"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let sub = product.subscription {
                        let period = periodText(sub.subscriptionPeriod)
                        Text(String(localized: "订阅生效后每 \(period) 续费"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if isYearly, let monthlyEquivalent = monthlyEquivalentText(for: product) {
                        Text(monthlyEquivalent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let savings = savingsText(for: product) {
                        Text(savings)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    Text(planPriceText(product))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? accent : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .background(isSelected ? accent.opacity(0.04) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(store.purchasing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(planAccessibilityLabel(product, presentation: presentation))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await handlePurchaseButtonTap() }
        } label: {
            HStack {
                if store.purchasing {
                    ProgressView()
                        .tint(.white)
                }
                Text(purchaseButtonTitle)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(accent, in: RoundedRectangle(cornerRadius: 14))
        }
        // When products are temporarily unavailable, keep this button
        // tappable so it can retry instead of presenting a permanently dead
        // "Choose a plan" CTA.
        .disabled(store.purchasing)
        .opacity(store.purchasing ? 0.6 : 1)
    }

    private var purchaseButtonTitle: String {
        guard let id = selectedProductID,
              let product = store.products.first(where: { $0.id == id }) else {
            return String(localized: "选择方案")
        }
        guard let presentation = presentation(for: product) else {
            return String(localized: "选择方案")
        }
        switch presentation.cta {
        case .startTrial(let days):
            return String(localized: "开始 \(days) 天免费试用")
        case .subscribe:
            return String(localized: "订阅 \(presentation.displayName)")
        case .purchase:
            return String(localized: "购买并永久解锁")
        }
    }

    private func handlePurchaseButtonTap() async {
        if selectedProductID == nil {
            await store.loadProducts()
            selectDefaultProduct()
            guard selectedProductID != nil else {
                resultMsg = store.lastError ?? String(localized: "暂时无法加载产品。请确认网络；若在本地测试，请在 Xcode 配置 StoreKit Configuration 文件。")
                showResultAlert = true
                return
            }
            await store.refreshTrialEligibility()
        }
        await performPurchase()
    }

    private func performPurchase() async {
        guard let id = selectedProductID,
              let product = store.products.first(where: { $0.id == id }) else { return }
        let ok = await store.purchase(product)
        if !ok, let err = store.lastError {
            resultMsg = err
            showResultAlert = true
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await store.restore()
                resultMsg = store.premium
                    ? String(localized: "已恢复你的 Premium 权益。")
                    : (store.lastError ?? String(localized: "没有找到可恢复的购买。"))
                showResultAlert = true
            }
        } label: {
            Text("恢复购买").font(.subheadline).foregroundStyle(.secondary)
        }
        .disabled(store.purchasing)
    }

    // MARK: - Pricing Helpers

    private func planPriceText(_ product: Product) -> String {
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

    private func monthlyEquivalentText(for product: Product) -> String? {
        guard product.id == Store.ProductID.yearly else { return nil }
        let price = PaywallPricing.monthlyEquivalent(yearlyPrice: product.price)
            .formatted(product.priceFormatStyle)
        return String(localized: "约 \(price) / 月")
    }

    private func savingsText(for product: Product) -> String? {
        guard product.id == Store.ProductID.yearly,
              let monthly = store.products.first(where: { $0.id == Store.ProductID.monthly }),
              let percentage = PaywallPricing.savingsPercentage(
                yearlyPrice: product.price,
                monthlyPrice: monthly.price
              ) else { return nil }
        return String(localized: "节省 \(percentage)%")
    }

    // MARK: - Accessibility

    private func planAccessibilityLabel(_ product: Product, presentation: PaywallProductPresentation?) -> String {
        var parts = [product.displayName, planPriceText(product)]
        if case .some(.startTrial(let days)) = presentation?.cta {
            parts.append(String(localized: "\(days) 天免费试用"))
        }
        if case .some(.purchase) = presentation?.cta {
            parts.append(String(localized: "一次性付款，永久有效"))
        }
        if product.id == selectedProductID {
            parts.append(String(localized: "已选中"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Legal

    private var legalText: some View {
        VStack(spacing: 6) {
            if let selectedProduct,
               let presentation = presentation(for: selectedProduct) {
                disclosureText(
                    for: presentation.billingDisclosure,
                    price: selectedProduct.displayPrice
                )
            }
            legalLinks
        }
    }

    @ViewBuilder
    private func disclosureText(
        for disclosure: PaywallBillingDisclosure,
        price: String
    ) -> some View {
        switch disclosure {
            case .automaticRenewal(let trialDays, let postTrialPrice):
                if let trialDays, let postTrialPrice {
                Text("开始 \(trialDays) 天免费试用时不会立即收费。试用结束后将按 \(postTrialPrice) / 年自动续费；你可以在试用结束前取消，避免产生费用。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("确认订阅时将按 \(price) 收费。订阅会自动续期，除非在当前订阅期结束至少 24 小时前取消；账户会在当前订阅期结束前 24 小时内按所选方案收取续订费用。你可以在 App Store 账户设置中管理或取消订阅。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .oneTime:
            Text("确认购买时将按 \(price) 向你的 Apple ID 收费。一次性付款，永久有效，无续费。所有交易由 Apple 处理，我们不接触你的支付信息。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                legalLinkItems
            }
            VStack(spacing: 6) {
                legalLinkItems
            }
        }
        .font(.caption2)
        .foregroundStyle(.blue)
        .multilineTextAlignment(.center)
    }

    private var legalLinkItems: some View {
        Group {
            Link("隐私政策", destination: LegalLinks.privacy)
            Link("使用条款", destination: LegalLinks.terms)
            Link("管理订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
        }
    }

    private var selectedProduct: Product? {
        guard let selectedProductID else { return nil }
        return store.products.first { $0.id == selectedProductID }
    }

    private func presentation(for product: Product) -> PaywallProductPresentation? {
        let eligibleTrialDays: Int? = product.id == Store.ProductID.yearly
            && store.hasEligibleSevenDayTrial(product)
            ? store.freeTrialDays(for: product)
            : nil
        return PaywallPurchaseStrategy.presentation(
            productID: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            eligibleTrialDays: eligibleTrialDays
        )
    }
}

/// StoreKit 价格展示的纯计算，不依赖固定币种或 storefront。
enum PaywallPricing {
    static func monthlyEquivalent(yearlyPrice: Decimal) -> Decimal {
        NSDecimalNumber(decimal: yearlyPrice)
            .dividing(by: NSDecimalNumber(value: 12))
            .decimalValue
    }

    static func savingsPercentage(yearlyPrice: Decimal, monthlyPrice: Decimal) -> Int? {
        guard yearlyPrice >= 0, monthlyPrice > 0 else { return nil }
        let annualizedMonthly = monthlyPrice * Decimal(12)
        guard annualizedMonthly > yearlyPrice else { return nil }
        let savings = annualizedMonthly - yearlyPrice
        let fraction = NSDecimalNumber(decimal: savings)
            .dividing(by: NSDecimalNumber(decimal: annualizedMonthly))
        return fraction
            .multiplying(by: NSDecimalNumber(value: 100))
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
            .intValue
    }
}
