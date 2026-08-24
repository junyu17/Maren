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

    var palette: VelaPalette.Theme { VelaPalette.theme(for: rawValue) }

    /// Dynamic on iPhone/iPad: light mode uses a deep accent for white labels,
    /// dark mode uses a lifted accent so coloured text remains readable.
    var accent: Color {
        VelaPalette.dynamicColor(light: palette.light, dark: palette.dark)
    }

    /// Foreground to use on an accent-filled control (selected weekday, CTA,
    /// etc.).  This prevents bright dark-mode accents from getting white text
    /// with insufficient contrast.
    var onAccent: Color {
        VelaPalette.dynamicColor(light: palette.lightOnAccent, dark: palette.darkOnAccent)
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

// MARK: - MarenDesign · Lightweight visual tokens

/// Reusable visual tokens derived from the current AppTheme accent.
/// Geometry, colour, and card modifiers only — keep this lean.
enum MarenDesign {

    // MARK: Spacing

    static let spacingXS: CGFloat = 4
    static let spacingS:  CGFloat = 8
    static let spacingM:  CGFloat = 12
    static let spacingL:  CGFloat = 16
    static let spacingXL: CGFloat = 20
    static let spacingXXL: CGFloat = 24

    // MARK: Corner Radius

    static let radiusS:  CGFloat = 10
    static let radiusM:  CGFloat = 14
    static let radiusL:  CGFloat = 16
    static let radiusXL: CGFloat = 20

    // MARK: Shadow / Stroke

    static let shadowRadius: CGFloat = 6
    static let shadowOpacity: Double = 0.08
    static let strokeWidth: CGFloat = 0.5

    // MARK: Accent-derived Surface Colours

    /// Background tint derived from the current accent.
    static func accentTint(opacity: Double = 0.10) -> Color {
        AppTheme.current.accent.opacity(opacity)
    }

    /// Slightly elevated surface (cards sitting on the page background).
    static var surface: Color {
        Color(.secondarySystemBackground)
    }

    /// Elevated surface (cards floating above other cards, sheets, popovers).
    static var elevatedSurface: Color {
        Color(.tertiarySystemBackground)
    }

    /// Accent capsule / pill fill used for badges and chips.
    static func accentCapsuleFill(opacity: Double = 0.14) -> Color {
        AppTheme.current.accent.opacity(opacity)
    }

    // MARK: Card Modifiers

    /// A minimal card style: rounded corners + subtle shadow on a secondary-system background.
    struct CardStyle: ViewModifier {
        var cornerRadius: CGFloat = MarenDesign.radiusL
        var fill: Color = MarenDesign.surface
        var shadowed: Bool = true

        func body(content: Content) -> some View {
            content
                .padding(MarenDesign.spacingL)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(
                    color: .black.opacity(shadowed ? MarenDesign.shadowOpacity : 0),
                    radius: shadowed ? MarenDesign.shadowRadius : 0,
                    y: shadowed ? 2 : 0
                )
        }
    }

    /// Accent-tinted card variant (prediction card, quote bar, etc.).
    struct AccentCardStyle: ViewModifier {
        var cornerRadius: CGFloat = MarenDesign.radiusM
        var tintOpacity: Double = 0.14

        func body(content: Content) -> some View {
            content
                .padding(MarenDesign.spacingL)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MarenDesign.accentTint(opacity: tintOpacity),
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
        }
    }

    /// Thin outline card (for sections that need separation without heaviness).
    struct OutlineCardStyle: ViewModifier {
        var cornerRadius: CGFloat = MarenDesign.radiusM
        var strokeColor: Color = Color(.separator).opacity(0.35)

        func body(content: Content) -> some View {
            content
                .padding(MarenDesign.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(strokeColor, lineWidth: MarenDesign.strokeWidth)
                )
        }
    }
}

// MARK: - View convenience

extension View {
    /// Apply the standard card style.
    func marenCard(cornerRadius: CGFloat = MarenDesign.radiusL,
                   fill: Color = MarenDesign.surface,
                   shadowed: Bool = true) -> some View {
        modifier(MarenDesign.CardStyle(cornerRadius: cornerRadius, fill: fill, shadowed: shadowed))
    }

    /// Apply the accent-tinted card style.
    func marenAccentCard(cornerRadius: CGFloat = MarenDesign.radiusM,
                         tintOpacity: Double = 0.14) -> some View {
        modifier(MarenDesign.AccentCardStyle(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }

    /// Apply the outline card style.
    func marenOutlineCard(cornerRadius: CGFloat = MarenDesign.radiusM,
                          strokeColor: Color = Color(.separator).opacity(0.35)) -> some View {
        modifier(MarenDesign.OutlineCardStyle(cornerRadius: cornerRadius, strokeColor: strokeColor))
    }
}
