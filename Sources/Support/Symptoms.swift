import Foundation

/// 预置症状标签。极简、可扩展;后续可做「自定义追踪项」。
struct SymptomTag: Identifiable, Hashable {
    let key: String
    let label: String
    let emoji: String
    var id: String { key }
}

enum Symptoms {
    static let all: [SymptomTag] = [
        SymptomTag(key: "cramps",    label: String(localized: "痛经"),   emoji: "🩸"),
        SymptomTag(key: "headache",  label: String(localized: "头痛"),   emoji: "🤕"),
        SymptomTag(key: "bloating",  label: String(localized: "腹胀"),   emoji: "🎈"),
        SymptomTag(key: "backache",  label: String(localized: "腰酸"),   emoji: "🔥"),
        SymptomTag(key: "tender",    label: String(localized: "乳房胀痛"), emoji: "💗"),
        SymptomTag(key: "acne",      label: String(localized: "痤疮"),   emoji: "🌋"),
        SymptomTag(key: "fatigue",   label: String(localized: "疲惫"),   emoji: "🥱"),
        SymptomTag(key: "nausea",    label: String(localized: "恶心"),   emoji: "🤢"),
        SymptomTag(key: "cravings",  label: String(localized: "食欲变化"), emoji: "🍫"),
        SymptomTag(key: "insomnia",  label: String(localized: "失眠"),   emoji: "🌙"),
        SymptomTag(key: "anxious",   label: String(localized: "焦虑"),   emoji: "😰"),
        SymptomTag(key: "irritable", label: String(localized: "易怒"),   emoji: "⚡️"),
        // PCOS 相关追踪项(层级 2)。
        SymptomTag(key: "hairloss",  label: String(localized: "脱发"),   emoji: "💇‍♀️"),
        SymptomTag(key: "hirsutism", label: String(localized: "多毛"),   emoji: "🧑‍🦱"),
    ]

    /// 内置 key -> tag,便于 O(1) 查询。
    private static let builtInByKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// 解析任意 key 的显示名(内置 + 自定义)。
    static func label(for key: String) -> String {
        if let t = builtInByKey[key] { return t.label }
        if let t = CustomSymptomStore.byKey[key] { return t.label }
        return key
    }

    /// 解析任意 key 的完整标签(含 emoji)。
    static func tag(for key: String) -> SymptomTag {
        builtInByKey[key] ?? CustomSymptomStore.byKey[key]
            ?? SymptomTag(key: key, label: key, emoji: "•")
    }
}
