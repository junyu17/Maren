import SwiftUI

/// 交叉推广:开发者名下其他 App 的入口(设置页底部)。
/// App Store 数据显示,Live Pet AI 近期 63 次安装里有 29 次来自其他 App 内的跳转,
/// 几乎追平搜索量,所以每个 App 的设置里都放一份「更多 App」清单。
struct CrossPromoApp: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let storeURL: URL
}

/// Maren 之外,同一位开发者的其他 App。点击直接跳转到对应的 App Store 页面。
private let otherDeveloperApps: [CrossPromoApp] = [
    CrossPromoApp(
        id: "platepace",
        name: "PlatePace",
        tagline: String(localized: "GLP-1 饮食节奏的 AI 营养记录"),
        storeURL: AppLinks.crossPromo(appID: "6799087226")
    ),
    CrossPromoApp(
        id: "startkind",
        name: "StartKind",
        tagline: String(localized: "一小步，从此刻开始"),
        storeURL: AppLinks.crossPromo(appID: "6799113108")
    ),
    CrossPromoApp(
        id: "taskkin",
        name: "TaskKin",
        tagline: String(localized: "家庭协作照护"),
        storeURL: AppLinks.crossPromo(appID: "6794837934")
    ),
    CrossPromoApp(
        id: "dogcat",
        name: "Dog & Cat Nutrition Coach",
        tagline: String(localized: "猫狗喂食计算器"),
        storeURL: AppLinks.crossPromo(appID: "6800743305")
    ),
    CrossPromoApp(
        id: "livepet",
        name: "Live Pet AI",
        tagline: String(localized: "把照片变成会动的宠物小组件"),
        storeURL: AppLinks.crossPromo(appID: "6794836674")
    ),
    CrossPromoApp(
        id: "virtualpets",
        name: "Virtual Pets",
        tagline: String(localized: "温馨养宠换装游戏"),
        storeURL: AppLinks.crossPromo(appID: "6784545568")
    ),
]

/// 设置页底部的「更多 App」区块。每行是一个跳转到 App Store 的按钮。
struct MoreAppsSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            ForEach(otherDeveloperApps) { app in
                Button {
                    openURL(app.storeURL)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(app.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(String(localized: "更多 App"))
        } footer: {
            Text(String(localized: "来自同一位开发者的其他 App。"))
        }
    }
}

/// 设置页的「评价 / 分享 Maren」两行。评价直接打开写评价页,分享带 ct=share_app 的商店链接。
struct RateShareSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Button {
                openURL(AppLinks.writeReview)
            } label: {
                Label(String(localized: "评价 Maren"), systemImage: "star")
            }
            ShareLink(item: AppLinks.share(.app),
                      message: Text(String(localized: "我在用 Maren 记录经期和身体变化,数据只保存在手机里。"))) {
                Label(String(localized: "分享 Maren"), systemImage: "square.and.arrow.up")
            }
        }
    }
}
