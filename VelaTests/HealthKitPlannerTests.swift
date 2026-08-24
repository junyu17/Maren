import Foundation
import HealthKit
import XCTest
@testable import Vela

private actor PeriodRevisionRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] { values }
}

/// Deterministic, Foundation-only coverage for the HealthKit planning helpers.
/// These tests never request HealthKit authorization or touch a HealthStore.
final class HealthKitPlannerTests: XCTestCase {

    private func calendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(
        _ calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    private func interval(
        base: Date,
        startHours: Double,
        endHours: Double
    ) -> HealthKitPlanners.Interval {
        HealthKitPlanners.Interval(
            start: base.addingTimeInterval(startHours * 3_600),
            end: base.addingTimeInterval(endHours * 3_600)
        )
    }

    func testSelectionMigrationLegacyEnabledUsesMenstrualOnly() {
        let supported: Set<String> = ["menstrualFlow", "bodyMass", "sleepAnalysis"]

        let migrated = HealthKitPlanners.selectionMigration(
            saved: nil,
            oldSyncEnabled: true,
            menstrualIdentifier: "menstrualFlow",
            supported: supported
        )

        XCTAssertEqual(migrated, ["menstrualFlow"])
    }

    func testSelectionMigrationLegacyDisabledIsEmpty() {
        let migrated = HealthKitPlanners.selectionMigration(
            saved: nil,
            oldSyncEnabled: false,
            menstrualIdentifier: "menstrualFlow",
            supported: ["menstrualFlow", "bodyMass"]
        )

        XCTAssertTrue(migrated.isEmpty)
    }

    func testSelectionMigrationExplicitFalseWinsAndUnsupportedIsFiltered() {
        let supported: Set<String> = ["menstrualFlow", "bodyMass"]

        let allFalse = HealthKitPlanners.selectionMigration(
            saved: ["menstrualFlow": false, "bodyMass": false],
            oldSyncEnabled: true,
            menstrualIdentifier: "menstrualFlow",
            supported: supported
        )
        XCTAssertTrue(allFalse.isEmpty)

        let filtered = HealthKitPlanners.selectionMigration(
            saved: [
                "menstrualFlow": true,
                "bodyMass": false,
                "futureType": true
            ],
            oldSyncEnabled: false,
            menstrualIdentifier: "menstrualFlow",
            supported: supported
        )
        XCTAssertEqual(filtered, ["menstrualFlow"])
    }

    func testSelectionMigrationIncludesNewReadOnlyTypes() {
        let supported: Set<String> = [
            HealthKitBridge.SyncType.menstrualFlow.rawValue,
            HealthKitBridge.SyncType.stepCount.rawValue,
            HealthKitBridge.SyncType.appleExerciseTime.rawValue
        ]

        let migrated = HealthKitPlanners.selectionMigration(
            saved: [
                HealthKitBridge.SyncType.menstrualFlow.rawValue: false,
                HealthKitBridge.SyncType.stepCount.rawValue: true,
                HealthKitBridge.SyncType.appleExerciseTime.rawValue: true
            ],
            oldSyncEnabled: true,
            menstrualIdentifier: HealthKitBridge.SyncType.menstrualFlow.rawValue,
            supported: supported
        )

        XCTAssertEqual(migrated, [
            HealthKitBridge.SyncType.stepCount.rawValue,
            HealthKitBridge.SyncType.appleExerciseTime.rawValue
        ])
    }

    func testStepAndExerciseTypesAreReadOnlyQuantityTypes() {
        let readOnlyTypes: Set<HealthKitBridge.SyncType> = [.stepCount, .appleExerciseTime]

        for type in readOnlyTypes {
            XCTAssertFalse(type.isWritable, "\(type) must never be written to HealthKit")
            XCTAssertTrue(type.objectType is HKQuantityType)
            XCTAssertTrue(type.sampleType is HKQuantityType)
            XCTAssertFalse(HealthKitBridge.SyncType.allCases.filter(\.isWritable).contains(type))
            XCTAssertFalse(type.title.isEmpty)
        }
    }

    func testHealthTypeTitlesAndListSeparatorsFollowLocale() throws {
        let types: [HealthKitBridge.SyncType] = [.menstrualFlow, .stepCount, .appleExerciseTime]
        let currentTitles = types.map(\.title)
        let currentSeparator = Locale.current.language.languageCode?.identifier == "zh" ? "、" : ", "

        XCTAssertEqual(
            HealthKitBridge.SyncType.localizedTitleList(for: types),
            currentTitles.joined(separator: currentSeparator)
        )

        let zhPath = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let zhBundle = try XCTUnwrap(Bundle(path: zhPath))
        let chineseTitles = ["经期流量", "步数", "锻炼时间"].map {
            zhBundle.localizedString(forKey: $0, value: nil, table: "Localizable")
        }
        XCTAssertEqual(
            HealthKitBridge.SyncType.titleList(
                chineseTitles,
                locale: Locale(identifier: "zh-Hans")
            ),
            "经期流量、步数、锻炼时间"
        )
    }

    func testPeriodRevisionPlanRunsDeleteAndWritesAsOneNonInterleavedBatch() async throws {
        let calendar = calendar(timeZone: "UTC")
        let deleteDate = date(calendar, year: 2026, month: 2, day: 1)
        let firstWrite = HealthKitBridge.PeriodWriteSnapshot(
            date: date(calendar, year: 2026, month: 2, day: 2),
            flowRaw: FlowLevel.light.rawValue,
            isCycleStart: true
        )
        let secondWrite = HealthKitBridge.PeriodWriteSnapshot(
            date: date(calendar, year: 2026, month: 2, day: 3),
            flowRaw: FlowLevel.medium.rawValue,
            isCycleStart: false
        )
        let plan = HealthKitBridge.makePeriodRevisionPlan(
            deleteDate: deleteDate,
            writes: [firstWrite, secondWrite]
        )
        XCTAssertEqual(
            plan.operations,
            [.delete(deleteDate), .write(firstWrite), .write(secondWrite)]
        )

        let recorder = PeriodRevisionRecorder()
        func run(_ batch: String) -> Task<Void, Error> {
            Task {
                try await HealthKitBridge._runPeriodRevisionPlanForTesting(plan) { operation in
                    let label: String
                    switch operation {
                    case .delete: label = "delete"
                    case .write(let snapshot): label = "write-\(snapshot.flowRaw)"
                    }
                    await recorder.append("\(batch):\(label)")
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
        }

        let first = run("A")
        let second = run("B")
        try await first.value
        try await second.value

        let events = await recorder.snapshot()
        XCTAssertEqual(events.count, 6)
        XCTAssertEqual(Set(events.map { String($0.prefix(1)) }), Set(["A", "B"]))
        let firstBatch = String(events[0].prefix(1))
        XCTAssertTrue(events.prefix(3).allSatisfy { String($0.prefix(1)) == firstBatch })
        XCTAssertTrue(events.suffix(3).allSatisfy { String($0.prefix(1)) != firstBatch })
    }

    func testFieldKeysIncludeCanonicalStepAndExerciseFields() {
        XCTAssertTrue(HealthKitPlanners.FieldKey.allCases.contains(.steps))
        XCTAssertTrue(HealthKitPlanners.FieldKey.allCases.contains(.exercise))
        XCTAssertEqual(HealthKitPlanners.FieldKey.steps.rawValue, "steps")
        XCTAssertEqual(HealthKitPlanners.FieldKey.exercise.rawValue, "exercise")
    }

    func testDayKeyUsesSuppliedTimezone() {
        let utc = calendar(timeZone: "UTC")
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let instant = date(utc, year: 2026, month: 1, day: 1, hour: 0, minute: 30)

        XCTAssertEqual(HealthKitPlanners.dayKey(for: instant, calendar: utc), 20260101)
        XCTAssertEqual(HealthKitPlanners.dayKey(for: instant, calendar: losAngeles), 20251231)
    }

    func testDailyRangesRespectCalendarDaysAndSpringDST() {
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let start = date(losAngeles, year: 2026, month: 3, day: 7)
        let end = date(losAngeles, year: 2026, month: 3, day: 10)

        let ranges = HealthKitPlanners.dailyRanges(from: start, to: end, calendar: losAngeles)

        XCTAssertEqual(ranges.map { HealthKitPlanners.dayKey(for: $0.start, calendar: losAngeles) },
                       [20260307, 20260308, 20260309])
        XCTAssertEqual(ranges.map { $0.end.timeIntervalSince($0.start) / 3_600 },
                       [24.0, 23.0, 24.0])
    }

    func testDailyRangeAnchorsAtLocalStartOfDay() {
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let dateInDay = date(losAngeles, year: 2026, month: 3, day: 8, hour: 12)
        let range = HealthKitPlanners.dailyRange(for: dateInDay, calendar: losAngeles)

        XCTAssertEqual(HealthKitPlanners.dayKey(for: range.start, calendar: losAngeles), 20260308)
        XCTAssertEqual(range.start, date(losAngeles, year: 2026, month: 3, day: 8))
        XCTAssertEqual(range.end, date(losAngeles, year: 2026, month: 3, day: 9))
        XCTAssertEqual(range.end.timeIntervalSince(range.start), 23 * 3_600)
    }

    func testDailyRangesRespectCalendarDaysAndFallDST() {
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let start = date(losAngeles, year: 2026, month: 10, day: 31)
        let end = date(losAngeles, year: 2026, month: 11, day: 3)

        let ranges = HealthKitPlanners.dailyRanges(from: start, to: end, calendar: losAngeles)

        XCTAssertEqual(ranges.map { HealthKitPlanners.dayKey(for: $0.start, calendar: losAngeles) },
                       [20261031, 20261101, 20261102])
        XCTAssertEqual(ranges.map { $0.end.timeIntervalSince($0.start) / 3_600 },
                       [24.0, 25.0, 24.0])
    }

    func testUnionSleepIntervalsMergesOverlapAndAdjacentAndFiltersInvalid() {
        let base = date(calendar(timeZone: "UTC"), year: 2026, month: 1, day: 1)
        let intervals = [
            interval(base: base, startHours: 4, endHours: 6),
            interval(base: base, startHours: 1, endHours: 4),
            interval(base: base, startHours: 0, endHours: 2),
            interval(base: base, startHours: 8, endHours: 9),
            interval(base: base, startHours: 7, endHours: 6),
            interval(base: base, startHours: 9, endHours: 9),
            HealthKitPlanners.Interval(
                start: Date(timeIntervalSinceReferenceDate: .infinity),
                end: Date(timeIntervalSinceReferenceDate: .infinity + 1)
            )
        ]

        let merged = HealthKitPlanners.unionSleepIntervals(intervals)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start, base)
        XCTAssertEqual(merged[0].end, base.addingTimeInterval(6 * 3_600))
        XCTAssertEqual(merged[1].start, base.addingTimeInterval(8 * 3_600))
        XCTAssertEqual(merged[1].end, base.addingTimeInterval(9 * 3_600))
    }

    func testSplitSleepIntervalsAcrossMidnight() {
        let utc = calendar(timeZone: "UTC")
        let start = date(utc, year: 2026, month: 1, day: 1, hour: 23)
        let end = date(utc, year: 2026, month: 1, day: 2, hour: 2)

        let split = HealthKitPlanners.splitSleepIntervalsByDay(
            [HealthKitPlanners.Interval(start: start, end: end)],
            calendar: utc
        )

        XCTAssertEqual(split[20260101]!, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(split[20260102]!, 2.0, accuracy: 0.000_001)
    }

    func testSpringForwardFullLocalDayUses23ActualHours() {
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let start = date(losAngeles, year: 2026, month: 3, day: 8)
        let end = losAngeles.date(byAdding: .day, value: 1, to: start)!

        let split = HealthKitPlanners.splitSleepIntervalsByDay(
            [HealthKitPlanners.Interval(start: start, end: end)],
            calendar: losAngeles
        )

        XCTAssertEqual(split[20260308]!, 23.0, accuracy: 0.000_001)
    }

    func testFallBackFullLocalDayIsCappedAt24Hours() {
        let losAngeles = calendar(timeZone: "America/Los_Angeles")
        let start = date(losAngeles, year: 2026, month: 11, day: 1)
        let end = losAngeles.date(byAdding: .day, value: 1, to: start)!

        let split = HealthKitPlanners.splitSleepIntervalsByDay(
            [HealthKitPlanners.Interval(start: start, end: end)],
            calendar: losAngeles
        )

        XCTAssertEqual(split[20261101]!, 24.0, accuracy: 0.000_001)
    }

    func testLatestValidValuesExcludesOwnSourceRejectsInvalidAndUsesLatest() {
        let utc = calendar(timeZone: "UTC")
        let firstDay = date(utc, year: 2026, month: 2, day: 10)
        let secondDay = date(utc, year: 2026, month: 2, day: 11)
        let samples = [
            HealthKitPlanners.DatedValue(
                date: firstDay.addingTimeInterval(1 * 3_600), value: 60, sourceIdentifier: "other"
            ),
            HealthKitPlanners.DatedValue(
                date: firstDay.addingTimeInterval(3 * 3_600), value: 62, sourceIdentifier: "other"
            ),
            HealthKitPlanners.DatedValue(
                date: firstDay.addingTimeInterval(4 * 3_600), value: 80, sourceIdentifier: "Maren"
            ),
            HealthKitPlanners.DatedValue(
                date: firstDay.addingTimeInterval(5 * 3_600), value: 10, sourceIdentifier: "other"
            ),
            HealthKitPlanners.DatedValue(
                date: firstDay.addingTimeInterval(6 * 3_600), value: .nan, sourceIdentifier: "other"
            ),
            HealthKitPlanners.DatedValue(
                date: secondDay.addingTimeInterval(2 * 3_600), value: 70, sourceIdentifier: "other"
            )
        ]

        let latest = HealthKitPlanners.latestValidValuesByDay(
            samples,
            calendar: utc,
            excludingSourceIdentifier: "Maren",
            isValid: { HealthKitPlanners.isValidWeight($0) }
        )

        XCTAssertEqual(latest[20260210], 62)
        XCTAssertEqual(latest[20260211], 70)
        XCTAssertEqual(latest.count, 2)
    }

    func testValidatorsEnforceFiniteRanges() {
        XCTAssertTrue(HealthKitPlanners.isValidWeight(20))
        XCTAssertTrue(HealthKitPlanners.isValidWeight(400))
        XCTAssertFalse(HealthKitPlanners.isValidWeight(19.999))
        XCTAssertFalse(HealthKitPlanners.isValidWeight(400.001))
        XCTAssertFalse(HealthKitPlanners.isValidWeight(.nan))
        XCTAssertFalse(HealthKitPlanners.isValidWeight(.infinity))

        XCTAssertTrue(HealthKitPlanners.isValidBasalBodyTemperature(33))
        XCTAssertTrue(HealthKitPlanners.isValidBasalBodyTemperature(43))
        XCTAssertFalse(HealthKitPlanners.isValidBasalBodyTemperature(32.999))
        XCTAssertFalse(HealthKitPlanners.isValidBasalBodyTemperature(43.001))
        XCTAssertFalse(HealthKitPlanners.isValidBasalBodyTemperature(.nan))

        XCTAssertFalse(HealthKitPlanners.isValidSleepHours(0))
        XCTAssertTrue(HealthKitPlanners.isValidSleepHours(0.001))
        XCTAssertTrue(HealthKitPlanners.isValidSleepHours(24))
        XCTAssertFalse(HealthKitPlanners.isValidSleepHours(24.001))
        XCTAssertFalse(HealthKitPlanners.isValidSleepHours(.infinity))

        XCTAssertTrue(HealthKitPlanners.isValidSteps(0))
        XCTAssertTrue(HealthKitPlanners.isValidSteps(200_000))
        XCTAssertFalse(HealthKitPlanners.isValidSteps(-1))
        XCTAssertFalse(HealthKitPlanners.isValidSteps(200_001))
        XCTAssertEqual(HealthKitPlanners.normalizedSteps(0), 0)
        XCTAssertEqual(HealthKitPlanners.normalizedSteps(200_000), 200_000)
        XCTAssertEqual(HealthKitPlanners.normalizedSteps(12.6), 13)
        XCTAssertNil(HealthKitPlanners.normalizedSteps(-0.1))
        XCTAssertNil(HealthKitPlanners.normalizedSteps(200_000.1))
        XCTAssertNil(HealthKitPlanners.normalizedSteps(.nan))
        XCTAssertNil(HealthKitPlanners.normalizedSteps(.infinity))

        XCTAssertTrue(HealthKitPlanners.isValidExerciseMinutes(0))
        XCTAssertTrue(HealthKitPlanners.isValidExerciseMinutes(1_440))
        XCTAssertFalse(HealthKitPlanners.isValidExerciseMinutes(-1))
        XCTAssertFalse(HealthKitPlanners.isValidExerciseMinutes(1_441))
        XCTAssertEqual(HealthKitPlanners.normalizedExerciseMinutes(0), 0)
        XCTAssertEqual(HealthKitPlanners.normalizedExerciseMinutes(1_440), 1_440)
        XCTAssertEqual(HealthKitPlanners.normalizedExerciseMinutes(12.6), 13)
        XCTAssertNil(HealthKitPlanners.normalizedExerciseMinutes(-0.1))
        XCTAssertNil(HealthKitPlanners.normalizedExerciseMinutes(1_440.1))
        XCTAssertNil(HealthKitPlanners.normalizedExerciseMinutes(.nan))
        XCTAssertNil(HealthKitPlanners.normalizedExerciseMinutes(.infinity))
    }

    func testShouldImportFieldDistinguishesUnrecordedImportedAndManual() {
        XCTAssertTrue(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: false,
            importedFields: [],
            field: .weight
        ))
        XCTAssertTrue(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: true,
            importedFields: [.weight],
            field: .weight
        ))
        XCTAssertFalse(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: true,
            importedFields: [],
            field: .weight
        ))
        XCTAssertFalse(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: true,
            importedFields: [.sleep],
            field: .weight
        ))
        XCTAssertTrue(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: false,
            importedFields: [],
            field: .steps
        ))
        XCTAssertTrue(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: true,
            importedFields: [.exercise],
            field: .exercise
        ))
        XCTAssertFalse(HealthKitPlanners.shouldImportField(
            localValueIsRecorded: true,
            importedFields: [],
            field: .steps
        ))
    }

    func testUpdatedImportedFieldsAddsAndRemovesMarkers() {
        let added = HealthKitPlanners.updatedImportedFields(
            existing: [.sleep],
            field: .weight,
            imported: true
        )
        XCTAssertEqual(added, [.sleep, .weight])

        let removed = HealthKitPlanners.updatedImportedFields(
            existing: added,
            field: .sleep,
            imported: false
        )
        XCTAssertEqual(removed, [.weight])
    }

    func testShouldImportPeriodDayAllowsUnknownAndImportedButNotManual() {
        XCTAssertTrue(HealthKitPlanners.shouldImportPeriodDay(existingImportedFromHealth: nil))
        XCTAssertTrue(HealthKitPlanners.shouldImportPeriodDay(existingImportedFromHealth: true))
        XCTAssertFalse(HealthKitPlanners.shouldImportPeriodDay(existingImportedFromHealth: false))
    }

    func testLookbackClampAndDateRange() {
        let utc = calendar(timeZone: "UTC")
        let now = date(utc, year: 2026, month: 4, day: 10, hour: 12, minute: 30)

        XCTAssertEqual(HealthKitPlanners.clampedLookbackDays(requested: -1), 1)
        XCTAssertEqual(HealthKitPlanners.clampedLookbackDays(requested: 0), 1)
        XCTAssertEqual(HealthKitPlanners.clampedLookbackDays(requested: 30), 30)
        XCTAssertEqual(HealthKitPlanners.clampedLookbackDays(requested: 999), 730)

        let range = HealthKitPlanners.importDateRange(
            now: now,
            requestedDays: 3,
            calendar: utc
        )
        XCTAssertEqual(range.start, date(utc, year: 2026, month: 4, day: 7, hour: 12, minute: 30))
        XCTAssertEqual(range.end, now)

        let clampedRange = HealthKitPlanners.importDateRange(
            now: now,
            requestedDays: 999,
            calendar: utc
        )
        XCTAssertEqual(
            clampedRange.start,
            utc.date(byAdding: .day, value: -730, to: now)
        )
    }

    func testCycleStartFlagsRecomputeConsecutiveRunsAndIgnoreDuplicateKeys() {
        let utc = calendar(timeZone: "UTC")

        let flags = HealthKitPlanners.cycleStartFlags(
            for: [20260104, 20260102, 20260103, 20260110, 20260110],
            calendar: utc
        )

        XCTAssertEqual(flags, [
            20260102: true,
            20260103: false,
            20260104: false,
            20260110: true
        ])
    }

    func testCycleStartFlagsHandlesLeapDayAndDSTUsingCalendarDays() {
        let losAngeles = calendar(timeZone: "America/Los_Angeles")

        let flags = HealthKitPlanners.cycleStartFlags(
            for: [20260228, 20260301, 20260308, 20260309],
            calendar: losAngeles
        )

        XCTAssertEqual(flags[20260228], true)
        XCTAssertEqual(flags[20260301], false)
        XCTAssertEqual(flags[20260308], true)
        XCTAssertEqual(flags[20260309], false)
    }

    func testPeriodDayKeysToResyncPromotesNextDayAfterDelete() {
        XCTAssertEqual(
            HealthKitPlanners.periodDayKeysToResync(
                afterChanging: 20260101,
                existingDayKeys: [20260102, 20260103, 20260120],
                deleting: true
            ),
            [20260102]
        )
        XCTAssertEqual(
            HealthKitPlanners.periodDayKeysToResync(
                afterChanging: 20260102,
                existingDayKeys: [20260101, 20260102, 20260103, 20260120],
                deleting: false
            ),
            [20260102, 20260103]
        )
    }

    func testPartialHealthCleanupResultRetainsSkippedAndFailedTypes() {
        let result = HealthKitBridge.DeleteAllResult(
            deleted: [.menstrualFlow],
            skipped: [.bodyMass],
            failed: [.init(type: .spotting, message: "test failure")]
        )

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.deleted, [.menstrualFlow])
        XCTAssertEqual(result.skipped, [.bodyMass])
        XCTAssertEqual(result.failed.map(\.type), [.spotting])
        XCTAssertTrue(result.userFacingIssueDescription.contains(HealthKitBridge.SyncType.bodyMass.title))
        XCTAssertTrue(result.userFacingIssueDescription.contains(HealthKitBridge.SyncType.spotting.title))
    }
}
