import Foundation

/// 层级 1 · 阶段科普内容加载器。本地 JSON,离线、双语。
enum PhaseInfo {

    private struct Entry: Decodable { let zh: String; let en: String }

    private static let library: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "phase_info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return dict
    }()

    private static var preferEnglish: Bool {
        let localization = Bundle.main.preferredLocalizations.first ?? "en"
        return !localization.hasPrefix("zh")
    }

    /// 某阶段的科普说明文字(按界面语言)。unknown 无内容。
    static func body(for phase: CyclePhase) -> String {
        guard let e = library[phase.rawValue] else { return "" }
        return preferEnglish ? e.en : e.zh
    }
}
