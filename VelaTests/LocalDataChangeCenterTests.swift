import XCTest
import SwiftData
@testable import Vela

@MainActor
final class LocalDataChangeCenterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LocalDataChangeCenter.shared._resetRevisionCounter()
    }

    // MARK: - Revision monotonicity

    func testRepeatedPostProducesDistinctRevisions() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .dailyLogDeleted, affectedDayKeys: [20260101])
        let first = center.lastEvent!.revision
        center.post(kind: .dailyLogDeleted, affectedDayKeys: [20260101])
        let second = center.lastEvent!.revision
        XCTAssertGreaterThan(second, first)
    }

    func testAllRevisionsAreDistinct() {
        let center = LocalDataChangeCenter.shared
        var revisions = Set<UInt64>()
        for _ in 0..<20 {
            center.post(kind: .quickLogApplied, affectedDayKeys: [20260101])
            revisions.insert(center.lastEvent!.revision)
        }
        XCTAssertEqual(revisions.count, 20)
    }

    // MARK: - Event affected-day matching

    func testEventCarriesAffectedDayKeys() {
        let center = LocalDataChangeCenter.shared
        let keys: Set<Int> = [20260101, 20260102, 20260103]
        center.post(kind: .backupImported, affectedDayKeys: keys)
        XCTAssertEqual(center.lastEvent?.affectedDayKeys, keys)
    }

    func testEventCarriesRemovedCustomTrackerKeys() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .customTrackerDeleted, removedCustomTrackerKeys: ["custom_headache"])
        XCTAssertEqual(center.lastEvent?.removedCustomTrackerKeys, ["custom_headache"])
    }

    func testEventKindIsCorrect() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .storeReset)
        XCTAssertEqual(center.lastEvent?.kind, .storeReset)
    }

    func testCustomTrackerEditEventIsAvailableForLiveConsumers() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .customTrackerChanged)
        XCTAssertEqual(center.lastEvent?.kind, .customTrackerChanged)
    }

    func testTrackerSanitizerRemovesDeletedCustomKeysButPreservesBuiltIns() {
        let symptoms: Set<String> = ["headache", "c:kept", "c:deleted"]
        let sanitized = LocalDataChangeCenter.sanitizeCustomTrackerKeys(
            symptoms,
            availableKeys: ["c:kept"]
        )
        XCTAssertEqual(sanitized, ["headache", "c:kept"])
    }

    func testEmptyAffectedDayKeysIsAllowed() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .storeReset)
        XCTAssertTrue(center.lastEvent?.affectedDayKeys.isEmpty ?? false)
    }

    // MARK: - Draft dirty / conflict decision policy

    func testStoreResetAlwaysClears() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .storeReset)
        XCTAssertEqual(
            DailyLogExternalChangePolicy.action(
                for: center.lastEvent!, selectedDayKey: 20260101, draftIsDirty: true),
            .reset
        )
    }

    func testCustomTrackerRemovedAlwaysSanitizesDraft() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .customTrackerDeleted,
                    removedCustomTrackerKeys: ["custom_migraine"])
        XCTAssertEqual(
            DailyLogExternalChangePolicy.action(
                for: center.lastEvent!, selectedDayKey: 20260101, draftIsDirty: true),
            .sanitizeTrackers
        )
    }

    func testOtherDayEventIgnored() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .quickLogApplied, affectedDayKeys: [20260101])
        XCTAssertEqual(
            DailyLogExternalChangePolicy.action(
                for: center.lastEvent!, selectedDayKey: 20260102, draftIsDirty: false),
            .ignore
        )
    }

    func testSameDayChangeReloadsWhenCleanAndConflictsWhenDirty() {
        let center = LocalDataChangeCenter.shared
        center.post(kind: .healthImported, affectedDayKeys: [20260101])
        let event = center.lastEvent!
        XCTAssertEqual(
            DailyLogExternalChangePolicy.action(
                for: event, selectedDayKey: 20260101, draftIsDirty: false),
            .reload
        )
        XCTAssertEqual(
            DailyLogExternalChangePolicy.action(
                for: event, selectedDayKey: 20260101, draftIsDirty: true),
            .conflict
        )
    }

    // MARK: - QuickLog overwriting imported period

    func testQuickLogOverwriteSetsImportedFromHealthFalse() {
        let container = try! ModelContainer(
            for: PeriodDay.self, DailyLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        // Insert a period day marked as imported from Health.
        let period = PeriodDay(date: DayKey.date(from: 20260101), flow: .light)
        period.importedFromHealth = true
        context.insert(period)
        try! context.save()

        // Verify it's imported.
        let fetched = try! context.fetch(
            FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == 20260101 })
        ).first
        XCTAssertTrue(fetched?.importedFromHealth == true)

        let quickLog = QuickLog.period(
            flowRaw: FlowLevel.heavy.rawValue,
            dayKey: 20260101,
            sentAt: period.updatedAt.addingTimeInterval(1),
            tzOffsetSeconds: TimeZone.current.secondsFromGMT()
        )
        let result = QuickLogApplier.applyWithKeys([quickLog], context: context)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.affectedDayKeys, [20260101])

        let updated = try! context.fetch(
            FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == 20260101 })
        ).first
        XCTAssertEqual(updated?.flow, .heavy)
        XCTAssertFalse(updated?.importedFromHealth ?? true)
    }

    // MARK: - No event before failed save

    func testNoEventEmittedOnEmptyApply() {
        let center = LocalDataChangeCenter.shared
        let before = center.lastEvent
        // Empty apply should not emit any event.
        let container = try! ModelContainer(
            for: PeriodDay.self, DailyLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        _ = QuickLogApplier.apply([], context: container.mainContext)
        // lastEvent should not have changed for empty input.
        XCTAssertEqual(before?.revision, center.lastEvent?.revision)
    }
}
