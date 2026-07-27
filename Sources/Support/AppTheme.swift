import SwiftUI

/// 层级 4 · 主题(强调色)。改变 app 的品牌强调色 —— 标签栏、按钮、开关、链接等都跟随。
/// 刻意**不**改经血流量的红色系(那是语义色,代表经期),只换 app 的「气质色」。
enum AppTheme: String, CaseIterable, Identifiable {
    case rose      // 默认:玫瑰(现有品牌色)
    case teal      // 青
    case violet    // 紫
    case amber     // 琥珀
    case ink       // 墨蓝(中性)

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .rose:   return Color(red: 0.82, green: 0.36, blue: 0.42)
        case .teal:   return Color(red: 0.20, green: 0.62, blue: 0.56)
        case .violet: return Color(red: 0.45, green: 0.35, blue: 0.80)
        case .amber:  return Color(red: 0.90, green: 0.55, blue: 0.20)
        case .ink:    return Color(red: 0.24, green: 0.34, blue: 0.52)
        }
    }

    var label: String {
        switch self {
        case .rose:   return String(localized: "玫瑰")
        case .teal:   return String(localized: "青")
        case .violet: return String(localized: "紫")
        case .amber:  return String(localized: "琥珀")
        case .ink:    return String(localized: "墨蓝")
        }
    }

    static let storageKey = "theme"

    /// 供非 View 场景读取当前主题。
    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .rose
    }
}
