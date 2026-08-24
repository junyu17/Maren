import SwiftUI

// MARK: - Appearance mode (Follow System / Light / Dark)

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    /// Maps to SwiftUI `ColorScheme?`. `nil` means follow system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    static let storageKey = "appearance.colorScheme"

    /// Reads the persisted value; invalid / missing raw value falls back to `.system`.
    static var current: AppAppearanceMode {
        AppAppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}

// MARK: - Text size preference (Smaller / System Default / Larger)

enum AppTextSizePreference: String, CaseIterable {
    case small
    case standard
    case large

    var label: LocalizedStringKey {
        switch self {
        case .small:    return "较小"
        case .standard: return "系统默认"
        case .large:    return "较大"
        }
    }

    static let storageKey = "appearance.textSize"

    /// Reads the persisted value; invalid / missing raw value falls back to `.standard`.
    static var current: AppTextSizePreference {
        AppTextSizePreference(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .standard
    }

    // MARK: Dynamic Type adjustment

    /// Ordered list of all DynamicTypeSizes, from smallest to largest.
    /// Accessibility sizes are kept in the same ordered sequence so that
    /// small/large stepping within accessibility stays inside accessibility.
    static let allSizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
    ]

    /// Pure function: given the system's current DynamicTypeSize and the
    /// user's preference, return the adjusted size.
    ///
    /// Rules:
    /// - `.standard` returns `current` unchanged.
    /// - `.small` steps one index smaller; clamps at `.xSmall`.
    /// - `.large` steps one index larger; clamps at `.accessibility5`.
    /// - If system size is an accessibility size, `.small` never crosses back
    ///   into a non-accessibility size (e.g. accessibility1 + small = accessibility1).
    static func adjustedSize(_ current: DynamicTypeSize, preference: AppTextSizePreference) -> DynamicTypeSize {
        guard preference != .standard else { return current }
        guard let idx = allSizes.firstIndex(of: current) else { return current }

        switch preference {
        case .small:
            // Never cross from accessibility back into non-accessibility.
            if current.isAccessibilitySize {
                // Walk backwards but stop at the boundary.
                let firstAccessibilityIdx = allSizes.firstIndex(of: .accessibility1)!
                return idx > firstAccessibilityIdx ? allSizes[idx - 1] : current
            }
            return idx > 0 ? allSizes[idx - 1] : current

        case .large:
            return idx < allSizes.count - 1 ? allSizes[idx + 1] : current

        case .standard:
            return current
        }
    }
}

// MARK: - DynamicTypeSize convenience helpers

private extension DynamicTypeSize {
    var isAccessibilitySize: Bool {
        switch self {
        case .accessibility1, .accessibility2, .accessibility3,
             .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}
