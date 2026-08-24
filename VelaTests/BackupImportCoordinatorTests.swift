import Foundation
import SwiftData
import XCTest
@testable import Vela

@MainActor
final class BackupImportCoordinatorTests: XCTestCase {
    private enum ForcedSaveError: Error {
        case failed
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PeriodDay.self,
            DailyLog.self,
            Medication.self,
            MedicationIntake.self,
            CustomSymptom.self
        ])
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        // Model dayKeys are derived in the device timezone. Construct fixture
        // dates in that same timezone so an intended same-day merge remains
        // an update rather than becoming a neighbouring-day insert.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func defaults(_ suffix: String = UUID().uuidString) throws -> UserDefaults {
        guard let result = UserDefaults(suiteName: "BackupImportCoordinatorTests.\(suffix)") else {
            throw NSError(domain: "BackupImportCoordinatorTests", code: 1)
        }
        return result
    }

    private func seedCurrentData(in context: ModelContext,
                                 medicationID: UUID,
                                 customKey: String) throws {
        let currentDate = date(2026, 8, 1)
        let period = PeriodDay(date: currentDate, flow: .light)
        period.createdAt = currentDate
        period.updatedAt = currentDate
        context.insert(period)

        let log = DailyLog(date: currentDate, mood: .okay, energy: 2, pain: 1,
                           note: "before")
        log.updatedAt = currentDate
        context.insert(log)

        let medication = Medication(name: "Existing")
        medication.id = medicationID
        medication.createdAt = currentDate
        context.insert(medication)
        context.insert(MedicationIntake(medicationId: medicationID, dayKey: 20260801))

        let symptom = CustomSymptom(label: "Existing symptom", emoji: "🙂")
        symptom.key = customKey
        symptom.createdAt = currentDate
        context.insert(symptom)

        try context.save()
    }

    func testMergeMutatesAllFiveModelsAndAppliesOnlyWhitelistedPreferences() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existingMedicationID = UUID()
        let newMedicationID = UUID()
        let existingCustomKey = "c:\(UUID().uuidString)"
        try seedCurrentData(in: context,
                            medicationID: existingMedicationID,
                            customKey: existingCustomKey)

        let defaults = try defaults("merge")
        defer { defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.merge") }
        defaults.set(true, forKey: "store.premium")
        defaults.set(true, forKey: "health.syncEnabled")
        defaults.set(true, forKey: "health.selectedTypes")
        defaults.set(true, forKey: "lock.enabled")
        defaults.set(true, forKey: "onboarding.done")
        let healthSyncBefore = HealthKitBridge.syncEnabled
        let healthTypesBefore = HealthKitBridge.selectedTypes
        let premiumBefore = UserDefaults.standard.bool(forKey: "store.premium")

        let newer = date(2026, 8, 3)
        let incoming = BackupSnapshot(
            periodDays: [BackupPeriodDayPayload(dayKey: 20260801,
                                                 flowRaw: FlowLevel.heavy.rawValue,
                                                 createdAt: date(2026, 8, 1),
                                                 updatedAt: newer,
                                                 importedFromHealth: true),
                          BackupPeriodDayPayload(dayKey: 20260802,
                                                 flowRaw: FlowLevel.spotting.rawValue,
                                                 createdAt: newer,
                                                 updatedAt: newer)],
            dailyLogs: [BackupDailyLogPayload(dayKey: 20260801,
                                              moodRaw: Mood.great.rawValue,
                                              energy: 5,
                                              pain: 0,
                                              steps: 12_345,
                                              exerciseMinutes: 42,
                                              basalBodyTemperatureCelsius: 36.7,
                                              spotting: true,
                                              healthImportedFields: ["spotting", "steps", "exercise"],
                                              note: "imported",
                                              updatedAt: newer)],
            medications: [BackupMedicationPayload(id: existingMedicationID,
                                                   name: "Incoming ignored",
                                                   createdAt: newer),
                           BackupMedicationPayload(id: newMedicationID,
                                                   name: "New medication",
                                                   createdAt: newer)],
            medicationIntakes: [BackupMedicationIntakePayload(
                                    medicationId: existingMedicationID,
                                    dayKey: 20260802,
                                    takenAt: newer),
                                BackupMedicationIntakePayload(
                                    medicationId: newMedicationID,
                                    dayKey: 20260802,
                                    takenAt: newer)],
            customSymptoms: [BackupCustomSymptomPayload(key: existingCustomKey,
                                                         label: "Incoming ignored",
                                                         emoji: "😶",
                                                         createdAt: newer),
                             BackupCustomSymptomPayload(key: "c:\(newMedicationID.uuidString)",
                                                         label: "New symptom",
                                                         emoji: "✨",
                                                         createdAt: newer)],
            preferences: BackupPreferences(theme: "rose",
                                           manualCycleEnabled: true,
                                           manualCycleLength: 32,
                                           manualPeriodLength: 6,
                                           hideSensitiveNotifications: true,
                                           lifeStageRaw: LifeStage.perimenopause.rawValue,
                                           contraception: BackupContraceptionPreference(
                                               methodRaw: ContraceptionSettings.Method.pill.rawValue,
                                               startDayKey: 20260801,
                                               reminderEnabled: true,
                                               reminderHour: 8,
                                               reminderMinute: 15,
                                               note: "imported note",
                                               updatedAt: newer)))

        let coordinator = BackupImportCoordinator(context: context,
                                                  postSaveRefresh: { _ in })
        let result = try coordinator.importSnapshot(incoming,
                                                    mode: .merge,
                                                    defaults: defaults)
        XCTAssertEqual(result.mode, .merge)
        XCTAssertEqual(result.importedCounts, incoming.counts)

        let periods = try context.fetch(FetchDescriptor<PeriodDay>())
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        let medications = try context.fetch(FetchDescriptor<Medication>())
        let intakes = try context.fetch(FetchDescriptor<MedicationIntake>())
        let symptoms = try context.fetch(FetchDescriptor<CustomSymptom>())
        XCTAssertEqual(periods.count, 2)
        XCTAssertEqual(periods.first(where: { $0.dayKey == 20260801 })?.flowRaw,
                       FlowLevel.heavy.rawValue)
        XCTAssertEqual(logs.first?.basalBodyTemperatureCelsius, 36.7)
        XCTAssertEqual(logs.first?.steps, 12_345)
        XCTAssertEqual(logs.first?.exerciseMinutes, 42)
        XCTAssertEqual(logs.first?.healthImportedFields, ["spotting", "steps", "exercise"])
        XCTAssertEqual(medications.count, 2)
        XCTAssertEqual(medications.first(where: { $0.id == existingMedicationID })?.name,
                       "Existing")
        XCTAssertEqual(intakes.count, 3)
        XCTAssertEqual(symptoms.count, 2)

        XCTAssertEqual(defaults.string(forKey: AppTheme.storageKey), "rose")
        XCTAssertTrue(defaults.bool(forKey: ManualCycle.Keys.enabled))
        XCTAssertEqual(defaults.integer(forKey: ManualCycle.Keys.cycleLength), 32)
        XCTAssertEqual(defaults.integer(forKey: ManualCycle.Keys.periodLength), 6)
        XCTAssertTrue(defaults.bool(forKey: NotificationManager.hideSensitiveKey))
        XCTAssertEqual(LifeStage.load(from: defaults), .perimenopause)
        let importedContraception = ContraceptionSettings.load(from: defaults)
        XCTAssertEqual(importedContraception.method, .pill)
        XCTAssertEqual(importedContraception.startDayKey, 20260801)
        XCTAssertTrue(importedContraception.reminderEnabled)
        XCTAssertEqual(importedContraception.reminderHour, 8)
        XCTAssertEqual(importedContraception.reminderMinute, 15)
        XCTAssertEqual(importedContraception.note, "imported note")
        XCTAssertTrue(defaults.bool(forKey: "store.premium"))
        XCTAssertTrue(defaults.bool(forKey: "health.syncEnabled"))
        XCTAssertTrue(defaults.bool(forKey: "health.selectedTypes"))
        XCTAssertTrue(defaults.bool(forKey: "lock.enabled"))
        XCTAssertTrue(defaults.bool(forKey: "onboarding.done"))
        XCTAssertEqual(HealthKitBridge.syncEnabled, healthSyncBefore)
        XCTAssertEqual(HealthKitBridge.selectedTypes, healthTypesBefore)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "store.premium"), premiumBefore)
    }

    func testReplaceReplacesAllFiveCollectionsAndPreservesIncomingIdentity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCurrentData(in: context, medicationID: UUID(), customKey: "c:\(UUID().uuidString)")
        let defaults = try defaults("replace")
        defer { defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.replace") }

        let medicationID = UUID()
        let customKey = "c:\(UUID().uuidString)"
        let importedDate = date(2026, 8, 5)
        let incoming = BackupSnapshot(
            periodDays: [BackupPeriodDayPayload(dayKey: 20260805,
                                                 flowRaw: FlowLevel.medium.rawValue,
                                                 createdAt: importedDate,
                                                 updatedAt: importedDate,
                                                 importedFromHealth: true)],
            dailyLogs: [BackupDailyLogPayload(dayKey: 20260805,
                                              moodRaw: Mood.good.rawValue,
                                              sleepHours: 8,
                                              steps: 6_789,
                                              exerciseMinutes: 30,
                                              healthImportedFields: ["sleep"],
                                              updatedAt: importedDate)],
            medications: [BackupMedicationPayload(id: medicationID,
                                                   name: "Imported",
                                                   createdAt: importedDate)],
            medicationIntakes: [BackupMedicationIntakePayload(
                                    medicationId: medicationID,
                                    dayKey: 20260805,
                                    takenAt: importedDate)],
            customSymptoms: [BackupCustomSymptomPayload(key: customKey,
                                                         label: "Imported symptom",
                                                         emoji: "🌿",
                                                         createdAt: importedDate)],
            preferences: BackupPreferences(theme: "violet"))

        let coordinator = BackupImportCoordinator(context: context,
                                                  postSaveRefresh: { _ in })
        _ = try coordinator.importSnapshot(incoming,
                                           mode: .replace,
                                           defaults: defaults)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PeriodDay>()).map(\.dayKey), [20260805])
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLog>()).map(\.dayKey), [20260805])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).map(\.id), [medicationID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<MedicationIntake>()).map(\.key),
                       ["\(medicationID.uuidString)-20260805"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<CustomSymptom>()).map(\.key), [customKey])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PeriodDay>()).first?.createdAt, importedDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PeriodDay>()).first?.importedFromHealth ?? false)
        let importedLog = try context.fetch(FetchDescriptor<DailyLog>()).first
        XCTAssertEqual(importedLog?.steps, 6_789)
        XCTAssertEqual(importedLog?.exerciseMinutes, 30)
    }

    func testOldBackupWithoutNewPreferencesLeavesLocalValuesUntouched() throws {
        let container = try makeContainer()
        let defaults = try defaults("old-preferences")
        defer {
            defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.old-preferences")
        }

        LifeStage.save(.perimenopause, to: defaults)
        let localContraception = ContraceptionSettings(
            method: .pill,
            startDayKey: 20260801,
            reminderEnabled: true,
            reminderHour: 7,
            reminderMinute: 30,
            note: "keep locally",
            updatedAt: date(2026, 8, 1))
        XCTAssertTrue(localContraception.save(to: defaults))

        // Missing optional preference keys model a pre-v1.1 backup. They
        // should not clear preferences already configured on this device.
        let incoming = BackupSnapshot(preferences: BackupPreferences(theme: "rose"))
        let coordinator = BackupImportCoordinator(context: container.mainContext,
                                                  postSaveRefresh: { _ in })
        _ = try coordinator.importSnapshot(incoming, mode: .replace, defaults: defaults)

        XCTAssertEqual(LifeStage.load(from: defaults), .perimenopause)
        let restoredContraception = ContraceptionSettings.load(from: defaults)
        XCTAssertEqual(restoredContraception.method, .pill)
        XCTAssertEqual(restoredContraception.startDayKey, 20260801)
        XCTAssertTrue(restoredContraception.reminderEnabled)
        XCTAssertEqual(restoredContraception.reminderHour, 7)
        XCTAssertEqual(restoredContraception.reminderMinute, 30)
        XCTAssertEqual(restoredContraception.note, "keep locally")
    }

    func testMergeOldPayloadWithoutActivityFieldsPreservesExistingValuesAndMarkers() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currentDate = date(2026, 8, 1)
        let log = DailyLog(date: currentDate,
                           steps: 2_222,
                           exerciseMinutes: 18)
        log.healthImportedFields = ["steps", "exercise"]
        log.updatedAt = currentDate
        context.insert(log)
        try context.save()

        let defaults = try defaults("old-activity")
        defer { defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.old-activity") }
        let incoming = BackupSnapshot(
            dailyLogs: [BackupDailyLogPayload(dayKey: 20260801,
                                              moodRaw: Mood.good.rawValue,
                                              updatedAt: date(2026, 8, 2))])

        let coordinator = BackupImportCoordinator(context: context,
                                                  postSaveRefresh: { _ in })
        _ = try coordinator.importSnapshot(incoming, mode: .merge, defaults: defaults)

        let restored = try context.fetch(FetchDescriptor<DailyLog>()).first
        XCTAssertEqual(restored?.steps, 2_222)
        XCTAssertEqual(restored?.exerciseMinutes, 18)
        XCTAssertEqual(restored?.healthImportedFields, ["exercise", "steps"])
    }

    func testSuccessfulImportPublishesReplayCutoffThatOnlyBlocksPreImportLogs() throws {
        let container = try makeContainer()
        let defaults = try defaults("replay")
        defer { defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.replay") }

        let importedAt = Date(timeIntervalSinceNow: -2)
        let incoming = BackupSnapshot(
            periodDays: [BackupPeriodDayPayload(dayKey: 20260806,
                                                flowRaw: FlowLevel.medium.rawValue,
                                                createdAt: importedAt,
                                                updatedAt: importedAt)])
        let coordinator = BackupImportCoordinator(context: container.mainContext,
                                                  postSaveRefresh: { _ in })
        let result = try coordinator.importSnapshot(incoming, mode: .replace, defaults: defaults)
        let persistedCutoff = try XCTUnwrap(QuickLogApplier.deleteReplayCutoff(from: defaults))
        XCTAssertEqual(persistedCutoff.timeIntervalSince1970,
                       result.replayCutoff.timeIntervalSince1970,
                       accuracy: 0.000_001)

        let oldLog = QuickLog.period(flowRaw: FlowLevel.heavy.rawValue,
                                     dayKey: 20260806,
                                     sentAt: result.replayCutoff.addingTimeInterval(-1))
        let newLog = QuickLog.period(flowRaw: FlowLevel.light.rawValue,
                                     dayKey: 20260807,
                                     sentAt: result.replayCutoff.addingTimeInterval(1))
        XCTAssertTrue(QuickLogApplier.apply([oldLog, newLog],
                                            context: container.mainContext,
                                            defaults: defaults))
        let periods = try container.mainContext.fetch(FetchDescriptor<PeriodDay>())
        XCTAssertEqual(periods.count, 2)
        XCTAssertEqual(periods.first(where: { $0.dayKey == 20260806 })?.flowRaw,
                       FlowLevel.medium.rawValue)
        XCTAssertEqual(periods.first(where: { $0.dayKey == 20260807 })?.flowRaw,
                       FlowLevel.light.rawValue)
    }

    func testSaveFailureRollsBackModelsAndLeavesPreferencesUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let medicationID = UUID()
        try seedCurrentData(in: context, medicationID: medicationID, customKey: "c:\(UUID().uuidString)")
        let defaults = try defaults("rollback")
        defer { defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.rollback") }
        defaults.set("rose", forKey: AppTheme.storageKey)

        let incoming = BackupSnapshot(
            dailyLogs: [BackupDailyLogPayload(dayKey: 20260801,
                                              moodRaw: Mood.great.rawValue,
                                              updatedAt: date(2026, 8, 4))],
            medications: [BackupMedicationPayload(id: medicationID,
                                                   name: "Should not save",
                                                   createdAt: date(2026, 8, 4))],
            preferences: BackupPreferences(theme: "teal"))
        let coordinator = BackupImportCoordinator(
            context: context,
            saveOperation: { throw ForcedSaveError.failed },
            postSaveRefresh: { _ in })

        XCTAssertThrowsError(try coordinator.importSnapshot(incoming,
                                                             mode: .merge,
                                                             defaults: defaults)) { error in
            XCTAssertTrue(error is BackupImportCoordinatorError)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLog>()).first?.note, "before")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).first?.name, "Existing")
        XCTAssertEqual(defaults.string(forKey: AppTheme.storageKey), "rose")
    }

    func testProScheduleRequiresCurrentDeviceEntitlement() {
        XCTAssertTrue(BackupImportCoordinator.shouldUseProMedicationSchedule(
            deviceHasPremium: true, proScheduleEnabled: true, slotCount: 1))
        XCTAssertFalse(BackupImportCoordinator.shouldUseProMedicationSchedule(
            deviceHasPremium: false, proScheduleEnabled: true, slotCount: 1))
        XCTAssertFalse(BackupImportCoordinator.shouldUseProMedicationSchedule(
            deviceHasPremium: true, proScheduleEnabled: false, slotCount: 1))
        XCTAssertFalse(BackupImportCoordinator.shouldUseProMedicationSchedule(
            deviceHasPremium: true, proScheduleEnabled: true, slotCount: 0))
        XCTAssertTrue(BackupImportCoordinator.canApplyBackupTheme("rose",
                                                                  deviceHasPremium: false))
        XCTAssertFalse(BackupImportCoordinator.canApplyBackupTheme("teal",
                                                                   deviceHasPremium: false))
        XCTAssertTrue(BackupImportCoordinator.canApplyBackupTheme("teal",
                                                                  deviceHasPremium: true))
    }

    func testDanglingImportedIntakeIsRejectedBeforeMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existingMedicationID = UUID()
        try seedCurrentData(in: context,
                            medicationID: existingMedicationID,
                            customKey: "c:\(UUID().uuidString)")
        let defaults = try defaults("dangling")
        defer { defaults.removePersistentDomain(forName: "BackupImportCoordinatorTests.dangling") }

        let unknownMedicationID = UUID()
        let incoming = BackupSnapshot(
            medicationIntakes: [BackupMedicationIntakePayload(
                medicationId: unknownMedicationID,
                dayKey: 20260802,
                takenAt: date(2026, 8, 2))])
        let coordinator = BackupImportCoordinator(context: context,
                                                  postSaveRefresh: { _ in })

        XCTAssertThrowsError(try coordinator.importSnapshot(incoming,
                                                             mode: .merge,
                                                             defaults: defaults)) { error in
            XCTAssertEqual((error as? BackupImportCoordinatorError),
                           .invalidMedicationReference)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<MedicationIntake>()).count, 1)
    }
}
