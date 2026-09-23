import Foundation

/// 层级 1 · 阶段科普内容加载器。本地 JSON,离线、双语。
enum PhaseInfo {

    private struct Entry: Decodable { let zh: String; let en: String; let ja: String? }

    private static let library: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "phase_info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return dict
    }()

    private static var languageCode: String {
        let localization = Bundle.main.preferredLocalizations.first ?? "en"
        if localization.hasPrefix("zh") { return "zh" }
        if localization.hasPrefix("ja") { return "ja" }
        return "en"
    }

    /// 某阶段的科普说明文字(按界面语言)。unknown 无内容。
    static func body(for phase: CyclePhase) -> String {
        guard let e = library[phase.rawValue] else { return "" }
        switch languageCode {
        case "zh": return e.zh
        case "ja": return e.ja ?? e.en
        default:   return e.en
        }
    }

    /// 简短的「该注意什么」提示(按阶段),用于 widget 等紧凑展示。每个阶段都有(含 unknown)。
    static func tip(for phase: CyclePhase) -> String {
        switch phase {
        case .menstrual:  return String(localized: "多休息、注意保暖")
        case .follicular: return String(localized: "精力回升,适合开始新的事")
        case .ovulatory:  return String(localized: "状态通常最好,精力充沛")
        case .luteal:     return String(localized: "情绪可能起伏,对自己宽容点")
        case .unknown:    return String(localized: "多记几天,就能看到你的规律")
        }
    }
}
