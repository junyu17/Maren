import XCTest
import SwiftData
@testable import Vela

final class MarenReviewEngineTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    private func dk(_ y: Int, _ m: Int, _ d: Int) -> Int {
        y * 10_000 + m * 100 + d
    }

    // MARK: - Weekly empty

    func testWeeklyEmpty() {
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: [])
        XCTAssertEqual(r.reviewStatus, .empty)
        XCTAssertTrue(r.currentWindow.recordedDayKeys.isEmpty)
        XCTAssertNil(r.averages.mood)
        XCTAssertNil(r.comparison)
        XCTAssertTrue(r.topTrackers.isEmpty)
    }

    // MARK: - Weekly limited

    func testWeeklyLimitedOneDay() {
        let log = DailyLog(date: date(2026,8,20), mood: .good)
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: [log])
        XCTAssertEqual(r.reviewStatus, .limited)
        XCTAssertEqual(r.currentWindow.recordedDayKeys.count, 1)
        XCTAssertNil(r.averages.mood)
    }

    func testWeeklyLimitedTwoDays() {
        let logs = [DailyLog(date: date(2026,8,19), mood: .good), DailyLog(date: date(2026,8,20), mood: .okay)]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertEqual(r.reviewStatus, .limited)
        XCTAssertNil(r.averages.mood)
    }

    // MARK: - Weekly ready

    func testWeeklyReady() {
        let logs = [
            DailyLog(date: date(2026,8,18), mood: .good, energy: 3, sleepHours: 7.0),
            DailyLog(date: date(2026,8,19), mood: .okay, energy: 4, sleepHours: 8.0),
            DailyLog(date: date(2026,8,20), mood: .great, energy: 5, sleepHours: 6.5),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertEqual(r.reviewStatus, .ready)
        XCTAssertNotNil(r.averages.mood)
        XCTAssertNotNil(r.averages.energy)
        XCTAssertNotNil(r.averages.sleep)
    }

    // MARK: - Exact 7-day boundaries

    func testWeeklyExactSevenDayBoundaries() {
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: [])
        XCTAssertEqual(r.currentWindow.startDayKey, dk(2026,8,14))
        XCTAssertEqual(r.currentWindow.endDayKey, dk(2026,8,20))
        XCTAssertEqual(r.previousWindow.startDayKey, dk(2026,8,7))
        XCTAssertEqual(r.previousWindow.endDayKey, dk(2026,8,13))
    }

    func testWeeklyAnchorClampedToToday() {
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2099,12,31), periodDays: [], logs: [])
        XCTAssertLessThanOrEqual(r.currentWindow.endDayKey, DayKey.today)
    }

    // MARK: - Duplicate day normalization

    func testDuplicateDayLatestWins() {
        let earlier = DailyLog(date: date(2026,8,20), mood: .good, energy: 2)
        let later = DailyLog(date: date(2026,8,20), mood: .great, energy: 5)
        earlier.updatedAt = Date(timeIntervalSince1970: 1000)
        later.updatedAt = Date(timeIntervalSince1970: 2000)
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: [earlier, later])
        XCTAssertEqual(r.currentWindow.recordedDayKeys.count, 1)
        // Only 1 recorded day → limited status → averages nil
        XCTAssertEqual(r.reviewStatus, .limited)
        XCTAssertNil(r.averages.mood)
        // But deduplication itself works correctly
        let deduped = MarenReviewEngine.deduplicateLogs([earlier, later])
        let log = deduped[dk(2026,8,20)]
        XCTAssertEqual(log?.moodRaw, 5) // .great = 5
        XCTAssertEqual(log?.energy, 5)
    }

    func testDuplicateDayMergesEachFieldWithLatestValidValue() throws {
        let older = DailyLog(date: date(2026, 8, 20), mood: .good, energy: 2,
                             sleepHours: 7, symptoms: ["older"])
        let middle = DailyLog(date: date(2026, 8, 20), mood: .great, energy: 5,
                              sleepHours: 8, symptoms: ["middle"])
        let newer = DailyLog(date: date(2026, 8, 20), energy: 9,
                             sleepHours: .nan, symptoms: ["newer"])
        older.updatedAt = Date(timeIntervalSince1970: 100)
        middle.updatedAt = Date(timeIntervalSince1970: 200)
        newer.updatedAt = Date(timeIntervalSince1970: 300)

        let log = try XCTUnwrap(MarenReviewEngine.deduplicateLogs([older, middle, newer])[dk(2026, 8, 20)])
        XCTAssertEqual(log.moodRaw, 5, "the newest valid mood must win")
        XCTAssertEqual(log.energy, 5, "an invalid newer energy must not erase a valid value")
        XCTAssertEqual(log.sleepHours, 8, "a non-finite newer sleep value must not erase a valid value")
        XCTAssertEqual(log.symptoms, Set(["older", "middle", "newer"]))
        XCTAssertEqual(log.updatedAt, Date(timeIntervalSince1970: 300))
    }

    func testDuplicateDayTrackerUnion() {
        let a = DailyLog(date: date(2026,8,20), symptoms: ["cramps","headache"])
        let b = DailyLog(date: date(2026,8,20), symptoms: ["headache","fatigue"])
        a.updatedAt = Date(timeIntervalSince1970: 1000)
        b.updatedAt = Date(timeIntervalSince1970: 2000)
        let deduped = MarenReviewEngine.deduplicateLogs([a, b])
        let log = deduped[dk(2026,8,20)]
        XCTAssertNotNil(log)
        XCTAssertEqual(log!.symptoms, Set(["cramps","headache","fatigue"]))
    }

    // MARK: - Future exclusion

    func testFutureLogsExcludedFromWindow() {
        let futureLog = DailyLog(date: date(2026,8,25), mood: .great)
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: [futureLog])
        XCTAssertTrue(r.currentWindow.recordedDayKeys.isEmpty)
    }

    // MARK: - Per-metric 3-sample thresholds

    func testMoodAverageRequiresThreeSamples() {
        let logs = [DailyLog(date: date(2026,8,18), mood: .good), DailyLog(date: date(2026,8,19), mood: .okay)]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertNil(r.averages.mood)
    }

    func testEnergyAverageExcludesZeroUnset() {
        let logs = [
            DailyLog(date: date(2026,8,18), energy: 3),
            DailyLog(date: date(2026,8,19), energy: 4),
            DailyLog(date: date(2026,8,20), energy: 0),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertNil(r.averages.energy)
    }

    func testEnergyAverageExcludesValuesAboveFive() {
        let rows = [
            MarenReviewEngine.DeduplicatedLog(dayKey: 1, moodRaw: 0, energy: 1,
                                               sleepHours: nil, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 2, moodRaw: 0, energy: 6,
                                               sleepHours: nil, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 3, moodRaw: 0, energy: 5,
                                               sleepHours: nil, symptoms: [], updatedAt: .now),
        ]
        XCTAssertNil(MarenReviewEngine.computeAverages(logs: rows).energy,
                     "the invalid value must not count toward the three-sample threshold")
    }

    func testSleepAverageWithNilValues() {
        let logs = [
            DailyLog(date: date(2026,8,18), sleepHours: 7.0),
            DailyLog(date: date(2026,8,19), sleepHours: nil),
            DailyLog(date: date(2026,8,20), sleepHours: 8.0),
            DailyLog(date: date(2026,8,21), sleepHours: 6.5),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,21), periodDays: [], logs: logs)
        XCTAssertNotNil(r.averages.sleep)
        XCTAssertEqual(r.averages.sleep!, 7.166666666666667, accuracy: 0.01)
    }

    func testSleepAverageExcludesNonFiniteAndOutOfRangeValues() {
        let rows = [
            MarenReviewEngine.DeduplicatedLog(dayKey: 1, moodRaw: 0, energy: 0,
                                               sleepHours: .nan, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 2, moodRaw: 0, energy: 0,
                                               sleepHours: .infinity, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 3, moodRaw: 0, energy: 0,
                                               sleepHours: -1, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 4, moodRaw: 0, energy: 0,
                                               sleepHours: 25, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 5, moodRaw: 0, energy: 0,
                                               sleepHours: 6, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 6, moodRaw: 0, energy: 0,
                                               sleepHours: 7, symptoms: [], updatedAt: .now),
            MarenReviewEngine.DeduplicatedLog(dayKey: 7, moodRaw: 0, energy: 0,
                                               sleepHours: 8, symptoms: [], updatedAt: .now),
        ]
        let sleepAverage = try! XCTUnwrap(MarenReviewEngine.computeAverages(logs: rows).sleep)
        XCTAssertEqual(sleepAverage, 7, accuracy: 0.001)
    }

    // MARK: - Comparison thresholds

    func testComparisonExactlyZeroPointThreeIsSimilar() {
        let cur = MarenReviewEngine.MetricAverages(mood: 3.0, energy: nil, sleep: nil)
        let prev = MarenReviewEngine.MetricAverages(mood: 2.7, energy: nil, sleep: nil)
        let c = try! XCTUnwrap(MarenReviewEngine.computeComparison(current: cur, previous: prev))
        XCTAssertEqual(c.moodDelta!, 0.3, accuracy: 0.001)
        XCTAssertTrue(c.moodSimilar)
    }

    func testComparisonAboveZeroPointThreeNotSimilar() {
        let cur = MarenReviewEngine.MetricAverages(mood: 3.1, energy: nil, sleep: nil)
        let prev = MarenReviewEngine.MetricAverages(mood: 2.7, energy: nil, sleep: nil)
        let c = try! XCTUnwrap(MarenReviewEngine.computeComparison(current: cur, previous: prev))
        XCTAssertFalse(c.moodSimilar)
    }

    func testComparisonSleepZeroPointThreeHoursIsSimilar() {
        let cur = MarenReviewEngine.MetricAverages(mood: nil, energy: nil, sleep: 7.5)
        let prev = MarenReviewEngine.MetricAverages(mood: nil, energy: nil, sleep: 7.2)
        let c = try! XCTUnwrap(MarenReviewEngine.computeComparison(current: cur, previous: prev))
        XCTAssertEqual(c.sleepDelta!, 0.3, accuracy: 0.001)
        XCTAssertTrue(c.sleepSimilar)
    }

    func testComparisonIsNilWhenAllMetricDeltasAreNil() {
        let current = MarenReviewEngine.MetricAverages(mood: nil, energy: nil, sleep: nil)
        let previous = MarenReviewEngine.MetricAverages(mood: nil, energy: nil, sleep: nil)
        XCTAssertNil(MarenReviewEngine.computeComparison(current: current, previous: previous))
    }

    func testComparisonRequiresBothWindowsRecordedDays() {
        let logs = [
            DailyLog(date: date(2026,8,18), mood: .good),
            DailyLog(date: date(2026,8,19), mood: .okay),
            DailyLog(date: date(2026,8,20), mood: .great),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertNil(r.comparison)
    }

    // MARK: - Tracker ranking

    func testTrackerRankingRequiresMinimumRecordedDays() {
        let logs = [
            DailyLog(date: date(2026,8,19), symptoms: ["cramps"]),
            DailyLog(date: date(2026,8,20), symptoms: ["cramps"]),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertTrue(r.topTrackers.isEmpty)
    }

    func testTrackerRankingRequiresTrackerOnAtLeastTwoDays() {
        let logs = [
            DailyLog(date: date(2026,8,18), symptoms: ["cramps"]),
            DailyLog(date: date(2026,8,19), symptoms: ["fatigue"]),
            DailyLog(date: date(2026,8,20), symptoms: ["cramps","fatigue"]),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        // cramps on 2 days, fatigue on 2 days → both appear
        XCTAssertEqual(r.topTrackers.count, 2)
    }

    func testTrackerRankingTopThreeTieByKey() {
        let logs = [
            DailyLog(date: date(2026,8,18), symptoms: ["a","b","c"]),
            DailyLog(date: date(2026,8,19), symptoms: ["a","b","c"]),
            DailyLog(date: date(2026,8,20), symptoms: ["a","b","c"]),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: [], logs: logs)
        XCTAssertEqual(r.topTrackers.count, 3)
        XCTAssertEqual(r.topTrackers[0].key, "a")
        XCTAssertEqual(r.topTrackers[1].key, "b")
        XCTAssertEqual(r.topTrackers[2].key, "c")
    }

    // MARK: - Completed cycle

    func testCompletedCycleAppearsOnlyAfterNextStart() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,1,3), flow: .light),
            PeriodDay(date: date(2026,1,29), flow: .medium),
            PeriodDay(date: date(2026,1,30), flow: .medium),
        ]
        let result = MarenReviewEngine.completedCycleSummary(periodDays: periods, logs: [], today: date(2026,2,15))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.startDayKey, dk(2026,1,1))
    }

    func testCompletedCycleStableIDIsStartDayKey() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,1,29), flow: .medium),
            PeriodDay(date: date(2026,1,30), flow: .medium),
        ]
        let result = MarenReviewEngine.completedCycleSummary(periodDays: periods, logs: [], today: date(2026,2,15))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.startDayKey, dk(2026,1,1))
    }

    func testCompletedCycleInclusiveExclusiveRange() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,1,29), flow: .medium),
            PeriodDay(date: date(2026,1,30), flow: .medium),
        ]
        let logs = [
            DailyLog(date: date(2026,1,5), mood: .good),
            DailyLog(date: date(2026,1,15), mood: .okay),
            DailyLog(date: date(2026,1,28), mood: .great),
        ]
        let result = MarenReviewEngine.completedCycleSummary(periodDays: periods, logs: logs, today: date(2026,2,15))
        XCTAssertNotNil(result)
        // All 3 logs in range [20260101, 20260129) → ready
        XCTAssertEqual(result!.reviewStatus, .ready)
    }

    func testCompletedCycleNoCurrentInProgress() {
        // Only one period span → no completed cycle
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
        ]
        let result = MarenReviewEngine.completedCycleSummary(periodDays: periods, logs: [], today: date(2026,1,10))
        XCTAssertNil(result)
    }

    func testCompletedCycleGapOver120Days() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,6,1), flow: .medium),  // 151 days later
            PeriodDay(date: date(2026,6,2), flow: .medium),
        ]
        let result = MarenReviewEngine.completedCycleSummary(periodDays: periods, logs: [], today: date(2026,6,15))
        // Latest completed cycle regardless of length; gapOver120 = true for >120 days
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.cycleLength, 151)
        XCTAssertTrue(result!.gapOver120)
        XCTAssertEqual(result!.recordedLogDays, 0)
    }

    // MARK: - Recorded-only history (manual settings ignored)

    func testCompletedCycleUsesRecordedOnly() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,1,29), flow: .medium),
            PeriodDay(date: date(2026,1,30), flow: .medium),
        ]
        // Recorded-only prediction is what the engine uses internally.
        let recorded = CyclePredictor.predict(from: periods, today: date(2026,2,15), manual: nil)
        let completed = recorded.cycles.filter { $0.length != nil }
        let result = MarenReviewEngine.completedCycleSummary(periodDays: periods, logs: [], today: date(2026,2,15))
        XCTAssertEqual(result?.startDayKey, MarenReviewEngine.dayKeyByAddingDays(0, to: dk(2026,1,1)))
        XCTAssertEqual(result?.cycleLength, completed.first?.length)
        // A manual cycle must NOT shift the recorded boundary.
        let manual = ManualCycle(enabled: true, cycleLength: 35, periodLength: 6)
        let recordedWithManual = CyclePredictor.predict(from: periods, today: date(2026,2,15), manual: manual)
        XCTAssertEqual(recordedWithManual.cycles.filter { $0.length != nil }.first?.length,
                       completed.first?.length,
                       "manual cycle must not affect recorded-only boundaries")
    }

    // MARK: - Selecting a specific cycle by start ID

    func testSelectSpecificCompletedCycleByStart() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,2,1), flow: .medium),
            PeriodDay(date: date(2026,2,2), flow: .medium),
            PeriodDay(date: date(2026,3,1), flow: .medium),
            PeriodDay(date: date(2026,3,2), flow: .medium),
        ]
        let result = MarenReviewEngine.completedCycleSummary(
            periodDays: periods, logs: [], cycleStartDayKey: dk(2026,2,1), today: date(2026,3,15))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.startDayKey, dk(2026,2,1))
        XCTAssertEqual(result?.cycleLength, 28)
    }

    func testSpecificCycleDisappearsAfterBoundaryDeletion() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,2,1), flow: .medium),
            PeriodDay(date: date(2026,2,2), flow: .medium),
            PeriodDay(date: date(2026,3,1), flow: .medium),
            PeriodDay(date: date(2026,3,2), flow: .medium),
        ]
        let before = MarenReviewEngine.completedCycleSummary(
            periodDays: periods, logs: [], cycleStartDayKey: dk(2026,2,1), today: date(2026,3,15))
        XCTAssertNotNil(before)

        // Delete the Feb boundary (e.g. user removed that period record).
        let remaining = periods.filter { $0.dayKey < dk(2026,2,1) || $0.dayKey >= dk(2026,3,1) }
        let after = MarenReviewEngine.completedCycleSummary(
            periodDays: remaining, logs: [], cycleStartDayKey: dk(2026,2,1), today: date(2026,3,15))
        XCTAssertNil(after, "selecting a deleted boundary must return nil, not a different cycle")
    }

    // MARK: - Over-120-day cycle has exact recordedLogDays

    func testCompletedCycleOver120ExactRecordedLogDays() {
        let periods = [
            PeriodDay(date: date(2026,1,1), flow: .medium),
            PeriodDay(date: date(2026,1,2), flow: .medium),
            PeriodDay(date: date(2026,6,1), flow: .medium),
            PeriodDay(date: date(2026,6,2), flow: .medium),
        ]
        let logs = [
            DailyLog(date: date(2026,2,1), mood: .good),
            DailyLog(date: date(2026,4,1), mood: .okay),
        ]
        let result = MarenReviewEngine.completedCycleSummary(
            periodDays: periods, logs: logs, today: date(2026,6,15))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.cycleLength, 151)
        XCTAssertTrue(result!.gapOver120)
        XCTAssertEqual(result!.recordedLogDays, 2)
    }

    // MARK: - Access policy (compact presentation contract)

    func testCompactPresentationPolicy() {
        let free = MarenReviewEngine.accessPolicy(isPremium: false)
        let premium = MarenReviewEngine.accessPolicy(isPremium: true)

        // Free excludes premium metrics...
        XCTAssertFalse(free.contains(.averages))
        XCTAssertFalse(free.contains(.comparisons))
        XCTAssertFalse(free.contains(.topTrackers))
        // ...but includes the free cycle boundary.
        XCTAssertTrue(free.contains(.cycleBoundary))

        // Premium includes everything.
        XCTAssertTrue(premium.contains(.averages))
        XCTAssertTrue(premium.contains(.comparisons))
        XCTAssertTrue(premium.contains(.topTrackers))
        XCTAssertTrue(premium.contains(.cycleBoundary))
    }

    func testFreeAccessPolicy() {
        let p = MarenReviewEngine.accessPolicy(isPremium: false)
        XCTAssertTrue(p.contains(.dateRange))
        XCTAssertTrue(p.contains(.coverage))
        XCTAssertTrue(p.contains(.periodDayCount))
        XCTAssertTrue(p.contains(.cycleBoundary))
        XCTAssertTrue(p.contains(.premiumPreview))
        XCTAssertFalse(p.contains(.averages))
        XCTAssertFalse(p.contains(.comparisons))
        XCTAssertFalse(p.contains(.topTrackers))
    }

    func testPremiumAccessPolicy() {
        let p = MarenReviewEngine.accessPolicy(isPremium: true)
        XCTAssertTrue(p.contains(.dateRange))
        XCTAssertTrue(p.contains(.coverage))
        XCTAssertTrue(p.contains(.periodDayCount))
        XCTAssertTrue(p.contains(.averages))
        XCTAssertTrue(p.contains(.comparisons))
        XCTAssertTrue(p.contains(.topTrackers))
        XCTAssertTrue(p.contains(.cycleHistory))
        XCTAssertFalse(p.contains(.premiumPreview))
    }

    // MARK: - Period days in window

    func testPeriodDaysCountedInCurrentWindow() {
        let periods = [
            PeriodDay(date: date(2026,8,18), flow: .medium),
            PeriodDay(date: date(2026,8,19), flow: .light),
            PeriodDay(date: date(2026,8,10), flow: .heavy),
        ]
        let r = MarenReviewEngine.weeklyReview(anchorDayKey: dk(2026,8,20), periodDays: periods, logs: [])
        // Aug 18, 19 are in current window (Aug 14-20); Aug 10 is in previous
        XCTAssertEqual(r.periodDayCount, 2)
    }

    // MARK: - dayKey arithmetic

    func testDayKeyByAddingDays() {
        let result = MarenReviewEngine.dayKeyByAddingDays(1, to: dk(2026,1,31))
        XCTAssertEqual(result, dk(2026,2,1))
    }

    func testDayKeyByAddingNegativeDays() {
        let result = MarenReviewEngine.dayKeyByAddingDays(-1, to: dk(2026,3,1))
        XCTAssertEqual(result, dk(2026,2,28))
    }

    // MARK: - Deduplication period days

    func testDeduplicatePeriodsLatestWins() {
        let a = PeriodDay(date: date(2026,8,20), flow: .light)
        let b = PeriodDay(date: date(2026,8,20), flow: .heavy)
        a.updatedAt = Date(timeIntervalSince1970: 1000)
        b.updatedAt = Date(timeIntervalSince1970: 2000)
        let deduped = MarenReviewEngine.deduplicatePeriods([a, b])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped[dk(2026,8,20)]?.flow, .heavy)
    }

    // MARK: - Calendar recency across boundaries

    func testCalendarDaysBetweenAcrossMonthBoundary() {
        let a = date(2025,12,31)
        let b = date(2026,1,2)
        XCTAssertEqual(MarenReviewEngine.calendarDaysBetween(a, b), 2)
    }

    func testCalendarDaysBetweenAcrossYearBoundary() {
        let a = date(2026,2,27)
        let b = date(2026,3,1) // 2026 is not a leap year
        XCTAssertEqual(MarenReviewEngine.calendarDaysBetween(a, b), 2)
    }
}

/// Regression coverage for the bounded SwiftData queries used by the
/// performance-sensitive screens. These tests keep the window definition and
/// the all-history custom-tracker count semantics explicit.
final class HistoricalDataQueryTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    func testRecentDayKeyRangeIsInclusiveAndMatchesCycleLookback() {
        let anchor = date(2026, 8, 24)
        let range = HistoricalDataQuery.recentDayKeyRange(ending: anchor)
        let expectedStart = cal.date(byAdding: .day, value: -HistoricalDataQuery.lookbackDays, to: anchor)!

        XCTAssertEqual(range.upperBound, DayKey.from(anchor))
        XCTAssertEqual(range.lowerBound, DayKey.from(expectedStart))
        XCTAssertTrue(range.contains(DayKey.from(anchor)))
        XCTAssertTrue(range.contains(DayKey.from(expectedStart)))
    }

    @MainActor
    func testDayKeyPredicateSelectsOnlyRecentRows() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DailyLog.self, configurations: configuration)
        let context = container.mainContext
        let anchor = date(2026, 8, 24)
        let range = HistoricalDataQuery.recentDayKeyRange(ending: anchor)

        context.insert(DailyLog(date: date(2022, 1, 1)))
        context.insert(DailyLog(date: date(2026, 8, 20)))
        context.insert(DailyLog(date: date(2026, 8, 25)))
        try context.save()

        let matches = try context.fetch(FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { log in
                log.dayKey >= range.lowerBound && log.dayKey <= range.upperBound
            }
        ))

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.dayKey, 20260820)
    }
}
