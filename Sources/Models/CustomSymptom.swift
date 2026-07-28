import Foundation
import SwiftData

/// 层级 2 · 用户自定义的追踪标签(立项书 F3「可自定义追踪项」)。
/// DailyLog.symptoms 里存的是 key;自定义项的 key 形如 "c:<uuid>",内置项用原有英文 key。
@Model
final class CustomSymptom {
    @Attribute(.unique) var key: String
    var label: String
    var emoji: String
    var createdAt: Date

    init(label: String, emoji: String) {
        self.key = "c:\(UUID().uuidString)"
        self.label = label
        self.emoji = emoji
        self.createdAt = Date()
    }

    /// 免费层最多自定义追踪项数;Pro 无限。
    static let freeLimit = 3
}

/// 静态快照,供非 View 场景(导出 / 洞察 / 趋势)解析自定义标签的显示名。
/// 视图里用 @Query 实时;这里在 app 启动和增删后刷新一次即可。
enum CustomSymptomStore {
    private(set) static var byKey: [String: SymptomTag] = [:]

    @MainActor
    static func refresh(_ context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<CustomSymptom>())) ?? []
        byKey = Dictionary(uniqueKeysWithValues: items.map {
            ($0.key, SymptomTag(key: $0.key, label: $0.label, emoji: $0.emoji))
        })
    }

    static func tags() -> [SymptomTag] {
        byKey.values.sorted { $0.label < $1.label }
    }
}
