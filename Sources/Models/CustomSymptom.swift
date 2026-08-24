import Foundation
import SwiftData

/// 层级 2 · 用户自定义的追踪标签(立项书 F3「可自定义追踪项」)。
/// DailyLog.symptoms 里存的是 key;自定义项的 key 形如 "c:<uuid>",内置项用原有英文 key。
@Model
final class CustomSymptom {
    /// 逻辑唯一键:`c:<uuid>`,UUID 保证全局唯一,天然不会有键冲突。
    var key: String = ""
    var label: String = ""
    var emoji: String = ""
    var createdAt: Date = Date.now

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
        // 用 reduce 后写赢而不是 Dictionary(uniqueKeysWithValues:):
        // 后者在 DB 出现重复 key(异常导入 / 数据恢复 / 未来版本)时会直接崩溃,
        // 而 CustomSymptomStore.refresh 在启动即触发,crash 会让 app 打不开。
        var map: [String: SymptomTag] = [:]
        for item in items {
            map[item.key] = SymptomTag(key: item.key, label: item.label, emoji: item.emoji)
        }
        byKey = map
    }

    static func tags() -> [SymptomTag] {
        byKey.values.sorted { $0.label < $1.label }
    }
}
