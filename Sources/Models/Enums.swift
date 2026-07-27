import Foundation
import SwiftUI

/// 经血流量。刻意从「点滴」到「大量」四档,够用且不吓人。
enum FlowLevel: Int, Codable, CaseIterable, Identifiable {
    case spotting = 0
    case light
    case medium
    case heavy

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .spotting: return String(localized: "点滴")
        case .light:    return String(localized: "少量")
        case .medium:   return String(localized: "中量")
        case .heavy:    return String(localized: "大量")
        }
    }

    /// 用点的数量表示强度。
    var dots: Int { rawValue + 1 }

    var tint: Color {
        switch self {
        case .spotting: return Color(red: 0.95, green: 0.72, blue: 0.72)
        case .light:    return Color(red: 0.90, green: 0.55, blue: 0.58)
        case .medium:   return Color(red: 0.82, green: 0.36, blue: 0.42)
        case .heavy:    return Color(red: 0.66, green: 0.20, blue: 0.28)
        }
    }
}

/// 心情。5 档,配 emoji,3 秒可选。
enum Mood: Int, Codable, CaseIterable, Identifiable {
    case great = 5
    case good = 4
    case okay = 3
    case low = 2
    case bad = 1

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .great: return "😄"
        case .good:  return "🙂"
        case .okay:  return "😐"
        case .low:   return "😕"
        case .bad:   return "😣"
        }
    }

    var label: String {
        switch self {
        case .great: return String(localized: "很好")
        case .good:  return String(localized: "不错")
        case .okay:  return String(localized: "一般")
        case .low:   return String(localized: "低落")
        case .bad:   return String(localized: "很糟")
        }
    }
}
