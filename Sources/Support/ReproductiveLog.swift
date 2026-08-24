import Foundation

/// Pure transformations for the reproductive-test tracker keys.
///
/// The tracker set belongs to the caller (for example, a day's `Set<String>`
/// of entries). These helpers only replace keys in their own group and leave
/// every unrelated tracker key untouched.
enum ReproductiveLog {
    enum OvulationTest: String, CaseIterable, Codable, Hashable {
        case negative = "ovulation_test_negative"
        case positive = "ovulation_test_positive"
        case peak = "ovulation_test_peak"
    }

    enum PregnancyTest: String, CaseIterable, Codable, Hashable {
        case negative = "pregnancy_test_negative"
        case positive = "pregnancy_test_positive"
        case invalid = "pregnancy_test_invalid"
    }

    static let ovulationTestKeys: Set<String> = Set(OvulationTest.allCases.map(\.rawValue))
    static let pregnancyTestKeys: Set<String> = Set(PregnancyTest.allCases.map(\.rawValue))
    static let manualOvulationKey = "manual_ovulation"

    /// Replace the same-day ovulation-test choice. `nil` (or an empty key)
    /// clears all ovulation-test keys without affecting other trackers.
    static func selectingOvulationTest(
        _ selection: OvulationTest?,
        in keys: Set<String>
    ) -> Set<String> {
        replacing(keys, in: ovulationTestKeys, with: selection?.rawValue)
    }

    /// String-based overload for SwiftUI controls and import callers.
    static func selectingOvulationTest(
        _ rawValue: String,
        in keys: Set<String>
    ) -> Set<String> {
        selectingOvulationTest(OvulationTest(rawValue: rawValue), in: keys)
    }

    /// Replace the same-day pregnancy-test choice. `nil` (or an empty key)
    /// clears all pregnancy-test keys without affecting other trackers.
    static func selectingPregnancyTest(
        _ selection: PregnancyTest?,
        in keys: Set<String>
    ) -> Set<String> {
        replacing(keys, in: pregnancyTestKeys, with: selection?.rawValue)
    }

    /// String-based overload for SwiftUI controls and import callers.
    static func selectingPregnancyTest(
        _ rawValue: String,
        in keys: Set<String>
    ) -> Set<String> {
        selectingPregnancyTest(PregnancyTest(rawValue: rawValue), in: keys)
    }

    /// Toggle the independent manual ovulation entry. This never changes the
    /// selected ovulation-test result.
    static func settingManualOvulation(_ enabled: Bool, in keys: Set<String>) -> Set<String> {
        var result = keys
        if enabled {
            result.insert(manualOvulationKey)
        } else {
            result.remove(manualOvulationKey)
        }
        return result
    }

    static func ovulationTest(in keys: Set<String>) -> OvulationTest? {
        OvulationTest.allCases.first { keys.contains($0.rawValue) }
    }

    static func pregnancyTest(in keys: Set<String>) -> PregnancyTest? {
        PregnancyTest.allCases.first { keys.contains($0.rawValue) }
    }

    static func hasManualOvulation(in keys: Set<String>) -> Bool {
        keys.contains(manualOvulationKey)
    }

    // MARK: Compatibility-friendly aliases

    static func setOvulationTest(_ selection: OvulationTest?, in keys: Set<String>) -> Set<String> {
        selectingOvulationTest(selection, in: keys)
    }

    static func setOvulationTest(_ rawValue: String, in keys: Set<String>) -> Set<String> {
        selectingOvulationTest(rawValue, in: keys)
    }

    static func setPregnancyTest(_ selection: PregnancyTest?, in keys: Set<String>) -> Set<String> {
        selectingPregnancyTest(selection, in: keys)
    }

    static func setPregnancyTest(_ rawValue: String, in keys: Set<String>) -> Set<String> {
        selectingPregnancyTest(rawValue, in: keys)
    }

    static func setManualOvulation(_ enabled: Bool, in keys: Set<String>) -> Set<String> {
        settingManualOvulation(enabled, in: keys)
    }

    private static func replacing(
        _ keys: Set<String>,
        in group: Set<String>,
        with selectedKey: String?
    ) -> Set<String> {
        var result = keys
        result.subtract(group)
        if let selectedKey, group.contains(selectedKey) {
            result.insert(selectedKey)
        }
        return result
    }
}
