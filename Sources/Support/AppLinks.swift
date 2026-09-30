import Foundation

/// App Store 链接的唯一出口:带推广渠道(pt + ct)的分享链接与跨 App 推广链接。
/// pt 是开发者的 provider token,缺了它 Apple 会忽略 ct。ct 最长 40 个字符。
enum AppLinks {
    static let providerToken = "129087449"
    static let marenID = "6795029983"

    /// 分享 Maren 自己的内容:ct=share_<artefact>(share_app / share_pdf)。
    enum ShareArtefact: String {
        case app = "share_app"
        case pdf = "share_pdf"
    }

    /// 从 Maren 跳转到同一位开发者的其他 App:ct=xp_maren。
    static func crossPromo(appID: String) -> URL {
        campaign(appID: appID, ct: "xp_maren")
    }

    /// Maren 自己的商店页,用于分享内容里附带的链接。
    static func share(_ artefact: ShareArtefact) -> URL {
        campaign(appID: marenID, ct: artefact.rawValue)
    }

    /// 直接打开写评价页(不受系统每年 3 次评分弹窗的限制)。
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(marenID)?action=write-review")!

    private static func campaign(appID: String, ct: String) -> URL {
        URL(string: "https://apps.apple.com/app/apple-store/id\(appID)?pt=\(providerToken)&ct=\(ct)&mt=8")!
    }
}
