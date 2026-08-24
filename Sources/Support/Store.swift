import Foundation
import StoreKit
import UIKit

enum PremiumEntitlementTransition {
    static func didDowngrade(from oldValue: Bool, to newValue: Bool) -> Bool {
        oldValue && !newValue
    }

    /// A verified no-entitlement snapshot must reconcile notifications even
    /// when the in-memory value was already false (for example after launch).
    static func shouldReconcileNotifications(forEntitledValue entitled: Bool) -> Bool {
        !entitled
    }
}

/// 内购(StoreKit 2)。Freemium:**Maren Premium** 解锁高级功能(首批:个性化洞察)。
///
/// 产品(需在 App Store Connect 创建同名产品 ID;本地测试用 StoreKit Configuration 文件):
///   - `cd.cc.vela.premium.yearly`   自动续期年订阅(最划算,默认推荐)
///   - `cd.cc.vela.premium.monthly`  自动续期月订阅
///   - `cd.cc.vela.premium.lifetime` 一次性买断
///
/// 隐私铁律:购买全程由 Apple 处理,我们只拿到 **entitlement 状态**(是否已升级),
/// 不接触支付信息,**不接触任何健康数据**。Premium 状态只由 StoreKit 2 的已验签交易
/// 决定；不把 UserDefaults 当成授权来源。每次启动、回到前台、恢复购买和交易更新时,
/// 都用 `Transaction.currentEntitlements` 校正(应对退款 / 过期 / 换设备)。
///
/// 本地测试(无需 App Store Connect):
///   1. Xcode → File → New → File → StoreKit Configuration File,命名 `Vela.storekit`;
///   2. 在其中添加上面三个产品 ID(年/月订阅放同一个 Subscription Group);
///   3. Edit Scheme → Run → Options → StoreKit Configuration 选 `Vela.storekit`。
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    enum ProductID {
        static let yearly   = "cd.cc.vela.premium.yearly"
        static let monthly  = "cd.cc.vela.premium.monthly"
        static let lifetime = "cd.cc.vela.premium.lifetime"
        /// 展示顺序:年订阅置顶(最划算)-> 月 -> 终身。
        static let all = [yearly, monthly, lifetime]
    }

    /// 已加载到的产品(按 `ProductID.all` 顺序)。
    @Published private(set) var products: [Product] = []
    /// 各产品的免费试用资格(异步填充,加载产品后查一次)。
    @Published private(set) var trialEligibility: [String: Bool] = [:]
    /// 是否已升级。这个值只会由已验签的 StoreKit 交易或
    /// `Transaction.currentEntitlements` 更新，不读取或写入 UserDefaults。
    @Published private(set) var premium: Bool = false
    /// 正在购买中(用于禁用按钮、显示转圈)。
    @Published var purchasing: Bool = false
    /// 最近一次错误(本地化描述,供界面提示)。
    @Published var lastError: String?

    private var transactionListener: Task<Void, Never>?
    private var lifecycleObserver: NSObjectProtocol?
    /// 防止一次较早开始的 currentEntitlements 扫描覆盖刚刚验签并授予的购买。
    private var entitlementRevision: UInt = 0

    private init() {
        // 监听交易更新(续期、退款、家庭共享、跨设备购买)。App 生命周期内常驻。
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? Self.checkVerified(result) {
                    // 续期、家庭共享、跨设备购买:这笔已验签且仍有效的交易就是即时凭据。
                    // 退款、撤销或过期交易不得继续授予;重新读取 currentEntitlements 以降级。
                    if !self.grant(from: transaction) {
                        await self.refreshEntitlements()
                    }
                    await transaction.finish()
                } else {
                    // 验签失败的交易:不能 finish(否则会被当成已处理而丢失),
                    // 但也不能永远滞留;记录一条错误供界面排查。
                    self.lastError = String(localized: "有一笔交易未能通过签名校验,已跳过。")
                }
            }
        }
        // 启动时校正 entitlement(退款 / 过期 / 换设备)。
        Task { await self.refreshEntitlements() }

        // 订阅可能在 app 运行期间过期,而不一定产生一条 Transaction.updates。
        // 每次回到前台都重新读取 StoreKit 的当前权益,避免过期后继续开放 Premium。
        lifecycleObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshEntitlements()
            }
        }
    }

    deinit {
        transactionListener?.cancel()
        if let lifecycleObserver {
            NotificationCenter.default.removeObserver(lifecycleObserver)
        }
    }

    // MARK: - 加载 / 购买 / 恢复

    /// 加载产品。无网络或产品未配时 `products` 为空,paywall 会提示「暂时无法加载」。
    @MainActor
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: ProductID.all)
            self.products = ProductID.all.compactMap { id in
                storeProducts.first { $0.id == id }
            }
            await checkTrialEligibility()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// 查询当前用户对各订阅产品免费试用的资格(仅首次订阅前可用)。
    @MainActor
    private func checkTrialEligibility() async {
        trialEligibility.removeAll(keepingCapacity: true)
        for product in products {
            guard let subscription = product.subscription,
                  let introOffer = subscription.introductoryOffer,
                  introOffer.paymentMode == .freeTrial else {
                trialEligibility[product.id] = false
                continue
            }
            trialEligibility[product.id] = await subscription.isEligibleForIntroOffer
        }
    }

    /// Intro-offer eligibility is account state, not product metadata.  It
    /// can change while the app is running (sandbox accounts make this easy
    /// to reproduce), so paywall appearances must be able to refresh it even
    /// when the Product objects are already cached.
    @MainActor
    func refreshTrialEligibility() async {
        guard !products.isEmpty else { return }
        await checkTrialEligibility()
    }

    /// 购买指定产品。成功并校验通过后返回 true。
    @discardableResult
    @MainActor
    func purchase(_ product: Product) async -> Bool {
        purchasing = true
        lastError = nil          // 清掉上一次的残留,否则界面会报一个早已过期的错
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // ⚠️ 这里以前用 `try?` 吞掉验签失败,并且直接 return false 而不写 lastError。
                // 结果是:Apple 自己的「购买成功」弹窗照常出现,但 app 什么都没发生、
                // 也不报错 —— 用户完全无从判断出了什么事。任何一条失败路径都必须留下话。
                do {
                    let transaction = try Self.checkVerified(verification)
                    // ⚠️ 先按这笔已验签且仍有效的交易直接授予权益,再 finish。
                    // 以前是 finish 之后去查 `Transaction.currentEntitlements` 反推 —— 那是错的:
                    // 沙盒里 currentEntitlements 在购买刚完成时经常还没刷新到,于是
                    // 「验签通过 + 已 finish」却查不到权益,用户看到购买成功但功能没解锁。
                    // 刚验签通过的 transaction 本身就是最权威的凭据,不该再绕一圈。
                    guard grant(from: transaction) else {
                        await transaction.finish()
                        await refreshEntitlements()
                        lastError = String(localized: "这笔购买已验签,但当前权益已过期或已撤销。请点「恢复购买」重试。")
                        return false
                    }
                    await transaction.finish()
                    return true
                } catch {
                    lastError = String(localized: "这笔购买未能通过 App Store 的签名校验,权益没有生效。请重试或联系 billy.yu@me.com。")
                    return false
                }
            case .pending:
                // Ask to Buy(家长批准)或 App Store 延后处理:不是失败,但也还没到账。
                lastError = String(localized: "购买还在等待确认,通过后权益会自动生效。")
                return false
            case .userCancelled:
                return false
            @unknown default:
                lastError = String(localized: "购买返回了未知状态,权益未生效。请重试。")
                return false
            }
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
    }

    /// 恢复购买:先向 App Store 同步本账号的所有交易,再刷新 entitlement。
    /// 只调 `refreshEntitlements` 依赖本机 Transaction.currentEntitlements 的缓存,
    /// 在新设备/缓存未刷新时会返回「没有可恢复的购买」;`AppStore.sync()` 强制拉取。
    @MainActor
    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    // MARK: - Trial Helpers

    /// 获取产品的免费试用期天数。StoreKit 的一周试用统一换算为 7 天显示。
    func freeTrialDays(for product: Product) -> Int? {
        guard let subscription = product.subscription,
              let introOffer = subscription.introductoryOffer,
              introOffer.paymentMode == .freeTrial else { return nil }
        switch introOffer.period.unit {
        case .day: return introOffer.period.value
        case .week: return introOffer.period.value * 7
        default: return nil
        }
    }

    /// 产品是否有资格显示免费试用文案。
    func isEligibleForTrial(_ product: Product) -> Bool {
        trialEligibility[product.id] == true
    }

    /// 付费墙只能对实际返回的一周免费试用做明确的“7 天”承诺。
    func hasEligibleSevenDayTrial(_ product: Product) -> Bool {
        isEligibleForTrial(product) && freeTrialDays(for: product) == 7
    }

    /// 按一笔**已验签且仍有效**的交易授予权益。只升不降；降级只由
    /// `refreshEntitlements` 根据 StoreKit 的当前权益快照执行。
    ///
    /// 为什么不统一走 `currentEntitlements`:那是「当前状态」的快照,在沙盒(以及网络抖动时)
    /// 相对刚完成的购买有明显滞后。而 `product.purchase()` 返回并验签通过的 transaction
    /// 是即时且权威的。降级由启动、前台、恢复购买和交易更新时的刷新负责。
    @discardableResult
    @MainActor
    private func grant(from transaction: Transaction) -> Bool {
        guard Self.isCurrentlyEntitled(transaction) else { return false }
        entitlementRevision &+= 1
        premium = true
        return true
    }

    private static func isCurrentlyEntitled(_ transaction: Transaction,
                                            now: Date = Date()) -> Bool {
        guard ProductID.all.contains(transaction.productID),
              transaction.revocationDate == nil else { return false }
        guard let expirationDate = transaction.expirationDate else { return true }
        return expirationDate > now
    }

    /// 扫一遍当前权益。返回(是否有权益, 验签失败的笔数)。
    private func currentEntitlementState() async -> (entitled: Bool, unverified: Int) {
        var entitled = false
        var unverified = 0
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if Self.isCurrentlyEntitled(transaction) { entitled = true }
            case .unverified(let transaction, _):
                // 单独统计:以前用 `try?` 一律跳过,于是「买到了但验不过」和「压根没买过」
                // 在界面上长得一模一样,都是「没有找到可恢复的购买」。
                if ProductID.all.contains(transaction.productID) { unverified += 1 }
            }
        }
        return (entitled, unverified)
    }

    /// 校正 entitlement(退款 / 过期 / 换设备)。UserDefaults 不参与授权判断。
    @MainActor
    func refreshEntitlements() async {
        let revisionAtStart = entitlementRevision
        let state = await currentEntitlementState()
        // 若扫描期间有一笔新的已验签购买到账,本次扫描可能仍看不到它;
        // 保留刚授予的权利,等待下一轮 StoreKit 刷新,避免购买成功后被瞬间锁回去。
        if revisionAtStart != entitlementRevision && !state.entitled {
            return
        }
        applyEntitlement(state.entitled)
        if state.entitled {
            lastError = nil
        } else if state.unverified > 0 {
            lastError = String(localized: "查到 \(state.unverified) 笔无法验签的购买记录,权益未生效。请重试或联系 billy.yu@me.com。")
        }
    }

    /// Apply a verified entitlement snapshot.  Store owns only StoreKit state;
    /// the notification layer performs its own request-level downgrade cleanup
    /// without giving Store a SwiftData dependency.
    @MainActor
    private func applyEntitlement(_ entitled: Bool) {
        premium = entitled
        // Do this for every verified no-entitlement snapshot. On a cold
        // launch premium starts false even if stale Premium requests were
        // left pending while the app was not running.
        guard PremiumEntitlementTransition.shouldReconcileNotifications(forEntitledValue: entitled) else { return }
        Task { @MainActor in
            await NotificationManager.shared.reconcileAfterPremiumDowngrade()
        }
    }

    // MARK: - 校验

    /// 校验 JWS 签名。生产环境的交易由系统验签;本地测试环境也走同一通道。
    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
