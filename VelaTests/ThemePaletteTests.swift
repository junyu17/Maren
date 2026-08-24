import XCTest
@testable import Vela

final class ThemePaletteTests: XCTestCase {
    func testAllThemesHaveDistinctLightAndDarkAccents() {
        let themes = [VelaPalette.rose, VelaPalette.teal, VelaPalette.violet,
                      VelaPalette.amber, VelaPalette.ink]

        XCTAssertEqual(Set(themes.map(\.light)).count, 5)
        XCTAssertEqual(Set(themes.map(\.dark)).count, 5)
        for theme in themes {
            XCTAssertGreaterThanOrEqual(theme.light.contrastRatio(to: theme.lightOnAccent), 4.5)
            XCTAssertGreaterThanOrEqual(theme.dark.contrastRatio(to: theme.darkOnAccent), 4.5)
        }
    }

    func testRawThemeFallbackAndWatchInk() {
        XCTAssertEqual(VelaPalette.theme(for: "not-a-theme"), VelaPalette.rose)
        XCTAssertEqual(VelaPalette.theme(for: "ink"), VelaPalette.ink)
    }

    func testLightFlowUsesDarkInkForDateText() {
        XCTAssertEqual(VelaPalette.flowForeground(0), VelaPalette.flowForeground(1))
        XCTAssertEqual(VelaPalette.flowForeground(2), VelaPalette.white)
        XCTAssertGreaterThan(VelaPalette.flow(0).contrastRatio(to: VelaPalette.flowForeground(0)), 4.5)
        XCTAssertGreaterThan(VelaPalette.flow(1).contrastRatio(to: VelaPalette.flowForeground(1)), 4.5)
    }

    func testTrackerCategoryTonesAreReadableInBothAppearances() {
        let rawCategories = [
            "bleeding_cycle", "pain", "discharge", "mood", "sleep_energy",
            "digestive", "skin_hair", "body", "activity_wellbeing", "sexual_reproductive"
        ]
        for raw in rawCategories {
            let theme = VelaPalette.trackerTheme(for: raw)
            XCTAssertGreaterThanOrEqual(theme.light.contrastRatio(to: VelaPalette.white), 3.0)
            XCTAssertGreaterThanOrEqual(theme.dark.contrastRatio(to: VelaPalette.black), 3.0)
        }
    }
}
