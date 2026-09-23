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
        id: "dogcat",
        name: "Dog & Cat Nutrition Coach",
        tagline: String(localized: "猫狗喂食计算器"),
        storeURL: URL(string: "https://apps.apple.com/app/id6800743305")!
    ),
    CrossPromoApp(
        id: "taskkin",
        name: "TaskKin",
        tagline: String(localized: "家庭协作照护"),
        storeURL: URL(string: "https://apps.apple.com/app/id6794837934")!
    ),
    CrossPromoApp(
        id: "livepet",
        name: "Live Pet AI",
        tagline: String(localized: "把照片变成会动的宠物小组件"),
        storeURL: URL(string: "https://apps.apple.com/app/id6794836674")!
    ),
    CrossPromoApp(
        id: "virtualpets",
        name: "Virtual Pets",
        tagline: String(localized: "温馨养宠换装游戏"),
        storeURL: URL(string: "https://apps.apple.com/app/id6784545568")!
    ),
    CrossPromoApp(
        id: "startkind",
        name: "StartKind",
        tagline: String(localized: "一小步，从此刻开始"),
        storeURL: URL(string: "https://apps.apple.com/app/id6799113108")!
    ),
    CrossPromoApp(
        id: "platepace",
        name: "PlatePace",
        tagline: String(localized: "GLP-1 饮食节奏的 AI 营养记录"),
        storeURL: URL(string: "https://apps.apple.com/app/id6799087226")!
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
