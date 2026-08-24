import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Shared, platform-neutral colour data used by the iPhone app, widgets and
/// watch targets.  Keeping the values as RGBA makes it impossible for one
/// target to silently drift from the others.
enum VelaPalette {
    struct RGBA: Equatable, Hashable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Relative luminance used by palette regression tests and contrast
        /// checks.  The alpha channel is deliberately excluded.
        var relativeLuminance: Double {
            func linear(_ value: Double) -> Double {
                let value = min(max(value, 0), 1)
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func contrastRatio(to other: RGBA) -> Double {
            let high = max(relativeLuminance, other.relativeLuminance)
            let low = min(relativeLuminance, other.relativeLuminance)
            return (high + 0.05) / (low + 0.05)
        }
    }

    struct Theme: Equatable, Sendable {
        let light: RGBA
        let dark: RGBA
        let lightOnAccent: RGBA
        let darkOnAccent: RGBA
    }

    // Light values are intentionally deep enough for white labels. Dark
    // values are brighter so accent text remains legible on a dark surface.
    static let rose = Theme(
        light: RGBA(0.74, 0.25, 0.33), dark: RGBA(0.98, 0.49, 0.58),
        lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0)
    )
    static let teal = Theme(
        light: RGBA(0.10, 0.48, 0.43), dark: RGBA(0.30, 0.80, 0.70),
        lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0)
    )
    static let violet = Theme(
        light: RGBA(0.38, 0.27, 0.70), dark: RGBA(0.66, 0.57, 0.98),
        lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0)
    )
    static let amber = Theme(
        light: RGBA(0.70, 0.36, 0.05), dark: RGBA(0.98, 0.70, 0.30),
        lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0)
    )
    static let ink = Theme(
        light: RGBA(0.18, 0.29, 0.52), dark: RGBA(0.50, 0.66, 0.96),
        lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0)
    )

    static func theme(for rawValue: String) -> Theme {
        switch rawValue {
        case "teal": return teal
        case "violet": return violet
        case "amber": return amber
        case "ink": return ink
        default: return rose
        }
    }

    static let white = RGBA(1, 1, 1)
    static let black = RGBA(0, 0, 0)

    /// Flow colours have their own semantic scale and are not changed by the
    /// selected accent theme.  The lightest two levels use dark ink for the
    /// date number so the number never disappears into the dot.
    static func flow(_ rawValue: Int) -> RGBA {
        switch rawValue {
        case 0: return RGBA(0.98, 0.76, 0.77)
        case 1: return RGBA(0.92, 0.57, 0.60)
        case 2: return RGBA(0.82, 0.36, 0.42)
        default: return RGBA(0.66, 0.20, 0.28)
        }
    }

    static func flowForeground(_ rawValue: Int) -> RGBA {
        rawValue <= 1 ? RGBA(0.16, 0.09, 0.11) : white
    }

    /// Stable category tones for tracker icons.  Light values are darkened
    /// and dark values lifted, while preserving the category's personality.
    static func trackerTheme(for categoryRawValue: String) -> Theme {
        switch categoryRawValue {
        case "pain":
            return Theme(light: RGBA(0.70, 0.30, 0.10), dark: RGBA(0.98, 0.63, 0.32), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "discharge":
            return Theme(light: RGBA(0.28, 0.34, 0.45), dark: RGBA(0.65, 0.72, 0.84), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "mood":
            return Theme(light: RGBA(0.40, 0.28, 0.72), dark: RGBA(0.68, 0.58, 0.98), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "sleep_energy":
            return Theme(light: RGBA(0.24, 0.38, 0.68), dark: RGBA(0.52, 0.66, 0.98), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "digestive":
            return Theme(light: RGBA(0.25, 0.52, 0.28), dark: RGBA(0.50, 0.80, 0.48), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "skin_hair":
            return Theme(light: RGBA(0.56, 0.33, 0.50), dark: RGBA(0.88, 0.60, 0.78), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "body":
            return Theme(light: RGBA(0.66, 0.24, 0.40), dark: RGBA(0.98, 0.50, 0.68), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "activity_wellbeing":
            return Theme(light: RGBA(0.12, 0.48, 0.43), dark: RGBA(0.32, 0.82, 0.72), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        case "sexual_reproductive":
            return Theme(light: RGBA(0.48, 0.29, 0.62), dark: RGBA(0.76, 0.58, 0.94), lightOnAccent: RGBA(1, 1, 1), darkOnAccent: RGBA(0, 0, 0))
        default: // bleeding_cycle
            return rose
        }
    }

    static func color(_ value: RGBA) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    static func color(light: RGBA, dark: RGBA, colorScheme: ColorScheme) -> Color {
        color(colorScheme == .dark ? dark : light)
    }

    /// iOS gets a true dynamic Color, so a single palette value follows the
    /// system appearance even when it is used outside a View's environment.
    /// watchOS uses the explicit colourScheme overload in its views/widgets.
    static func dynamicColor(light: RGBA, dark: RGBA) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        })
        #else
        color(light)
        #endif
    }
}
