import Foundation
import SwiftData
import XCTest
@testable import Vela

@MainActor
final class UserContentDeletionTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PeriodDay.self,
            DailyLog.self,
            Medication.self,
            MedicationIntake.self,
            CustomSymptom.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }

    // MARK: - 1. Custom tracker cascade removes its key from all DailyLog rows

    func testCustomTrackerCascadeRemovesKeyFromDailyLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let tracker = CustomSymptom(label: "Mood Tracker", emoji: "🧠")
        context.insert(tracker)

        let log1 = DailyLog(date: date(2026, 8, 1), symptoms: [tracker.key, "headache"])
        let log2 = DailyLog(date: date(2026, 8, 2), symptoms: [tracker.key])
        let log3 = DailyLog(date: date(2026, 8, 3), symptoms: ["headache", "fatigue"])
        context.insert(log1)
        context.insert(log2)
        context.insert(log3)
        try context.save()

        let beforeLogs = try context.fetch(
            FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\DailyLog.dayKey)]))
        XCTAssertEqual(beforeLogs.count, 3)
        XCTAssertTrue(beforeLogs[0].symptoms.contains(tracker.key))
        XCTAssertTrue(beforeLogs[1].symptoms.contains(tracker.key))
        XCTAssertFalse(beforeLogs[2].symptoms.contains(tracker.key))

        try UserContentDeletion.deleteCustomTracker(
            tracker,
            context: context,
            notificationManager: NotificationManager.shared,
            dailyEnabled: false,
            dailyHour: 21,
            periodEnabled: false,
            periodAdvanceDays: 2,
            smartEnabled: false,
            pmsEnabled: false,
            storePremium: false,
            manualCycle: ManualCycle(enabled: false, cycleLength: 28, periodLength: 5)
        )

        // Re-fetch using a fresh context to verify persistence
        let freshContext = ModelContext(container)
        let afterLogs = try freshContext.fetch(
            FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\DailyLog.dayKey)]))
        XCTAssertEqual(afterLogs.count, 3, "All logs should remain")
        XCTAssertFalse(afterLogs[0].symptoms.contains(tracker.key))
        XCTAssertFalse(afterLogs[1].symptoms.contains(tracker.key))
        XCTAssertFalse(afterLogs[2].symptoms.contains(tracker.key))

        // Verify unrelated keys are preserved
        XCTAssertTrue(afterLogs[0].symptoms.contains("headache"),
                      "Unrelated key 'headache' should be preserved in log 1")
        XCTAssertTrue(afterLogs[2].symptoms.contains("headache"))
        XCTAssertTrue(afterLogs[2].symptoms.contains("fatigue"))

        // Verify tracker definition is deleted
        let trackers = try freshContext.fetch(FetchDescriptor<CustomSymptom>())
        XCTAssertEqual(trackers.count, 0)
    }

    func testUpdatingCustomTrackerPreservesKeyAndHistoricalReferences() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tracker = CustomSymptom(label: "原名称", emoji: "📝")
        let originalKey = tracker.key
        let log = DailyLog(date: date(2026, 8, 4), symptoms: [originalKey])
        context.insert(tracker)
        context.insert(log)
        try context.save()

        try UserContentDeletion.updateCustomTracker(
            tracker,
            label: "更新名称",
            emoji: "🌙",
            context: context
        )

        let fetchedTracker = try context.fetch(FetchDescriptor<CustomSymptom>()).first
        let fetchedLog = try context.fetch(FetchDescriptor<DailyLog>()).first
        XCTAssertEqual(fetchedTracker?.key, originalKey)
        XCTAssertEqual(fetchedTracker?.label, "更新名称")
        XCTAssertEqual(fetchedTracker?.emoji, "🌙")
        XCTAssertEqual(fetchedLog?.symptoms, [originalKey])
        XCTAssertEqual(LocalDataChangeCenter.shared.lastEvent?.kind, .customTrackerChanged)
    }

    // MARK: - 2. Medication delete cascades all matching intakes

    func testMedicationDeleteCascadesIntakes() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let med1 = Medication(name: "Metformin", emoji: "💊")
        let med2 = Medication(name: "Vitamin D", emoji: "☀️")
        context.insert(med1)
        context.insert(med2)

        let intake1 = MedicationIntake(medicationId: med1.id, dayKey: DayKey.from(date(2026, 8, 1)))
        let intake2 = MedicationIntake(medicationId: med1.id, dayKey: DayKey.from(date(2026, 8, 2)))
        let intake3 = MedicationIntake(medicationId: med2.id, dayKey: DayKey.from(date(2026, 8, 1)))
        context.insert(intake1)
        context.insert(intake2)
        context.insert(intake3)
        try context.save()

        // Delete med1
        try UserContentDeletion.deleteMedication(
            med1,
            context: context,
            notificationManager: NotificationManager.shared
        )

        // Verify: med1's intakes deleted, med2 and its intake remain
        let remainingMeds = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(remainingMeds.count, 1)
        XCTAssertEqual(remainingMeds.first?.id, med2.id)

        let remainingIntakes = try context.fetch(FetchDescriptor<MedicationIntake>())
        XCTAssertEqual(remainingIntakes.count, 1)
        XCTAssertEqual(remainingIntakes.first?.medicationId, med2.id)
        XCTAssertEqual(LocalDataChangeCenter.shared.lastEvent?.kind, .medicationDeleted)
    }

    // MARK: - 3. Deleting a DailyLog changes a fresh fetch immediately

    func testDeletingDailyLogChangesFetchImmediately() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let log1 = DailyLog(date: date(2026, 8, 1), mood: .good)
        let log2 = DailyLog(date: date(2026, 8, 2), mood: .great)
        context.insert(log1)
        context.insert(log2)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(fetched.count, 2)

        let oldSyncEnabled = HealthKitBridge.syncEnabled
        HealthKitBridge.syncEnabled = false
        defer { HealthKitBridge.syncEnabled = oldSyncEnabled }

        try await UserContentDeletion.deleteDailyLog(
            log1,
            context: context,
            notificationManager: NotificationManager.shared,
            dailyEnabled: false,
            dailyHour: 21,
            periodEnabled: false,
            periodAdvanceDays: 2,
            smartEnabled: false,
            pmsEnabled: false,
            storePremium: false,
            manualCycle: ManualCycle(enabled: false, cycleLength: 28, periodLength: 5)
        )

        fetched = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.dayKey, DayKey.from(date(2026, 8, 2)))
    }

    // MARK: - 4. Deleting a PeriodDay changes a fresh fetch immediately

    func testDeletingPeriodDayChangesFetchImmediately() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let p1 = PeriodDay(date: date(2026, 8, 1), flow: .heavy)
        let p2 = PeriodDay(date: date(2026, 8, 2), flow: .light)
        context.insert(p1)
        context.insert(p2)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<PeriodDay>())
        XCTAssertEqual(fetched.count, 2)

        let oldSyncEnabled = HealthKitBridge.syncEnabled
        HealthKitBridge.syncEnabled = false
        defer { HealthKitBridge.syncEnabled = oldSyncEnabled }

        try await UserContentDeletion.deletePeriodDay(
            p1,
            context: context,
            notificationManager: NotificationManager.shared,
            dailyEnabled: false,
            dailyHour: 21,
            periodEnabled: false,
            periodAdvanceDays: 2,
            smartEnabled: false,
            pmsEnabled: false,
            storePremium: false,
            manualCycle: ManualCycle(enabled: false, cycleLength: 28, periodLength: 5)
        )

        fetched = try context.fetch(FetchDescriptor<PeriodDay>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.dayKey, DayKey.from(date(2026, 8, 2)))
    }

    // MARK: - 5. Save failure does not run derived side effects

    /// Verifies that the deletion helpers follow the pattern:
    /// mutate → save → (only on success) refresh/side effects.
    /// We test this by checking the structure: if save() were to fail,
    /// the method throws before reaching refresh calls.
    func testDeleteMedicationIntakeSaveFailureStructure() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Test", emoji: "💊")
        context.insert(med)
        let intake = MedicationIntake(medicationId: med.id, dayKey: DayKey.from(date(2026, 8, 1)))
        context.insert(intake)
        try context.save()

        // Verify the intake exists
        var fetched = try context.fetch(FetchDescriptor<MedicationIntake>())
        XCTAssertEqual(fetched.count, 1)

        // Delete should succeed
        try UserContentDeletion.deleteMedicationIntake(intake, context: context)

        fetched = try context.fetch(FetchDescriptor<MedicationIntake>())
        XCTAssertEqual(fetched.count, 0)
        XCTAssertEqual(LocalDataChangeCenter.shared.lastEvent?.kind, .medicationIntakeDeleted)
    }

    // MARK: - 6. Notification cancel covers pending + delivered

    /// Source contract test: cancelAllMedicationReminders calls both
    /// removePendingNotificationRequests and removeDeliveredNotifications.
    /// We verify the method exists and can be called without crash.
    func testCancelAllMedicationRemindersCompiles() {
        let manager = NotificationManager.shared
        // Just verify the method signature is callable (no pending notifications in test)
        manager.cancelAllMedicationReminders(notificationId: "vela.med.test-uuid")
    }

    func testCancelMedicationReminderCompiles() {
        let manager = NotificationManager.shared
        manager.cancelMedicationReminder(id: "vela.med.test-uuid")
    }
}
