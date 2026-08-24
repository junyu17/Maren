import Foundation
import SwiftData
import XCTest
@testable import Vela

/// Delete All Data 的接收端重放屏障测试。
/// Watch 端 outbox/recent/applicationContext 无法由手机直接删除,
/// 因此这里只验证 cutoff 对手机落库的最终效果。
@MainActor
final class QuickLogReplayBarrierTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        PhoneConnectivity._clearPendingQuickLogsForTesting()
        suiteName = "QuickLogReplayBarrierTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
    }

    override func tearDown() {
        PhoneConnectivity._clearPendingQuickLogsForTesting()
        if let defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = ""
        defaults = nil
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PeriodDay.self, DailyLog.self])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func today() -> Int { QuickActionQueue.todayKey() }

    func testDeleteCutoffDefaultsToNilAndMalformedValuesFailOpen() {
        XCTAssertNil(QuickLogApplier.deleteReplayCutoff(from: defaults))

        defaults.set("not-a-timestamp", forKey: QuickLogApplier.deleteReplayCutoffKey)
        XCTAssertNil(QuickLogApplier.deleteReplayCutoff(from: defaults))

        defaults.set(Double.nan, forKey: QuickLogApplier.deleteReplayCutoffKey)
        XCTAssertNil(QuickLogApplier.deleteReplayCutoff(from: defaults))

        let log = QuickLog.period(flowRaw: 1, dayKey: today(), sentAt: Date())
        XCTAssertFalse(QuickLogApplier.isBlockedByDeleteReplay(log, defaults: defaults))
    }

    func testOldPeriodAndMoodAtCutoffAreRejected() throws {
        let cutoff = Date(timeIntervalSinceNow: -60)
        XCTAssertTrue(QuickLogApplier.persistDeleteReplayCutoff(at: cutoff, in: defaults))
        let storedCutoff = try XCTUnwrap(QuickLogApplier.deleteReplayCutoff(from: defaults))
        XCTAssertEqual(storedCutoff.timeIntervalSince1970, cutoff.timeIntervalSince1970, accuracy: 0.000_001)

        let container = try makeContainer()
        let dayKey = today()
        let period = QuickLog.period(flowRaw: FlowLevel.heavy.rawValue,
                                     dayKey: dayKey,
                                     sentAt: cutoff,
                                     tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        let mood = QuickLog.mood(moodRaw: Mood.great.rawValue,
                                 dayKey: dayKey,
                                 sentAt: cutoff,
                                 tzOffsetSeconds: TimeZone.current.secondsFromGMT())

        XCTAssertTrue(QuickLogApplier.isBlockedByDeleteReplay(period, defaults: defaults))
        XCTAssertTrue(QuickLogApplier.isBlockedByDeleteReplay(mood, defaults: defaults))
        XCTAssertTrue(QuickLogApplier.apply([period, mood],
                                            context: container.mainContext,
                                            defaults: defaults))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PeriodDay>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<DailyLog>()).isEmpty)
    }

    func testCutoffToleranceBlocksQuantizationErrorButAllowsClearlyLaterRecord() throws {
        let cutoff = Date(timeIntervalSinceNow: -60)
        XCTAssertTrue(QuickLogApplier.persistDeleteReplayCutoff(at: cutoff, in: defaults))
        let storedCutoff = try XCTUnwrap(QuickLogApplier.deleteReplayCutoff(from: defaults))
        let tolerance = QuickLogApplier.deleteReplayPersistenceTolerance

        let atOriginalCutoff = QuickLog.period(flowRaw: FlowLevel.heavy.rawValue,
                                               dayKey: today(),
                                               sentAt: cutoff,
                                               tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        let justAfterStoredCutoff = QuickLog.mood(moodRaw: Mood.great.rawValue,
                                                  dayKey: today(),
                                                  sentAt: storedCutoff.addingTimeInterval(tolerance / 2),
                                                  tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        let oneMillisecondLater = QuickLog.period(flowRaw: FlowLevel.light.rawValue,
                                                  dayKey: today(),
                                                  sentAt: cutoff.addingTimeInterval(0.001),
                                                  tzOffsetSeconds: TimeZone.current.secondsFromGMT())

        XCTAssertTrue(QuickLogApplier.isBlockedByDeleteReplay(atOriginalCutoff, defaults: defaults))
        XCTAssertTrue(QuickLogApplier.isBlockedByDeleteReplay(justAfterStoredCutoff, defaults: defaults))
        XCTAssertFalse(QuickLogApplier.isBlockedByDeleteReplay(oneMillisecondLater, defaults: defaults))
    }

    func testNewRecordAfterCutoffIsAccepted() throws {
        let cutoff = Date(timeIntervalSinceNow: -60)
        XCTAssertTrue(QuickLogApplier.persistDeleteReplayCutoff(at: cutoff, in: defaults))

        let container = try makeContainer()
        let log = QuickLog.mood(moodRaw: Mood.good.rawValue,
                                dayKey: today(),
                                sentAt: Date(),
                                tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        XCTAssertFalse(QuickLogApplier.isBlockedByDeleteReplay(log, defaults: defaults))
        XCTAssertTrue(QuickLogApplier.apply([log],
                                            context: container.mainContext,
                                            defaults: defaults))
        let saved = try container.mainContext.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.moodRaw, Mood.good.rawValue)
    }

    func testResetEpochMarkerRoundTripsAndPostResetCutoffAllowsNewLog() throws {
        let cutoff = Date(timeIntervalSinceNow: -1)
        let resetEpoch: Int64 = 7
        defaults.set(resetEpoch, forKey: PhoneConnectivity.resetEpochKey)
        XCTAssertEqual(PhoneConnectivity.resetEpoch(from: defaults), resetEpoch)
        XCTAssertTrue(QuickLogApplier.persistDeleteReplayCutoff(at: cutoff, in: defaults))

        let container = try makeContainer()
        let log = QuickLog.period(flowRaw: FlowLevel.light.rawValue,
                                  dayKey: today(),
                                  sentAt: Date(),
                                  tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        XCTAssertTrue(QuickLogApplier.apply([log], context: container.mainContext, defaults: defaults))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PeriodDay>()).count, 1)
    }

    func testResetGenerationsAdvanceAndDoNotWrapOldPackets() {
        let first = PhoneConnectivity.advanceResetEpoch(in: defaults)
        let second = PhoneConnectivity.advanceResetEpoch(in: defaults)

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        XCTAssertTrue(WatchResetGeneration.shouldApply(second, current: first))
        XCTAssertTrue(WatchResetGeneration.shouldApply(second, current: second))
        XCTAssertFalse(WatchResetGeneration.shouldApply(first, current: second))
        XCTAssertNil(WatchResetGeneration.decode("legacy-(UUID().uuidString)"))
    }

    func testInvalidAndEmptyBatchesDoNotPersist() throws {
        let container = try makeContainer()
        let invalid = QuickLog(kind: "period",
                               flowRaw: nil,
                               moodRaw: nil,
                               dayKey: 20260230,
                               sentAt: Date(),
                               tzOffsetSeconds: TimeZone.current.secondsFromGMT())

        XCTAssertTrue(QuickLogApplier.apply([], context: container.mainContext, defaults: defaults))
        XCTAssertTrue(QuickLogApplier.apply([invalid], context: container.mainContext, defaults: defaults))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PeriodDay>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<DailyLog>()).isEmpty)
        XCTAssertTrue(QuickLogApplier.shouldDiscard(invalid, defaults: defaults))
    }

    func testOfflineBatchKeepsNewestSentAtInsteadOfPhoneReceiveTime() throws {
        let container = try makeContainer()
        let dayKey = today()
        let older = Date(timeIntervalSinceNow: -120)
        let newer = Date(timeIntervalSinceNow: -60)
        let batch = [
            QuickLog.period(flowRaw: FlowLevel.heavy.rawValue, dayKey: dayKey, sentAt: older),
            QuickLog.period(flowRaw: FlowLevel.light.rawValue, dayKey: dayKey, sentAt: newer)
        ]

        let result = QuickLogApplier.applyWithKeys(
            batch,
            context: container.mainContext,
            defaults: defaults
        )
        XCTAssertTrue(result.success)

        let saved = try XCTUnwrap(
            container.mainContext.fetch(
                FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == dayKey })
            ).first
        )
        XCTAssertEqual(saved.flow, .light)
        XCTAssertEqual(saved.updatedAt.timeIntervalSince1970, newer.timeIntervalSince1970, accuracy: 0.001)
    }

    func testPhoneRetryJournalPersistsNewestPayloadPerDay() {
        let dayKey = today()
        let older = QuickLog.mood(
            moodRaw: Mood.low.rawValue,
            dayKey: dayKey,
            sentAt: Date(timeIntervalSinceNow: -120)
        )
        let newer = QuickLog.mood(
            moodRaw: Mood.great.rawValue,
            dayKey: dayKey,
            sentAt: Date(timeIntervalSinceNow: -60)
        )

        PhoneConnectivity._enqueuePendingQuickLogsForTesting([older])
        PhoneConnectivity._enqueuePendingQuickLogsForTesting([newer])

        let pending = PhoneConnectivity._pendingQuickLogsForTesting()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.moodRaw, Mood.great.rawValue)
    }

    func testConcurrentJournalMergesKeepDifferentKeysAndNewestSameKey() {
        let calendar = Calendar(identifier: .gregorian)
        let currentDayKey = today()
        let baseDate = DayKey.date(from: currentDayKey)
        let old = Date(timeIntervalSinceNow: -600)

        DispatchQueue.concurrentPerform(iterations: 32) { index in
            guard let date = calendar.date(byAdding: .day, value: index + 1, to: baseDate) else { return }
            let dayKey = DayKey.from(date)
            PhoneConnectivity._enqueuePendingQuickLogsForTesting([
                .period(flowRaw: FlowLevel.light.rawValue, dayKey: dayKey, sentAt: old),
                .mood(moodRaw: Mood.good.rawValue, dayKey: dayKey, sentAt: old),
                // These two records deliberately race with the same logical
                // keys.  The final merge below must retain the newer values.
                .period(flowRaw: FlowLevel.heavy.rawValue, dayKey: currentDayKey, sentAt: old),
                .mood(moodRaw: Mood.low.rawValue, dayKey: currentDayKey, sentAt: old)
            ])
        }

        let newest = Date(timeIntervalSinceNow: -1)
        PhoneConnectivity._enqueuePendingQuickLogsForTesting([
            .period(flowRaw: FlowLevel.spotting.rawValue, dayKey: currentDayKey, sentAt: newest),
            .mood(moodRaw: Mood.great.rawValue, dayKey: currentDayKey, sentAt: newest)
        ])

        let pending = PhoneConnectivity._pendingQuickLogsForTesting()
        XCTAssertEqual(pending.count, 66)
        XCTAssertEqual(
            pending.first(where: { $0.kind == "period" && $0.dayKey == currentDayKey })?.flowRaw,
            FlowLevel.spotting.rawValue
        )
        XCTAssertEqual(
            pending.first(where: { $0.kind == "mood" && $0.dayKey == currentDayKey })?.moodRaw,
            Mood.great.rawValue
        )
        for index in 0..<32 {
            guard let date = calendar.date(byAdding: .day, value: index + 1, to: baseDate) else {
                XCTFail("Unable to construct test date")
                continue
            }
            let dayKey = DayKey.from(date)
            XCTAssertNotNil(pending.first(where: { $0.kind == "period" && $0.dayKey == dayKey }))
            XCTAssertNotNil(pending.first(where: { $0.kind == "mood" && $0.dayKey == dayKey }))
        }
    }
}
