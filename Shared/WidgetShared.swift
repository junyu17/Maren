import Foundation

/// 层级 3 · 小组件与主 app 之间的共享数据。
///
/// 数据共享走 **App Group 的 UserDefaults**(纯本地,不联网):
/// 主 app 每次数据变化时写入一份「已本地化好的展示文案」快照,小组件只负责渲染。
/// 这样小组件不必访问 SwiftData 库、也不必自己做本地化 —— 语言跟随主 app 写入时的语言。
struct WidgetSnapshot: Codable {
    var title: String     // 例如「距下次经期」/「Next period」
    var value: String     // 例如「3 天」/「in 3 days」
    var note: String      // 每日一句(可空)
    var themeRaw: String  // 主题强调色
    var updated: Date

    static let placeholder = WidgetSnapshot(
        title: "Maren", value: "—", note: "", themeRaw: "rose", updated: Date(timeIntervalSince1970: 0))
}

enum WidgetSnapshotStore {
    /// App Group id。主 app 与小组件都要在 entitlements 里声明同一个。
    static let appGroup = "group.cd.cc.vela"
    private static let key = "widget.snapshot.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> WidgetSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }
}
