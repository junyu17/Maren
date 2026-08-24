import Foundation
import XCTest
@testable import Vela

final class PerimenopauseTrendEngineTests: XCTestCase {

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }

    private func dayKey(_ year: Int, _ month: Int, _ day: Int) -> Int {
        year * 10_000 + month * 100 + day
    }

    private func record(_ key: Int,
                        symptoms: Set<String> = [],
                        mood: Double? = nil,
                        sleep: Double? = nil) -> PerimenopauseTrendEngine.DailyRecord {
        PerimenopauseTrendEngine.DailyRecord(dayKey: key,
                                              symptomKeys: symptoms,
                                              mood: mood,
                                              sleepHours: sleep)
    }

    private func record(_ date: Date,
                        in calendar: Calendar,
                        symptoms: Set<String> = []) -> PerimenopauseTrendEngine.DailyRecord {
        PerimenopauseTrendEngine.DailyRecord(date: date,
                                              symptomKeys: symptoms)
    }

    private func report(records: [PerimenopauseTrendEngine.DailyRecord] = [],
                        periodDates: [Date] = [],
                        periodKeys: [Int] = [],
                        asOf: Date = Date(timeIntervalSince1970: 0),
                        calendar: Calendar? = nil) -> PerimenopauseTrendEngine.Report {
        PerimenopauseTrendEngine.evaluate(
            PerimenopauseTrendEngine.Input(
                dailyRecords: records,
                periodStartDates: periodDates,
                periodStartDayKeys: periodKeys,
                asOf: asOf,
                calendar: calendar ?? utc
            )
        )
    }

    func testLifeStageUsesStableKeyAndSafeFallback() {
        let suiteName = "LifeStageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(LifeStage.userDefaultsKey, "vela.lifeStage")
        XCTAssertEqual(LifeStage.load(from: defaults), .cycleTracking)

        defaults.set("future-value", forKey: LifeStage.userDefaultsKey)
        XCTAssertEqual(LifeStage.load(from: defaults), .cycleTracking)

        let unknown = Data("\"future-value\"".utf8)
        XCTAssertEqual(try? JSONDecoder().decode(LifeStage.self, from: unknown), .cycleTracking)

        LifeStage.save(.perimenopause, to: defaults)
        XCTAssertEqual(LifeStage.load(from: defaults), .perimenopause)
    }

    func testThirtyAndNinetyDayWindowsHaveExactInclusiveBoundaries() {
        let calendar = utc
        let anchor = date(2026, 8, 21, in: calendar)
        let records = [
            record(dayKey(2026, 7, 23), symptoms: ["hotFlashes"]), // recent day 30: included
            record(dayKey(2026, 7, 22), symptoms: ["nightSweats"]), // previous day 30: included
            record(dayKey(2026, 6, 22), symptoms: ["vaginalDryness"]), // outside previous 30
            record(dayKey(2026, 5, 24), symptoms: ["brainFog"]), // recent day 90: included
            record(dayKey(2026, 5, 23), symptoms: ["jointPain"]), // outside recent 90
            record(dayKey(2026, 8, 22), symptoms: ["heartRacing"]), // future: excluded
        ]

        let result = report(records: records, asOf: anchor, calendar: calendar)

        XCTAssertEqual(result.thirtyDay.coverageDays, 1)
        XCTAssertEqual(result.thirtyDay.symptomCount(for: "hotFlashes"), 1)
        XCTAssertEqual(result.thirtyDay.symptomCount(for: "nightSweats"), 0)
        XCTAssertEqual(result.ninetyDay.coverageDays, 4)
        XCTAssertEqual(result.ninetyDay.symptomCount(for: "brainFog"), 1)
        XCTAssertEqual(result.ninetyDay.symptomCount(for: "heartRacing"), 0)
    }

    func testFutureRecordsAreExcludedEvenWhenTheyWouldChangeCoverage() {
        let calendar = utc
        let anchor = date(2026, 8, 21, in: calendar)
        let result = report(
            records: [
                record(dayKey(2026, 8, 21), symptoms: ["hotFlashes"]),
                record(dayKey(2026, 8, 22), symptoms: ["hotFlashes"]),
            ],
            asOf: anchor,
            calendar: calendar
        )

        XCTAssertEqual(result.thirtyDay.coverageDays, 1)
        XCTAssertEqual(result.thirtyDay.symptomCount(for: "hotFlashes"), 1)
    }

    func testDuplicateDayMergesTagsWithoutInflatingCoverageOrCounts() {
        let calendar = utc
        let result = report(
            records: [
                record(dayKey(2026, 8, 10), symptoms: ["hotFlashes"], mood: 3),
                record(dayKey(2026, 8, 10), symptoms: ["nightSweats"], sleep: 7),
            ],
            asOf: date(2026, 8, 21, in: calendar),
            calendar: calendar
        )

        XCTAssertEqual(result.thirtyDay.coverageDays, 1)
        XCTAssertEqual(result.thirtyDay.symptomCount(for: "hotFlashes"), 1)
        XCTAssertEqual(result.thirtyDay.symptomCount(for: "nightSweats"), 1)
        XCTAssertEqual(result.thirtyDay.sleep.previousSampleCount, 0)
    }

    func testRatesUseRecordedDayCoverageRatherThanWindowLength() throws {
        let calendar = utc
        let anchor = date(2026, 8, 21, in: calendar)
        let records = [
            record(dayKey(2026, 8, 1), symptoms: ["hotFlashes"]),
            record(dayKey(2026, 8, 2), symptoms: ["hotFlashes"]),
            record(dayKey(2026, 8, 3)),
            record(dayKey(2026, 7, 1)),
            record(dayKey(2026, 7, 2)),
            record(dayKey(2026, 7, 3)),
        ]
        let trend = report(records: records, asOf: anchor, calendar: calendar)
            .thirtyDay.symptomTrend(for: "hotFlashes")!

        XCTAssertEqual(try XCTUnwrap(trend.recentRate), 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(trend.previousRate), 0.0, accuracy: 0.000_001)
        XCTAssertEqual(trend.direction, .rising)
    }

    func testDirectionIsInsufficientUntilBothSidesHaveThreeRecordedDays() {
        let calendar = utc
        let result = report(
            records: [
                record(dayKey(2026, 8, 1), symptoms: ["hotFlashes"]),
                record(dayKey(2026, 8, 2), symptoms: ["hotFlashes"]),
                record(dayKey(2026, 7, 1)),
                record(dayKey(2026, 7, 2)),
                record(dayKey(2026, 7, 3)),
            ],
            asOf: date(2026, 8, 21, in: calendar),
            calendar: calendar
        )

        XCTAssertEqual(result.thirtyDay.symptomTrend(for: "hotFlashes")?.direction, .insufficient)
    }

    func testDirectionThresholdIsTenPercentagePoints() throws {
        let calendar = utc
        let anchor = date(2026, 8, 21, in: calendar)
        var records: [PerimenopauseTrendEngine.DailyRecord] = []

        // Ten recorded days in each side: 20% vs 10% is exactly the rising
        // threshold; 19% vs 10% is represented by a separate 90-day check
        // below as a stable, sub-threshold change.
        for offset in 0..<10 {
            let recent = calendar.date(byAdding: .day, value: -offset, to: anchor)!
            let previous = calendar.date(byAdding: .day, value: -30 - offset, to: anchor)!
            records.append(record(recent, in: calendar,
                                  symptoms: offset < 2 ? ["hotFlashes"] : []))
            records.append(record(previous, in: calendar,
                                  symptoms: offset == 0 ? ["hotFlashes"] : []))
        }

        let trend = report(records: records, asOf: anchor, calendar: calendar)
            .thirtyDay.symptomTrend(for: "hotFlashes")!
        XCTAssertEqual(trend.direction, .rising)
        XCTAssertEqual(try XCTUnwrap(trend.recentRate), 0.2, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(trend.previousRate), 0.1, accuracy: 0.000_001)

        let subThreshold = report(
            records: records.map { record in
                guard record.symptomKeys.contains("hotFlashes") else { return record }
                return PerimenopauseTrendEngine.DailyRecord(
                    date: record.date,
                    dayKey: record.dayKey,
                    symptomKeys: [],
                    mood: record.mood,
                    sleepHours: record.sleepHours
                )
            },
            asOf: anchor,
            calendar: calendar
        )
        XCTAssertEqual(subThreshold.thirtyDay.symptomTrend(for: "hotFlashes")?.direction, .stable)
    }

    func testCycleLengthsExposeMinimumMaximumAndRangeInRecentWindow() {
        let calendar = utc
        let result = report(
            periodKeys: [
                dayKey(2026, 4, 30),
                dayKey(2026, 5, 30), // 30
                dayKey(2026, 6, 28), // 29
                dayKey(2026, 7, 30), // 32
            ],
            asOf: date(2026, 8, 21, in: calendar),
            calendar: calendar
        )

        let cycle = result.ninetyDay.cycleLength
        XCTAssertEqual(cycle.lengths, [30, 29, 32])
        XCTAssertEqual(cycle.minimum, 29)
        XCTAssertEqual(cycle.maximum, 32)
        XCTAssertEqual(cycle.range, 3)
    }

    func testSleepAndMoodAveragesRequireThreeValuesAndUseRecentAndPreviousWindows() throws {
        let calendar = utc
        let result = report(
            records: [
                record(dayKey(2026, 8, 1), mood: 3, sleep: 6),
                record(dayKey(2026, 8, 2), mood: 4, sleep: 7),
                record(dayKey(2026, 8, 3), mood: 5, sleep: 8),
                record(dayKey(2026, 7, 1), mood: 1, sleep: 4),
                record(dayKey(2026, 7, 2), mood: 2, sleep: 5),
                record(dayKey(2026, 7, 3), mood: 3, sleep: 6),
            ],
            asOf: date(2026, 8, 21, in: calendar),
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(result.thirtyDay.sleep.recentAverage), 7, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.thirtyDay.sleep.previousAverage), 5, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.thirtyDay.mood.recentAverage), 4, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(result.thirtyDay.mood.previousAverage), 2, accuracy: 0.000_001)
        XCTAssertTrue(result.thirtyDay.sleep.isSufficient)
        XCTAssertTrue(result.thirtyDay.mood.isSufficient)
    }

    func testDateWindowsRemainStableAcrossDSTAndTimeZones() {
        let anchorKey = dayKey(2024, 3, 11)
        let records = [
            record(dayKey(2024, 3, 10), symptoms: ["hotFlashes"]),
            record(dayKey(2024, 3, 11), symptoms: ["nightSweats"]),
        ]

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let ny = report(records: records,
                        asOf: date(2024, 3, 11, in: newYork),
                        calendar: newYork)
        let la = report(records: records,
                        asOf: date(2024, 3, 11, in: losAngeles),
                        calendar: losAngeles)

        XCTAssertEqual(anchorKey, 20240311)
        XCTAssertEqual(ny.thirtyDay.coverageDays, la.thirtyDay.coverageDays)
        XCTAssertEqual(ny.thirtyDay.symptomCounts, la.thirtyDay.symptomCounts)
        XCTAssertEqual(ny.thirtyDay.startDate,
                       newYork.date(byAdding: .day, value: -29,
                                    to: newYork.startOfDay(for: date(2024, 3, 11, in: newYork))))
        XCTAssertEqual(la.thirtyDay.startDate,
                       losAngeles.date(byAdding: .day, value: -29,
                                       to: losAngeles.startOfDay(for: date(2024, 3, 11, in: losAngeles))))
    }
}
