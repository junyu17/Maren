import Foundation
import SwiftData
import XCTest
@testable import Vela

@MainActor
final class QuickLogWidgetDrainTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickLogWidgetDrainTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "QuickLogWidgetDrainTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        defaults?.removePersistentDomain(forName: suiteName)
        tempDir = nil
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PeriodDay.self, DailyLog.self])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    func testReplayBlockedWidgetEntryIsAcknowledgedWithoutSaving() throws {
        let cutoff = Date(timeIntervalSinceNow: -60)
        XCTAssertTrue(QuickLogApplier.persistDeleteReplayCutoff(at: cutoff, in: defaults))

        let entry = QuickActionEntry(
            id: UUID(), kind: "period", flowRaw: FlowLevel.heavy.rawValue,
            moodRaw: nil, dayKey: QuickActionQueue.todayKey(),
            createdAt: cutoff.addingTimeInterval(-1))
        XCTAssertTrue(QuickActionQueue.append(entry, to: tempDir.path))

        let container = try makeContainer()
        WidgetQuickDrain.drainIfNeeded(context: container.mainContext,
                                       groupID: tempDir.path,
                                       defaults: defaults)

        XCTAssertTrue(QuickActionQueue.peek(from: tempDir.path).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PeriodDay>()).isEmpty)
    }

    func testWidgetDrainUsesProductionApplyAndPublishesLiveMutation() throws {
        let dayKey = QuickActionQueue.todayKey()
        let entry = QuickActionEntry.period(
            flowRaw: FlowLevel.heavy.rawValue,
            dayKey: dayKey
        )
        XCTAssertTrue(QuickActionQueue.append(entry, to: tempDir.path))

        let container = try makeContainer()
        let oldSyncEnabled = HealthKitBridge.syncEnabled
        HealthKitBridge.syncEnabled = false
        defer { HealthKitBridge.syncEnabled = oldSyncEnabled }
        LocalDataChangeCenter.shared._resetRevisionCounter()

        WidgetQuickDrain.drainIfNeeded(
            context: container.mainContext,
            groupID: tempDir.path,
            defaults: defaults
        )

        let period = try container.mainContext.fetch(
            FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == dayKey })
        ).first
        XCTAssertEqual(period?.flow, .heavy)
        XCTAssertTrue(QuickActionQueue.peek(from: tempDir.path).isEmpty)
        XCTAssertEqual(LocalDataChangeCenter.shared.lastEvent?.kind, .quickLogApplied)
        XCTAssertEqual(LocalDataChangeCenter.shared.lastEvent?.affectedDayKeys, [dayKey])
    }
}
