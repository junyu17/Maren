import Foundation

/// App Store 评分请求的时机控制。
///
/// 系统每 365 天最多真正展示 3 次弹窗,且是否展示完全由 App Store 决定 ——
/// 我们能控制的只有"什么时候开口问"。原则:只在用户刚完成一次有价值的操作之后问,
/// 绝不在启动时、引导流程中或一次失败之后问。
///
/// 用法:在一次成功的价值操作之后调用 `recordValueMoment()`,返回 true 时再触发
/// SwiftUI 的 `requestReview`。
@MainActor
enum ReviewPrompter {
    /// 累计多少次价值时刻后才第一次开口。
    ///
    /// 2,不是 5。5 适合已经有用户的 App —— 稀缺的是系统每年 3 次的配额;
    /// 在这个装机量下没有人累计得到 5 次,于是弹窗从未出现过。
    /// 现在记经期也算一次价值时刻,2 次意味着用户第二天回来记录时就会问,
    /// 那时第一次预测刚好出现。
    private static let momentsBeforeAsking = 2
    private static let momentCountKey = "review.valueMomentCount"
    private static let promptedVersionKey = "review.promptedVersion"

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 记一次价值时刻。达到阈值、且当前版本还没问过时返回 true。
    ///
    /// 按版本而不是按时间去重:同一个版本只问一次,升级后重新有机会 ——
    /// 系统自己的 365 天 / 3 次上限仍然在外层兜底。
    @discardableResult
    static func recordValueMoment() -> Bool {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: momentCountKey) + 1
        defaults.set(count, forKey: momentCountKey)

        guard count >= momentsBeforeAsking else { return false }
        guard defaults.string(forKey: promptedVersionKey) != currentVersion else { return false }

        defaults.set(currentVersion, forKey: promptedVersionKey)
        return true
    }

    /// 供测试与"清除全部数据"复位使用。
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: momentCountKey)
        defaults.removeObject(forKey: promptedVersionKey)
    }
}
