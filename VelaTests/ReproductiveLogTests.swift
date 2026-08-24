import XCTest
@testable import Vela

final class ReproductiveLogTests: XCTestCase {
    private let unrelatedKeys: Set<String> = ["cramps", "mood_good", "custom_tracker"]

    func testOvulationSelectionIsMutuallyExclusiveAndPreservesUnrelatedKeys() {
        let initial = unrelatedKeys
            .union([ReproductiveLog.OvulationTest.negative.rawValue])
            .union([ReproductiveLog.OvulationTest.peak.rawValue])

        let selected = ReproductiveLog.selectingOvulationTest(
            .positive,
            in: initial
        )

        XCTAssertEqual(
            selected,
            unrelatedKeys.union([ReproductiveLog.OvulationTest.positive.rawValue])
        )
        XCTAssertEqual(ReproductiveLog.ovulationTest(in: selected), .positive)
    }

    func testSelectingNoOvulationResultClearsOnlyThatGroup() {
        let initial = unrelatedKeys
            .union([ReproductiveLog.OvulationTest.negative.rawValue])
            .union([ReproductiveLog.OvulationTest.positive.rawValue])
        let cleared = ReproductiveLog.selectingOvulationTest(nil, in: initial)

        XCTAssertEqual(cleared, unrelatedKeys)
        XCTAssertNil(ReproductiveLog.ovulationTest(in: cleared))
    }

    func testManualOvulationIsIndependentFromOvulationTestSelection() {
        let withManual = ReproductiveLog.settingManualOvulation(
            true,
            in: ReproductiveLog.selectingOvulationTest(.peak, in: unrelatedKeys)
        )
        XCTAssertTrue(withManual.contains(ReproductiveLog.manualOvulationKey))
        XCTAssertEqual(ReproductiveLog.ovulationTest(in: withManual), .peak)

        let withoutManual = ReproductiveLog.settingManualOvulation(false, in: withManual)
        XCTAssertFalse(withoutManual.contains(ReproductiveLog.manualOvulationKey))
        XCTAssertEqual(ReproductiveLog.ovulationTest(in: withoutManual), .peak)
        XCTAssertEqual(withoutManual.subtracting(ReproductiveLog.ovulationTestKeys), unrelatedKeys)
    }

    func testPregnancySelectionIsMutuallyExclusiveAndRoundTrips() {
        var keys = ReproductiveLog.selectingPregnancyTest(.invalid, in: unrelatedKeys)
        XCTAssertEqual(ReproductiveLog.pregnancyTest(in: keys), .invalid)

        keys = ReproductiveLog.selectingPregnancyTest(.negative, in: keys)
        XCTAssertEqual(ReproductiveLog.pregnancyTest(in: keys), .negative)
        XCTAssertTrue(keys.isSuperset(of: unrelatedKeys))
        XCTAssertEqual(keys.intersection(ReproductiveLog.pregnancyTestKeys), [
            ReproductiveLog.PregnancyTest.negative.rawValue
        ])
    }

    func testSelectingNoPregnancyResultClearsOnlyThatGroup() {
        let initial = unrelatedKeys
            .union([ReproductiveLog.PregnancyTest.positive.rawValue])
        let cleared = ReproductiveLog.selectingPregnancyTest(nil, in: initial)

        XCTAssertEqual(cleared, unrelatedKeys)
        XCTAssertNil(ReproductiveLog.pregnancyTest(in: cleared))
    }

    func testStringSelectionSupportsEmptyValueAsClear() {
        let initial = unrelatedKeys
            .union([ReproductiveLog.OvulationTest.positive.rawValue])
            .union([ReproductiveLog.PregnancyTest.positive.rawValue])

        let clearedOvulation = ReproductiveLog.setOvulationTest("", in: initial)
        let clearedBoth = ReproductiveLog.setPregnancyTest("", in: clearedOvulation)

        XCTAssertEqual(clearedBoth, unrelatedKeys)
    }
}
