import Foundation
import XCTest
@testable import Vela

/// TodayStatusEngine 状态生成测试。
final class TodayStatusEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func input(mood: Int? = nil, energy: Int? = nil, pain: Int? = nil,
                       sleepHours: Double? = nil, steps: Int? = nil,
                       exerciseMinutes: Int? = nil, trackerKeys: Set<String> = [],
                       phase: String? = nil, isPerimenopause: Bool = false) -> TodayStatusEngine.Input {
        TodayStatusEngine.Input(
            date: Date(),
            phase: phase,
            mood: mood,
            energy: energy,
            pain: pain,
            sleepHours: sleepHours,
            steps: steps,
            exerciseMinutes: exerciseMinutes,
            trackerKeys: trackerKeys,
            isPerimenopause: isPerimenopause
        )
    }

    // MARK: - Helpers for localized string expectations

    private func localizedMood(_ value: Int) -> String {
        String(localized: "Mood %d/5", defaultValue: "Mood %d/5", comment: "Mood observation")
            .replacingOccurrences(of: "%d", with: "\(value)")
    }

    private func localizedEnergy(_ value: Int) -> String {
        String(localized: "Energy %d/5", defaultValue: "Energy %d/5", comment: "Energy observation")
            .replacingOccurrences(of: "%d", with: "\(value)")
    }

    private func localizedPain(_ value: Int) -> String {
        String(localized: "Pain %d/5", defaultValue: "Pain %d/5", comment: "Pain observation")
            .replacingOccurrences(of: "%d", with: "\(value)")
    }

    private func localizedSleep(_ hours: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        let formatted = formatter.string(from: NSNumber(value: hours)) ?? "\(hours)"
        return String(localized: "Sleep %@ hours", defaultValue: "Sleep %@ hours", comment: "Sleep observation")
            .replacingOccurrences(of: "%@", with: formatted)
    }

    private func localizedSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        let formatted = formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        return String(localized: "%@ steps", defaultValue: "%@ steps", comment: "Steps observation")
            .replacingOccurrences(of: "%@", with: formatted)
    }

    private func localizedExercise(_ minutes: Int) -> String {
        String(localized: "%d minutes exercise", defaultValue: "%d minutes exercise", comment: "Exercise observation")
            .replacingOccurrences(of: "%d", with: "\(minutes)")
    }

    private func localizedPhase(_ phase: String) -> String {
        let label: String
        switch phase {
        case "menstrual":  label = String(localized: "menstrual", comment: "Menstrual phase")
        case "follicular": label = String(localized: "follicular", comment: "Follicular phase")
        case "ovulatory":  label = String(localized: "ovulatory", comment: "Ovulatory phase")
        case "luteal":     label = String(localized: "luteal", comment: "Luteal phase")
        default: return ""
        }
        return String(localized: "Estimated to be in %@.", defaultValue: "Estimated to be in %@.", comment: "Phase observation")
            .replacingOccurrences(of: "%@", with: label)
    }

    private let perimenopauseHotFlashString = String(localized: "You logged hot flashes or night sweats.", comment: "Perimenopause hot flashes/night sweats observation")

    private func localizedSingleTracker(_ key: String) -> String {
        String(localized: "You logged %@.", defaultValue: "You logged %@.", comment: "Single tracker observation")
            .replacingOccurrences(of: "%@", with: Symptoms.label(for: key))
    }

    private func localizedMultipleTrackers(_ count: Int) -> String {
        String(localized: "You logged %d trackers.", defaultValue: "You logged %d trackers.", comment: "Multiple trackers observation")
            .replacingOccurrences(of: "%d", with: "\(count)")
    }

    private let noRecordsTitle = String(localized: "今天还没有记录")
    private let statusTitle = String(localized: "今日状态")

    // MARK: - Empty data

    func testEmptyDataIsSparse() {
        let result = TodayStatusEngine.evaluate(input())
        XCTAssertTrue(result.isDataSparse)
        XCTAssertEqual(result.observations.count, 0)
        XCTAssertEqual(result.title, noRecordsTitle)
    }

    func testNonEmptyDataIsNotSparse() {
        let result = TodayStatusEngine.evaluate(input(mood: 3))
        XCTAssertFalse(result.isDataSparse)
        XCTAssertEqual(result.title, statusTitle)
    }

    func testNonSparseImpliesNonempty() {
        // Phase alone should NOT make data non-sparse (phase-only removed from non-sparse invariant)
        let cases: [TodayStatusEngine.Input] = [
            input(mood: 3),
            input(energy: 3),
            input(pain: 3),
            input(sleepHours: 7),
            input(steps: 5000),
            input(exerciseMinutes: 15),
            input(trackerKeys: ["cramps"]),
            input(trackerKeys: ["hotFlashes"], isPerimenopause: true),
        ]
        for caseInput in cases {
            let result = TodayStatusEngine.evaluate(caseInput)
            XCTAssertFalse(result.isDataSparse, "Input should not be sparse")
            XCTAssertFalse(result.observations.isEmpty, "Non-sparse input must produce observations")
        }
    }

    func testPhaseAloneIsSparse() {
        let result = TodayStatusEngine.evaluate(input(phase: "menstrual"))
        XCTAssertTrue(result.isDataSparse)
    }

    // MARK: - Mood

    func testMoodObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(mood: 5))
        XCTAssertTrue(result.observations.contains(localizedMood(5)))
    }

    func testLowMoodObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(mood: 1))
        XCTAssertTrue(result.observations.contains(localizedMood(1)))
    }

    func testNeutralMoodObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(mood: 3))
        XCTAssertTrue(result.observations.contains(localizedMood(3)))
    }

    // MARK: - Energy

    func testEnergyObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(energy: 5))
        XCTAssertTrue(result.observations.contains(localizedEnergy(5)))
    }

    func testLowEnergyObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(energy: 1))
        XCTAssertTrue(result.observations.contains(localizedEnergy(1)))
    }

    func testNeutralEnergyObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(energy: 3))
        XCTAssertTrue(result.observations.contains(localizedEnergy(3)))
    }

    // MARK: - Pain

    func testPainObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(pain: 5))
        XCTAssertTrue(result.observations.contains(localizedPain(5)))
    }

    func testLowPainObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(pain: 1))
        XCTAssertTrue(result.observations.contains(localizedPain(1)))
    }

    func testNeutralPainObservationReportsExactValue() {
        let result = TodayStatusEngine.evaluate(input(pain: 3))
        XCTAssertTrue(result.observations.contains(localizedPain(3)))
    }

    // MARK: - Sleep

    func testSleepObservationReportsActualHours() {
        let result = TodayStatusEngine.evaluate(input(sleepHours: 7.5))
        XCTAssertTrue(result.observations.contains(localizedSleep(7.5)))
    }

    func testSleepObservationReportsIntegerHours() {
        let result = TodayStatusEngine.evaluate(input(sleepHours: 8))
        XCTAssertTrue(result.observations.contains(localizedSleep(8)))
    }

    func testSleepLowerBoundaryReportsActualHours() {
        let result = TodayStatusEngine.evaluate(input(sleepHours: 6))
        XCTAssertTrue(result.observations.contains(localizedSleep(6)))
    }

    func testSleepUpperBoundaryReportsActualHours() {
        let result = TodayStatusEngine.evaluate(input(sleepHours: 9))
        XCTAssertTrue(result.observations.contains(localizedSleep(9)))
    }

    // MARK: - Steps

    func testStepsReportsActualLocalizedCount() {
        let result = TodayStatusEngine.evaluate(input(steps: 12000))
        XCTAssertTrue(result.observations.contains(localizedSteps(12000)))
    }

    func testLowStepsReportsActualLocalizedCount() {
        let result = TodayStatusEngine.evaluate(input(steps: 3000))
        XCTAssertTrue(result.observations.contains(localizedSteps(3000)))
    }

    func testExactStepsReportsActualLocalizedCount() {
        let result = TodayStatusEngine.evaluate(input(steps: 10000))
        XCTAssertTrue(result.observations.contains(localizedSteps(10000)))
    }

    // MARK: - Exercise

    func testExerciseReportsActualMinutes() {
        let result = TodayStatusEngine.evaluate(input(exerciseMinutes: 45))
        XCTAssertTrue(result.observations.contains(localizedExercise(45)))
    }

    func testShortExerciseReportsActualMinutes() {
        let result = TodayStatusEngine.evaluate(input(exerciseMinutes: 10))
        XCTAssertTrue(result.observations.contains(localizedExercise(10)))
    }

    // MARK: - Tracker-only

    func testSingleTrackerUsesLabel() {
        let result = TodayStatusEngine.evaluate(input(trackerKeys: ["cramps"]))
        XCTAssertTrue(result.observations.contains(localizedSingleTracker("cramps")))
    }

    func testMultipleTrackersReportCount() {
        let result = TodayStatusEngine.evaluate(input(trackerKeys: ["cramps", "headache", "bloating"]))
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertTrue(result.observations.contains(localizedMultipleTrackers(3)))
    }

    func testTrackerNotUsedWhenHigherPriorityPresent() {
        let result = TodayStatusEngine.evaluate(
            input(mood: 5, energy: 5, pain: 5, trackerKeys: ["cramps"])
        )
        XCTAssertEqual(result.observations.count, 3)
        XCTAssertFalse(result.observations.contains(localizedSingleTracker("cramps")))
    }

    func testTrackerFillsRemainingSlot() {
        let result = TodayStatusEngine.evaluate(
            input(mood: 5, trackerKeys: ["headache"])
        )
        XCTAssertEqual(result.observations.count, 2)
        XCTAssertTrue(result.observations.contains(localizedSingleTracker("headache")))
    }

    func testTrackerOnlyIsNonSparse() {
        let result = TodayStatusEngine.evaluate(input(trackerKeys: ["cramps"]))
        XCTAssertFalse(result.isDataSparse)
    }

    // MARK: - Perimenopause

    func testPerimenopauseHotFlashObservation() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["hotFlashes"], isPerimenopause: true)
        )
        XCTAssertTrue(result.observations.contains(perimenopauseHotFlashString))
    }

    func testPerimenopauseNightSweatsObservation() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["nightSweats"], isPerimenopause: true)
        )
        XCTAssertTrue(result.observations.contains(perimenopauseHotFlashString))
    }

    func testPerimenopauseBothHotFlashAndNightSweatsSingleObservation() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["hotFlashes", "nightSweats"], isPerimenopause: true)
        )
        // Should only produce one perimenopause observation, not two
        let count = result.observations.filter { $0 == perimenopauseHotFlashString }.count
        XCTAssertEqual(count, 1)
    }

    func testPerimenopauseNoHotFlashNoObservation() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["cramps"], isPerimenopause: true)
        )
        XCTAssertFalse(result.observations.contains(perimenopauseHotFlashString))
    }

    func testPerimenopauseHotFlashObservationBeforeGenericTracker() {
        // Perimenopause observation should appear before generic tracker summary
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["hotFlashes", "cramps"], isPerimenopause: true)
        )
        guard let periIdx = result.observations.firstIndex(of: perimenopauseHotFlashString) else {
            XCTFail("Missing perimenopause observation"); return
        }
        // Generic tracker for cramps should appear after (if there's room)
        if let trackerIdx = result.observations.firstIndex(of: localizedSingleTracker("cramps")) {
            XCTAssertLessThan(periIdx, trackerIdx, "Perimenopause observation should come before generic tracker")
        }
    }

    func testNonPerimenopauseHotFlashesAllowsGenericTracker() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["hotFlashes"], isPerimenopause: false)
        )
        // Should NOT contain the special perimenopause sentence
        XCTAssertFalse(result.observations.contains(perimenopauseHotFlashString))
        // SHOULD contain generic tracker observation
        XCTAssertTrue(result.observations.contains(localizedSingleTracker("hotFlashes")))
    }

    func testNonPerimenopauseNightSweatsAllowsGenericTracker() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["nightSweats"], isPerimenopause: false)
        )
        XCTAssertFalse(result.observations.contains(perimenopauseHotFlashString))
        XCTAssertTrue(result.observations.contains(localizedSingleTracker("nightSweats")))
    }

    func testNonPerimenopauseHotFlashesWithOtherTrackers() {
        let result = TodayStatusEngine.evaluate(
            input(trackerKeys: ["hotFlashes", "cramps"], isPerimenopause: false)
        )
        XCTAssertFalse(result.observations.contains(perimenopauseHotFlashString))
        // Should show multiple trackers count
        XCTAssertTrue(result.observations.contains(localizedMultipleTrackers(2)))
    }

    func testPerimenopauseFlagAloneIsSparse() {
        let result = TodayStatusEngine.evaluate(input(isPerimenopause: true))
        XCTAssertTrue(result.isDataSparse)
    }

    // MARK: - Phase

    func testMenstrualPhaseObservation() {
        let result = TodayStatusEngine.evaluate(input(phase: "menstrual"))
        XCTAssertTrue(result.observations.contains(localizedPhase("menstrual")))
    }

    func testLutealPhaseObservation() {
        let result = TodayStatusEngine.evaluate(input(phase: "luteal"))
        XCTAssertTrue(result.observations.contains(localizedPhase("luteal")))
    }

    func testFollicularPhaseObservation() {
        let result = TodayStatusEngine.evaluate(input(phase: "follicular"))
        XCTAssertTrue(result.observations.contains(localizedPhase("follicular")))
    }

    func testOvulatoryPhaseObservation() {
        let result = TodayStatusEngine.evaluate(input(phase: "ovulatory"))
        XCTAssertTrue(result.observations.contains(localizedPhase("ovulatory")))
    }

    func testPhaseUsesEstimatedWording() {
        let result = TodayStatusEngine.evaluate(input(phase: "menstrual"))
        XCTAssertTrue(result.observations.contains { $0.contains(String(localized: "Estimated", defaultValue: "Estimated", comment: "Phase estimated wording")) })
    }

    func testUnknownPhaseNoObservation() {
        let result = TodayStatusEngine.evaluate(input(phase: "unknown"))
        XCTAssertFalse(result.observations.contains { $0.contains(String(localized: "Estimated", defaultValue: "Estimated", comment: "Phase estimated wording")) })
    }

    func testPhaseAloneRemainsSparse() {
        let result = TodayStatusEngine.evaluate(input(phase: "menstrual"))
        XCTAssertTrue(result.isDataSparse)
        // But should still produce the phase observation
        XCTAssertTrue(result.observations.contains(localizedPhase("menstrual")))
    }

    // MARK: - Max 3 observations

    func testMaxThreeObservations() {
        let result = TodayStatusEngine.evaluate(
            input(mood: 5, energy: 5, pain: 5, sleepHours: 4, steps: 15000,
                  exerciseMinutes: 60, trackerKeys: ["cramps"], phase: "menstrual")
        )
        XCTAssertLessThanOrEqual(result.observations.count, 3)
    }

    func testMaxThreeWithAllNeutral() {
        let result = TodayStatusEngine.evaluate(
            input(mood: 3, energy: 3, pain: 3, sleepHours: 7)
        )
        XCTAssertEqual(result.observations.count, 3)
    }

    func testMaxThreeTruncates() {
        let result = TodayStatusEngine.evaluate(
            input(mood: 5, energy: 5, pain: 5, sleepHours: 4, steps: 8000)
        )
        XCTAssertEqual(result.observations.count, 3)
    }

    // MARK: - Perimenopause with other high-priority items

    func testPerimenopauseObservationPriority() {
        // Perimenopause observation should be added before tracker observation
        // but after mood/energy/pain/sleep/steps/exercise
        let result = TodayStatusEngine.evaluate(
            input(mood: 5, energy: 5, trackerKeys: ["hotFlashes", "cramps"], isPerimenopause: true)
        )
        // mood and energy take first two slots
        XCTAssertEqual(result.observations.count, 3)
        XCTAssertTrue(result.observations.contains(localizedMood(5)))
        XCTAssertTrue(result.observations.contains(localizedEnergy(5)))
        // Third slot should be perimenopause observation (hotFlashes present)
        XCTAssertTrue(result.observations.contains(perimenopauseHotFlashString))
    }
}