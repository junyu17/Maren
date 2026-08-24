import Foundation
import SwiftData

/// Errors raised while applying an already-authenticated snapshot to the
/// current SwiftData store.  Authentication errors are intentionally kept in
/// `EncryptedBackupEngine`; this type only covers local-store integration.
enum BackupImportCoordinatorError: Error, LocalizedError, Equatable {
    case invalidMedicationReference
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidMedicationReference:
            return String(localized: "The backup contains a medication check-in without a matching medication.")
        case .persistenceFailed:
            return String(localized: "The backup could not be saved. Your existing records were not changed.")
        }
    }
}

struct BackupImportResult: Sendable {
    let mode: BackupMergeMode
    let plan: BackupMergePlan
    let importedCounts: BackupRecordCounts
    /// Receiver-side barrier written immediately after the imported models
    /// become durable.  Watch/Widget payloads created before this instant are
    /// rejected, while records created afterwards remain eligible.
    let replayCutoff: Date
    let watchResetEpoch: Int64
    let quickQueueCleared: Bool
}

/// Main-actor SwiftData integration for the pure backup engine.
///
/// Encryption/decryption belongs in a detached task owned by the UI.  This
/// coordinator intentionally accepts only a value snapshot and touches
/// `ModelContext` on the main actor.  It creates a fresh current snapshot for
/// every plan/application, so a preview cannot silently apply against stale
/// data after the user has continued editing the app.
@MainActor
final class BackupImportCoordinator {
    let context: ModelContext
    let engine: EncryptedBackupEngine

    // These hooks are intentionally internal and default to the live
    // operations.  In-memory tests can force a save failure or suppress
    // derived-device side effects without mocking SwiftData itself.
    private let saveOperation: (() throws -> Void)?
    private let postSaveRefresh: ((UserDefaults) -> Void)?

    init(context: ModelContext,
         engine: EncryptedBackupEngine = EncryptedBackupEngine(),
         saveOperation: (() throws -> Void)? = nil,
         postSaveRefresh: ((UserDefaults) -> Void)? = nil) {
        self.context = context
        self.engine = engine
        self.saveOperation = saveOperation
        self.postSaveRefresh = postSaveRefresh
    }

    /// Pure entitlement gate used by notification refresh and integration
    /// tests.  Backup data never changes this decision.
    static func shouldUseProMedicationSchedule(deviceHasPremium: Bool,
                                                proScheduleEnabled: Bool,
                                                slotCount: Int) -> Bool {
        deviceHasPremium && proScheduleEnabled && slotCount > 0
    }

    /// Premium color themes may travel as a preference, but importing one
    /// must not grant a free device a paid feature.  Rose is the free theme.
    static func canApplyBackupTheme(_ theme: String?,
                                    deviceHasPremium: Bool) -> Bool {
        guard let theme else { return false }
        return theme == "rose" || deviceHasPremium
    }

    /// Fetches all five model collections and captures only the explicit
    /// preferences whitelist.  No SwiftData mutation occurs here.
    func currentSnapshot(preferences: BackupPreferences? = nil) throws -> BackupSnapshot {
        let periods = try context.fetch(FetchDescriptor<PeriodDay>())
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        let medications = try context.fetch(FetchDescriptor<Medication>())
        let intakes = try context.fetch(FetchDescriptor<MedicationIntake>())
        let customSymptoms = try context.fetch(FetchDescriptor<CustomSymptom>())
        let snapshot = BackupSnapshot.capture(
            periodDays: periods,
            dailyLogs: logs,
            medications: medications,
            medicationIntakes: intakes,
            customSymptoms: customSymptoms,
            preferences: preferences ?? BackupPreferences.fromCurrentDeviceDefaults()
        )
        try snapshot.validated(using: engine.configuration.limits)
        return snapshot
    }

    /// Alias kept explicit for export callers and future Settings integration.
    func captureSnapshot(preferences: BackupPreferences? = nil) throws -> BackupSnapshot {
        try currentSnapshot(preferences: preferences)
    }

    /// Builds a fresh deterministic merge/replace plan without mutating the
    /// store.  The incoming snapshot is checked against current medication IDs
    /// for merge-mode intake references.
    func makePlan(for incoming: BackupSnapshot,
                  mode: BackupMergeMode = .merge) throws -> BackupMergePlan {
        let current = try currentSnapshot()
        return try makePlan(current: current, incoming: incoming, mode: mode)
    }

    /// Applies an authenticated snapshot.  All five model collections are
    /// mutated in one context transaction and exactly one `save()` is issued.
    /// UserDefaults are changed only after that save succeeds.
    @discardableResult
    func importSnapshot(_ incoming: BackupSnapshot,
                        mode: BackupMergeMode = .merge,
                        defaults: UserDefaults = .standard) throws -> BackupImportResult {
        let current = try currentSnapshot(
            preferences: BackupPreferences.fromCurrentDeviceDefaults(defaults))
        let plan = try makePlan(current: current, incoming: incoming, mode: mode)

        // Capture notification IDs before replacement.  This is deliberately
        // done before any model mutation so stale schedules can be cancelled
        // after (and only after) a successful database save.
        let existingMedications = try context.fetch(FetchDescriptor<Medication>())
        let existingMedicationNotificationIds = existingMedications.map(\.notificationId)

        do {
            try apply(plan: plan, mode: mode)
            if let saveOperation {
                try saveOperation()
            } else {
                try context.save()
            }
        } catch let error as BackupImportCoordinatorError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw BackupImportCoordinatorError.persistenceFailed
        }

        // Establish the replay barrier before applying preferences or
        // refreshing Widget/Watch derived state.  Those refreshes publish the
        // imported snapshot and must not leave a window in which an old Watch
        // outbox can overwrite it.  resetWatchState also cancels the iPhone's
        // outstanding user-info transfers and sends the epoch to the Watch.
        let replayCutoff = Date()
        let watchReset = PhoneConnectivity.shared.resetWatchState(at: replayCutoff,
                                                                   defaults: defaults)

        // No premium state, HealthKit authorization/sync/type selections,
        // onboarding, lock, or device permission values are read or written.
        applyWhitelistedPreferences(plan.preferencesToApply, to: defaults)

        // Derived local artifacts are refreshed only after the durable save.
        // In particular, this path never calls HealthKit export/write APIs.
        for notificationId in existingMedicationNotificationIds {
            NotificationManager.shared.cancelAllMedicationReminders(notificationId: notificationId)
        }
        if let postSaveRefresh {
            postSaveRefresh(defaults)
        } else {
            refreshDerivedState(defaults: defaults)
        }

        // Broadcast change event after successful import.
        let affectedKeys = affectedDayKeys(from: plan)
            .union(current.periodDays.map(\.dayKey))
            .union(current.dailyLogs.map(\.dayKey))
        LocalDataChangeCenter.shared.post(kind: .backupImported, affectedDayKeys: affectedKeys)

        return BackupImportResult(mode: mode,
                                  plan: plan,
                                  importedCounts: incoming.counts,
                                  replayCutoff: replayCutoff,
                                  watchResetEpoch: watchReset.epoch,
                                  quickQueueCleared: watchReset.phoneQueueCleared)
    }

    /// Collects affected day keys from the merge plan for event broadcasting.
    private func affectedDayKeys(from plan: BackupMergePlan) -> Set<Int> {
        var keys = Set<Int>()
        for item in plan.periodDaysToInsert { keys.insert(item.dayKey) }
        for item in plan.periodDaysToUpdate { keys.insert(item.dayKey) }
        for item in plan.dailyLogsToInsert { keys.insert(item.dayKey) }
        for item in plan.dailyLogsToUpdate { keys.insert(item.dayKey) }
        return keys
    }

    private func makePlan(current: BackupSnapshot,
                          incoming: BackupSnapshot,
                          mode: BackupMergeMode) throws -> BackupMergePlan {
        let incomingMedicationIDs = Set(incoming.medications.map(\.id))
        let currentMedicationIDs = Set(current.medications.map(\.id))
        let availableMedicationIDs: Set<UUID>
        switch mode {
        case .merge:
            availableMedicationIDs = incomingMedicationIDs.union(currentMedicationIDs)
        case .replace:
            availableMedicationIDs = incomingMedicationIDs
        }
        guard incoming.medicationIntakes.allSatisfy({
            availableMedicationIDs.contains($0.medicationId)
        }) else {
            throw BackupImportCoordinatorError.invalidMedicationReference
        }

        // Validate the payload after the local referential-integrity check.
        // The snapshot validator rejects an intake absent from the payload's
        // medication table as an invalid snapshot, while this integration
        // boundary promises the more specific coordinator error before any
        // SwiftData mutation.
        try incoming.validated(using: engine.configuration.limits)

        return BackupMergePlanner.plan(current: current,
                                       incoming: incoming,
                                       mode: mode)
    }

    private func apply(plan: BackupMergePlan,
                       mode: BackupMergeMode) throws {
        let periods = try context.fetch(FetchDescriptor<PeriodDay>())
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        let medications = try context.fetch(FetchDescriptor<Medication>())
        let intakes = try context.fetch(FetchDescriptor<MedicationIntake>())
        let customSymptoms = try context.fetch(FetchDescriptor<CustomSymptom>())

        switch mode {
        case .replace:
            // Delete intake rows before their medication definitions even
            // though the current models have no SwiftData relationship.
            for intake in intakes { context.delete(intake) }
            for period in periods { context.delete(period) }
            for log in logs { context.delete(log) }
            for medication in medications { context.delete(medication) }
            for customSymptom in customSymptoms { context.delete(customSymptom) }

            for item in plan.periodDaysToInsert {
                context.insert(makePeriodDay(from: item))
            }
            for item in plan.dailyLogsToInsert {
                context.insert(makeDailyLog(from: item))
            }
            for item in plan.medicationsToInsert {
                context.insert(makeMedication(from: item))
            }
            for item in plan.medicationIntakesToInsert {
                context.insert(makeMedicationIntake(from: item))
            }
            for item in plan.customSymptomsToInsert {
                context.insert(makeCustomSymptom(from: item))
            }

        case .merge:
            var periodsByKey: [Int: PeriodDay] = [:]
            for period in periods where periodsByKey[period.dayKey] == nil {
                periodsByKey[period.dayKey] = period
            }
            for item in plan.periodDaysToInsert {
                let model = makePeriodDay(from: item)
                context.insert(model)
                periodsByKey[item.dayKey] = model
            }
            for item in plan.periodDaysToUpdate {
                if let model = periodsByKey[item.dayKey] {
                    apply(item, to: model)
                } else {
                    let model = makePeriodDay(from: item)
                    context.insert(model)
                    periodsByKey[item.dayKey] = model
                }
            }

            var logsByKey: [Int: DailyLog] = [:]
            for log in logs where logsByKey[log.dayKey] == nil {
                logsByKey[log.dayKey] = log
            }
            for item in plan.dailyLogsToInsert {
                let model = makeDailyLog(from: item)
                context.insert(model)
                logsByKey[item.dayKey] = model
            }
            for item in plan.dailyLogsToUpdate {
                if let model = logsByKey[item.dayKey] {
                    apply(item, to: model)
                } else {
                    let model = makeDailyLog(from: item)
                    context.insert(model)
                    logsByKey[item.dayKey] = model
                }
            }

            var medicationIDs = Set(medications.map(\.id))
            for item in plan.medicationsToInsert where !medicationIDs.contains(item.id) {
                context.insert(makeMedication(from: item))
                medicationIDs.insert(item.id)
            }

            var intakeKeys = Set(intakes.map(\.key))
            for item in plan.medicationIntakesToInsert where !intakeKeys.contains(item.key) {
                guard medicationIDs.contains(item.medicationId) else {
                    throw BackupImportCoordinatorError.invalidMedicationReference
                }
                context.insert(makeMedicationIntake(from: item))
                intakeKeys.insert(item.key)
            }

            var customKeys = Set(customSymptoms.map(\.key))
            for item in plan.customSymptomsToInsert where !customKeys.contains(item.key) {
                context.insert(makeCustomSymptom(from: item))
                customKeys.insert(item.key)
            }
        }

    }

    private func makePeriodDay(from item: BackupPeriodDayPayload) -> PeriodDay {
        let flow = FlowLevel(rawValue: item.flowRaw) ?? .medium
        let model = PeriodDay(date: DayKey.date(from: item.dayKey), flow: flow)
        model.dayKey = item.dayKey
        model.flowRaw = item.flowRaw
        model.createdAt = item.createdAt
        model.updatedAt = item.updatedAt
        model.importedFromHealth = item.importedFromHealth
        return model
    }

    private func apply(_ item: BackupPeriodDayPayload, to model: PeriodDay) {
        model.dayKey = item.dayKey
        model.flowRaw = item.flowRaw
        model.createdAt = item.createdAt
        model.updatedAt = item.updatedAt
        model.importedFromHealth = item.importedFromHealth
    }

    private func makeDailyLog(from item: BackupDailyLogPayload) -> DailyLog {
        let model = DailyLog(date: DayKey.date(from: item.dayKey),
                             mood: Mood(rawValue: item.moodRaw),
                             energy: item.energy,
                             pain: item.pain,
                             sleepHours: item.sleepHours,
                             weight: item.weight,
                             steps: item.steps,
                             exerciseMinutes: item.exerciseMinutes,
                             basalBodyTemperatureCelsius: item.basalBodyTemperatureCelsius,
                             spotting: item.spotting,
                             symptoms: item.symptoms,
                             note: item.note)
        model.dayKey = item.dayKey
        model.moodRaw = item.moodRaw
        model.energy = item.energy
        model.pain = item.pain
        model.sleepHours = item.sleepHours
        model.weight = item.weight
        model.steps = item.steps
        model.exerciseMinutes = item.exerciseMinutes
        model.basalBodyTemperatureCelsius = item.basalBodyTemperatureCelsius
        model.spotting = item.spotting
        model.healthImportedFields = item.healthImportedFields
        model.symptoms = item.symptoms
        model.note = item.note
        model.updatedAt = item.updatedAt
        return model
    }

    private func apply(_ item: BackupDailyLogPayload, to model: DailyLog) {
        model.dayKey = item.dayKey
        model.moodRaw = item.moodRaw
        model.energy = item.energy
        model.pain = item.pain
        model.sleepHours = item.sleepHours
        model.weight = item.weight
        // Older backups decode the newly added activity fields as nil. Keep
        // the current values (and their provenance markers) in that case;
        // a newer payload carrying either field replaces the pair together.
        let preservesActivityFields = item.steps == nil && item.exerciseMinutes == nil
        if !preservesActivityFields {
            model.steps = item.steps
            model.exerciseMinutes = item.exerciseMinutes
        }
        model.basalBodyTemperatureCelsius = item.basalBodyTemperatureCelsius
        model.spotting = item.spotting
        if preservesActivityFields {
            let activityMarkers = Set(["steps", "exercise"])
            let existingMarkers = model.healthImportedFields.filter { activityMarkers.contains($0) }
            model.healthImportedFields = Array(
                Set(item.healthImportedFields + existingMarkers)
            ).sorted()
        } else {
            model.healthImportedFields = item.healthImportedFields
        }
        model.symptoms = item.symptoms
        model.note = item.note
        model.updatedAt = item.updatedAt
    }

    private func makeMedication(from item: BackupMedicationPayload) -> Medication {
        let model = Medication(name: item.name,
                               emoji: item.emoji,
                               reminderEnabled: item.reminderEnabled,
                               reminderHour: item.reminderHour,
                               reminderMinute: item.reminderMinute)
        model.id = item.id
        model.name = item.name
        model.emoji = item.emoji
        model.reminderEnabled = item.reminderEnabled
        model.reminderHour = item.reminderHour
        model.reminderMinute = item.reminderMinute
        model.proScheduleEnabled = item.proScheduleEnabled
        model.scheduleSlotsJSON = item.scheduleSlotsJSON
        model.createdAt = item.createdAt
        return model
    }

    private func makeMedicationIntake(from item: BackupMedicationIntakePayload) -> MedicationIntake {
        let model = MedicationIntake(medicationId: item.medicationId, dayKey: item.dayKey)
        model.key = item.key
        model.medicationId = item.medicationId
        model.dayKey = item.dayKey
        model.takenAt = item.takenAt
        return model
    }

    private func makeCustomSymptom(from item: BackupCustomSymptomPayload) -> CustomSymptom {
        let model = CustomSymptom(label: item.label, emoji: item.emoji)
        model.key = item.key
        model.label = item.label
        model.emoji = item.emoji
        model.createdAt = item.createdAt
        return model
    }

    private func applyWhitelistedPreferences(_ preferences: BackupPreferences,
                                             to defaults: UserDefaults) {
        if let theme = preferences.theme,
           ["rose", "teal", "violet", "amber", "ink"].contains(theme),
           Self.canApplyBackupTheme(theme, deviceHasPremium: Store.shared.premium) {
            defaults.set(theme, forKey: AppTheme.storageKey)
        }
        defaults.set(preferences.manualCycleEnabled, forKey: ManualCycle.Keys.enabled)
        defaults.set(preferences.manualCycleLength, forKey: ManualCycle.Keys.cycleLength)
        defaults.set(preferences.manualPeriodLength, forKey: ManualCycle.Keys.periodLength)
        defaults.set(preferences.hideSensitiveNotifications,
                     forKey: NotificationManager.hideSensitiveKey)

        if let raw = preferences.lifeStageRaw,
           let lifeStage = LifeStage(rawValue: raw) {
            LifeStage.save(lifeStage, to: defaults)
        }

        if let payload = preferences.contraception,
           let method = ContraceptionSettings.Method(rawValue: payload.methodRaw) {
            let profile = ContraceptionSettings(
                method: method,
                startDayKey: payload.startDayKey,
                reminderEnabled: payload.reminderEnabled,
                reminderHour: payload.reminderHour,
                reminderMinute: payload.reminderMinute,
                note: payload.note,
                updatedAt: payload.updatedAt).normalized
            if profile.save(to: defaults) {
                // This only reconciles the existing device authorization and
                // never requests permission while importing a backup.
                NotificationManager.shared.schedule(profile: profile)
            }
        }
    }

    /// Rebuilds local, derived presentation state after the store is durable.
    /// Failures here do not roll back a successful import; the next app launch
    /// can rebuild these artifacts again from the saved five-model snapshot.
    private func refreshDerivedState(defaults: UserDefaults) {
        let periods: [PeriodDay]
        let logs: [DailyLog]
        let medications: [Medication]
        do {
            periods = try context.fetch(FetchDescriptor<PeriodDay>())
            logs = try context.fetch(FetchDescriptor<DailyLog>())
            medications = try context.fetch(FetchDescriptor<Medication>())
        } catch {
            CustomSymptomStore.refresh(context)
            return
        }

        CustomSymptomStore.refresh(context)
        WidgetSync.refresh(periodDays: periods, logs: logs)

        let notificationManager = NotificationManager.shared
        // Entitlement is always read from the current device StoreKit state;
        // it is never restored from the backup.  A non-entitled device must
        // not have an imported Pro schedule re-enabled.
        let premium = Store.shared.premium
        for medication in medications {
            notificationManager.cancelAllMedicationReminders(
                notificationId: medication.notificationId)
            if Self.shouldUseProMedicationSchedule(
                deviceHasPremium: premium,
                proScheduleEnabled: medication.proScheduleEnabled,
                slotCount: medication.slots.count) {
                let notificationId = medication.notificationId
                let name = medication.name
                let slots = medication.slots
                let fallbackEnabled = medication.reminderEnabled
                let fallbackHour = medication.reminderHour
                let fallbackMinute = medication.reminderMinute
                Task { @MainActor in
                    let scheduled = await notificationManager.scheduleMedicationSlots(
                        notificationId: notificationId,
                        name: name,
                        slots: slots)
                    // A pending-notification cap or system scheduling error
                    // must not leave the medication silently unscheduled.
                    // Fall back to the free single reminder when Pro slots
                    // cannot all be installed; no entitlement is changed.
                    if !scheduled {
                        notificationManager.scheduleMedicationReminder(
                            id: notificationId,
                            name: name,
                            enabled: fallbackEnabled,
                            hour: fallbackHour,
                            minute: fallbackMinute)
                    }
                }
            } else {
                notificationManager.scheduleMedicationReminder(
                    id: medication.notificationId,
                    name: medication.name,
                    enabled: medication.reminderEnabled,
                    hour: medication.reminderHour,
                    minute: medication.reminderMinute)
            }
        }

        // Notification settings are local device policy, not backup payload.
        // Re-read the existing values after applying the small preference
        // whitelist so imported data is reflected without restoring any
        // permission or premium state.
        let dailyEnabled = defaults.bool(forKey: "notif.dailyEnabled")
        let dailyHour = defaults.object(forKey: "notif.dailyHour") as? Int ?? 21
        let periodEnabled = defaults.bool(forKey: "notif.periodEnabled")
        let prediction = CyclePredictor.predict(from: periods, manual: ManualCycle.current)
        notificationManager.scheduleDailyReminder(enabled: dailyEnabled, hour: dailyHour)
        notificationManager.schedulePeriodReminder(
            enabled: periodEnabled,
            advanceDays: premium ? ProReminderSettings.periodAdvanceDays : 2,
            nextPeriodStart: prediction.nextPeriodStart)
        notificationManager.schedulePMSReminder(
            enabled: premium && ProReminderSettings.pmsEnabled,
            nextPeriodStart: prediction.nextPeriodStart)
        notificationManager.scheduleSmartReminders(
            enabled: premium && ProReminderSettings.smartEnabled,
            prediction: prediction,
            logs: logs)
    }
}
