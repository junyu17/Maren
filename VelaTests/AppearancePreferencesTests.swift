import XCTest
import SwiftUI
@testable import Vela

final class AppearancePreferencesTests: XCTestCase {

    // MARK: - AppAppearanceMode

    func testAppearanceModeRawFallback() {
        // Empty string → system
        XCTAssertEqual(AppAppearanceMode(rawValue: "") ?? .system, .system)
        // Unknown raw value → system
        XCTAssertEqual(AppAppearanceMode(rawValue: "neon") ?? .system, .system)
        // Valid raw values
        XCTAssertEqual(AppAppearanceMode(rawValue: "system"), .system)
        XCTAssertEqual(AppAppearanceMode(rawValue: "light"), .light)
        XCTAssertEqual(AppAppearanceMode(rawValue: "dark"), .dark)
    }

    func testAppearanceModeColorSchemeMapping() {
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
    }

    func testAppearanceModeCaseIterable() {
        XCTAssertEqual(AppAppearanceMode.allCases.count, 3)
    }

    // MARK: - AppTextSizePreference

    func testTextSizePreferenceRawFallback() {
        XCTAssertEqual(AppTextSizePreference(rawValue: "") ?? .standard, .standard)
        XCTAssertEqual(AppTextSizePreference(rawValue: "huge") ?? .standard, .standard)
        XCTAssertEqual(AppTextSizePreference(rawValue: "small"), .small)
        XCTAssertEqual(AppTextSizePreference(rawValue: "standard"), .standard)
        XCTAssertEqual(AppTextSizePreference(rawValue: "large"), .large)
    }

    func testTextSizePreferenceCaseIterable() {
        XCTAssertEqual(AppTextSizePreference.allCases.count, 3)
    }

    // MARK: - adjustedSize: standard unchanged for every supported DynamicTypeSize

    func testStandardPreferenceUnchangedForAllSizes() {
        let allSizes: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]
        for size in allSizes {
            XCTAssertEqual(
                AppTextSizePreference.adjustedSize(size, preference: .standard),
                size,
                "standard should not change \(size)"
            )
        }
    }

    // MARK: - adjustedSize: small steps one step smaller

    func testSmallStepsDown() {
        let cases: [(DynamicTypeSize, DynamicTypeSize)] = [
            (.large,   .medium),
            (.medium,  .small),
            (.small,   .xSmall),
            (.xLarge,  .large),
            (.xxLarge, .xLarge),
            (.xxxLarge,.xxLarge),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(
                AppTextSizePreference.adjustedSize(input, preference: .small),
                expected,
                "\(input) + small should be \(expected)"
            )
        }
    }

    func testSmallClampsAtXSmall() {
        XCTAssertEqual(
            AppTextSizePreference.adjustedSize(.xSmall, preference: .small),
            .xSmall,
            "xSmall + small should remain xSmall"
        )
    }

    // MARK: - adjustedSize: large steps one step larger

    func testLargeStepsUp() {
        let cases: [(DynamicTypeSize, DynamicTypeSize)] = [
            (.xSmall,  .small),
            (.small,   .medium),
            (.medium,  .large),
            (.large,   .xLarge),
            (.xLarge,  .xxLarge),
            (.xxLarge, .xxxLarge),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(
                AppTextSizePreference.adjustedSize(input, preference: .large),
                expected,
                "\(input) + large should be \(expected)"
            )
        }
    }

    func testLargeClampsAtAccessibility5() {
        XCTAssertEqual(
            AppTextSizePreference.adjustedSize(.accessibility5, preference: .large),
            .accessibility5,
            "accessibility5 + large should remain accessibility5"
        )
    }

    // MARK: - adjustedSize: small within accessibility stays in accessibility

    func testSmallWithinAccessibilityNeverCrossesIntoNormal() {
        let accessibilityCases: [(DynamicTypeSize, DynamicTypeSize)] = [
            (.accessibility1, .accessibility1),
            (.accessibility2, .accessibility1),
            (.accessibility3, .accessibility2),
            (.accessibility4, .accessibility3),
            (.accessibility5, .accessibility4),
        ]
        for (input, expected) in accessibilityCases {
            let result = AppTextSizePreference.adjustedSize(input, preference: .small)
            XCTAssertEqual(result, expected, "\(input) + small should be \(expected)")
        }
    }

    func testSmallFromBoundaryAccessibility1StaysAccessibility1() {
        XCTAssertEqual(
            AppTextSizePreference.adjustedSize(.accessibility1, preference: .small),
            .accessibility1,
            "accessibility1 + small should remain accessibility1"
        )
    }

    // MARK: - adjustedSize: large from accessibility sizes

    func testLargeFromAccessibilityStepsUp() {
        XCTAssertEqual(
            AppTextSizePreference.adjustedSize(.accessibility1, preference: .large),
            .accessibility2
        )
        XCTAssertEqual(
            AppTextSizePreference.adjustedSize(.accessibility4, preference: .large),
            .accessibility5
        )
    }

    func testLargeClampsAtAccessibility5FromAccessibility4() {
        XCTAssertEqual(
            AppTextSizePreference.adjustedSize(.accessibility4, preference: .large),
            .accessibility5
        )
    }

    // MARK: - allSizes count & order

    func testAllSizesCount() {
        XCTAssertEqual(AppTextSizePreference.allSizes.count, 12)
    }

    func testAllSizesStartAndEnd() {
        XCTAssertEqual(AppTextSizePreference.allSizes.first, .xSmall)
        XCTAssertEqual(AppTextSizePreference.allSizes.last, .accessibility5)
    }
}
