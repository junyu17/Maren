import Foundation
import StoreKit

/// 内购(StoreKit 2)。Freemium:**Maren Premium** 解锁高级功能(首批:个性化洞察)。
///
/// 产品(需在 App Store Connect 创建同名产品 ID;本地测试用 StoreKit Configuration 文件):
///   - `cd.cc.vela.premium.yearly`   自动续期年订阅(最划算,默认推荐)
///   - `cd.cc.vela.premium.monthly`  自动续期月订阅
///   - `cd.cc.vela.premium.lifetime` 一次性买断
///
/// 隐私铁律:购买全程由 Apple 处理,我们只拿到 **entitlement 状态**(是否已升级),
/// 不接触支付信息,**不接触任何健康数据**。entitlement 仅缓存于本机 UserDefaults,
/// 并在每次启动 / 交易更新时用 `Transaction.currentEntitlements` 校正(应对退款 / 过期)。
///
/// 本地测试(无需 App Store Connect):
///   1. Xcode → File → New → File → StoreKit Configuration File,命名 `Vela.storekit`;
///   2. 在其中添加上面三个产品 ID(年/月订阅放同一个 Subscription Group);
///   3. Edit Scheme → Run → Options → StoreKit Configuration 选 `Vela.storekit`。
final class Store: ObservableObject {
    static let shared = Store()

    enum ProductID {
        static let yearly   = "cd.cc.vela.premium.yearly"
        static let monthly  = "cd.cc.vela.premium.monthly"
        static let lifetime = "cd.cc.vela.premium.lifetime"
        /// 展示顺序:年订阅置顶(最划算)-> 月 -> 终身。
        static let all = [yearly, monthly, lifetime]
    }

    /// 本机缓存的 entitlement key。
    private static let premiumKey = "store.premium"

    /// 已加载到的产品(按 `ProductID.all` 顺序)。
    @Published private(set) var products: [Product] = []
    /// 是否已升级。启动时用缓存值即时显示,再用 StoreKit 校正。
    @Published private(set) var premium: Bool = UserDefaults.standard.bool(forKey: premiumKey)
    /// 正在购买中(用于禁用按钮、显示转圈)。
    @Published var purchasing: Bool = false
    /// 最近一次错误(本地化描述,供界面提示)。
    @Published var lastError: String?

    private var transactionListener: Task<Void, Never>?

    private init() {
        // 监听交易更新(续期、退款、家庭共享、跨设备购买)。App 生命周期内常驻。
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? Self.checkVerified(result) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
        // 启动时校正 entitlement(退款 / 过期会让缓存值失效)。
        Task { await self.refreshEntitlements() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - 加载 / 购买 / 恢复

    /// 加载产品。无网络或产品未配时 `products` 为空,paywall 会提示「暂时无法加载」。
    @MainActor
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: ProductID.all)
            self.products = ProductID.all.compactMap { id in
                storeProducts.first { $0.id == id }
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// 购买指定产品。成功并校验通过后返回 true。
    @discardableResult
    @MainActor
    func purchase(_ product: Product) async -> Bool {
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = try? Self.checkVerified(verification) {
                    await transaction.finish()
                    await refreshEntitlements()
                    return true
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.lastError = error.localizedDescription
            return false
        }
    }

    /// 恢复购买:把 App Store 上的 entitlement 拉回本机(Apple 要求提供此入口)。
    @MainActor
    func restore() async {
        await refreshEntitlements()
    }

    /// 校验当前是否享有任意一个 Premium 产品的权益。
    @MainActor
    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.checkVerified(result),
               ProductID.all.contains(transaction.productID) {
                entitled = true
            }
        }
        premium = entitled
        UserDefaults.standard.set(entitled, forKey: Self.premiumKey)
    }

    // MARK: - 校验

    private enum StoreError: LocalizedError {
        case unverified
        var errorDescription: String? { String(localized: "交易未能通过签名校验。") }
    }

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
