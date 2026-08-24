import Foundation
import WidgetKit

/// 手表 widget 快照存储,使用与主 app 相同的 App Group (group.cd.cc.vela)。
/// 手机通过 WatchConnectivity 推送快照到手表 App,手表 App 再写入 watch 侧 App Group 供 watch widget 读取。
/// 手表 widget 不直接读取 iPhone 存储。
enum WatchWidgetSnapshotStore {
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
