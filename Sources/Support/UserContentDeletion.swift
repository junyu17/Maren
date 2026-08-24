import Foundation
import SwiftData

enum DeletionError: LocalizedError {
    case healthKitSyncFailed(Error)
    case derivedRefreshFailed(Error)

    var errorDescription: String? {
        switch self {
        case .healthKitSyncFailed(let underlying):
            return underlying.localizedDescription
        case .derivedRefreshFailed(let underlying):
            return underlying.localizedDescription
        }
    }
}

enum UserContentDeletion {

    // MARK: - DailyLog

    @MainActor
    static func deleteDailyLog(
        _ log: DailyLog,
        context: ModelContext,
        notificationManager: NotificationManager,
        dailyEnabled: Bool,
        dailyHour: Int,
        periodEnabled: Bool,
        periodAdvanceDays: Int,
        smartEnabled: Bool,
        pmsEnabled: Bool,
        storePremium: Bool,
        manualCycle: ManualCycle
    ) async throws {
        let dayKey = log.dayKey
        context.delete(log)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        LocalDataChangeCenter.shared.post(
            kind: .dailyLogDeleted,
            affectedDayKeys: [dayKey]
        )

        do {
            _ = try refreshAfterMutation(
                context: context,
                notificationManager: notificationManager,
                dailyEnabled: dailyEnabled,
                dailyHour: dailyHour,
                periodEnabled: periodEnabled,
                periodAdvanceDays: periodAdvanceDays,
                smartEnabled: smartEnabled,
                pmsEnabled: pmsEnabled,
                storePremium: storePremium,
                manualCycle: manualCycle
            )
        } catch {
            // The local deletion is already durable and the change event has
            // been published. Surface a refresh failure instead of silently
            // leaving Widget/notification state stale.
            throw DeletionError.derivedRefreshFailed(error)
        }

        if HealthKitBridge.syncEnabled {
            let date = DayKey.date(from: dayKey)
            do {
                try await HealthKitBridge.deleteDailySamples(date)
            } catch {
                throw DeletionError.healthKitSyncFailed(error)
            }
        }
    }

    // MARK: - PeriodDay

    @MainActor
    static func deletePeriodDay(
        _ period: PeriodDay,
        context: ModelContext,
        notificationManager: NotificationManager,
        dailyEnabled: Bool,
        dailyHour: Int,
        periodEnabled: Bool,
        periodAdvanceDays: Int,
        smartEnabled: Bool,
        pmsEnabled: Bool,
        storePremium: Bool,
        manualCycle: ManualCycle
    ) async throws {
        let wasImportedFromHealth = period.importedFromHealth
        let dayKey = period.dayKey
        let date = DayKey.date(from: dayKey)

        context.delete(period)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        LocalDataChangeCenter.shared.post(
            kind: .periodDayDeleted,
            affectedDayKeys: [dayKey]
        )

        let actual: (periodDays: [PeriodDay], logs: [DailyLog])
        do {
            actual = try refreshAfterMutation(
                context: context,
                notificationManager: notificationManager,
                dailyEnabled: dailyEnabled,
                dailyHour: dailyHour,
                periodEnabled: periodEnabled,
                periodAdvanceDays: periodAdvanceDays,
                smartEnabled: smartEnabled,
                pmsEnabled: pmsEnabled,
                storePremium: storePremium,
                manualCycle: manualCycle
            )
        } catch {
            throw DeletionError.derivedRefreshFailed(error)
        }

        if HealthKitBridge.syncEnabled,
           HealthKitBridge.selectedTypes.contains(.menstrualFlow),
           !wasImportedFromHealth {
            let localDays = actual.periodDays
                .filter { !$0.importedFromHealth }
                .sorted { $0.dayKey < $1.dayKey }
            let resyncKeys = HealthKitPlanners.periodDayKeysToResync(
                afterChanging: dayKey,
                existingDayKeys: localDays.map(\.dayKey),
                deleting: true
            )
            let startFlags = HealthKitPlanners.cycleStartFlags(
                for: localDays.map(\.dayKey),
                calendar: Cal.gregorian
            )
            let writes: [HealthKitBridge.PeriodWriteSnapshot] = resyncKeys.compactMap { key -> HealthKitBridge.PeriodWriteSnapshot? in
                guard let next = localDays.first(where: { $0.dayKey == key }) else { return nil }
                return HealthKitBridge.PeriodWriteSnapshot(
                    date: next.date,
                    flowRaw: next.flowRaw,
                    isCycleStart: startFlags[key] ?? true
                )
            }
            do {
                try await HealthKitBridge.syncPeriodRevision(
                    deleteDate: date,
                    writes: writes
                )
            } catch {
                throw DeletionError.healthKitSyncFailed(error)
            }
        }
    }

    // MARK: - MedicationIntake

    @MainActor
    static func deleteMedicationIntake(
        _ intake: MedicationIntake,
        context: ModelContext
    ) throws {
        let dayKey = intake.dayKey
        context.delete(intake)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        LocalDataChangeCenter.shared.post(
            kind: .medicationIntakeDeleted,
            affectedDayKeys: [dayKey]
        )
    }

    // MARK: - Custom tracker cascade

    /// Deletes a custom tracker and removes its key from every DailyLog.symptoms
    /// that references it, all in one transaction.
    @MainActor
    static func deleteCustomTracker(
        _ tracker: CustomSymptom,
        context: ModelContext,
        notificationManager: NotificationManager,
        dailyEnabled: Bool,
        dailyHour: Int,
        periodEnabled: Bool,
        periodAdvanceDays: Int,
        smartEnabled: Bool,
        pmsEnabled: Bool,
        storePremium: Bool,
        manualCycle: ManualCycle
    ) throws {
        let trackerKey = tracker.key

        // 1. Remove key from all DailyLog.symptoms
        let allLogs = try context.fetch(FetchDescriptor<DailyLog>())
        for log in allLogs where log.symptoms.contains(trackerKey) {
            log.symptoms = log.symptoms.filter { $0 != trackerKey }
            log.updatedAt = Date()
        }

        // 2. Delete the definition
        context.delete(tracker)

        // 3. Save once
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        // 4. Notify editors immediately after the durable model change. This
        // also removes the key from a dirty DailyLog draft before any slower
        // derived refresh work runs.
        LocalDataChangeCenter.shared.post(
            kind: .customTrackerDeleted,
            removedCustomTrackerKeys: [trackerKey]
        )

        // 5. Refresh derived state
        CustomSymptomStore.refresh(context)
        do {
            _ = try refreshAfterMutation(
                context: context,
                notificationManager: notificationManager,
                dailyEnabled: dailyEnabled,
                dailyHour: dailyHour,
                periodEnabled: periodEnabled,
                periodAdvanceDays: periodAdvanceDays,
                smartEnabled: smartEnabled,
                pmsEnabled: pmsEnabled,
                storePremium: storePremium,
                manualCycle: manualCycle
            )
        } catch {
            throw DeletionError.derivedRefreshFailed(error)
        }

    }

    // MARK: - Medication cascade

    /// Updates a custom tracker in place. The logical key is intentionally
    /// never regenerated, so every historical DailyLog.symptoms reference
    /// continues to point at the renamed tracker.
    @MainActor
    static func updateCustomTracker(
        _ tracker: CustomSymptom,
        label: String,
        emoji: String,
        context: ModelContext
    ) throws {
        tracker.label = label
        tracker.emoji = emoji
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        CustomSymptomStore.refresh(context)
        LocalDataChangeCenter.shared.post(kind: .customTrackerChanged)
    }

    /// Deletes a medication and all its intakes in one transaction, then
    /// cancels notifications.
    @MainActor
    static func deleteMedication(
        _ med: Medication,
        context: ModelContext,
        notificationManager: NotificationManager
    ) throws {
        let medId = med.id
        let intakes = try context.fetch(
            FetchDescriptor<MedicationIntake>(
            predicate: #Predicate { $0.medicationId == medId }
        ))
        let affectedDayKeys = Set(intakes.map(\.dayKey))
        let notificationID = med.notificationId
        for intake in intakes { context.delete(intake) }
        context.delete(med)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        notificationManager.cancelAllMedicationReminders(notificationId: notificationID)
        LocalDataChangeCenter.shared.post(
            kind: .medicationDeleted,
            affectedDayKeys: affectedDayKeys
        )
    }

    // MARK: - Shared refresh helper

    @MainActor
    static func refreshAfterMutation(
        context: ModelContext,
        notificationManager: NotificationManager,
        dailyEnabled: Bool,
        dailyHour: Int,
        periodEnabled: Bool,
        periodAdvanceDays: Int,
        smartEnabled: Bool,
        pmsEnabled: Bool,
        storePremium: Bool,
        manualCycle: ManualCycle
    ) throws -> (periodDays: [PeriodDay], logs: [DailyLog]) {
        let actual = try fetchRemaining(context: context)
        WidgetSync.refresh(periodDays: actual.periodDays, logs: actual.logs)
        rescheduleReminders(
            notificationManager: notificationManager,
            periodDays: actual.periodDays,
            logs: actual.logs,
            dailyEnabled: dailyEnabled,
            dailyHour: dailyHour,
            periodEnabled: periodEnabled,
            periodAdvanceDays: periodAdvanceDays,
            smartEnabled: smartEnabled,
            pmsEnabled: pmsEnabled,
            storePremium: storePremium,
            manualCycle: manualCycle
        )
        return actual
    }

    /// Best-effort HealthKit write-back for quick actions received from a
    /// Widget or Apple Watch.  Local SwiftData is already durable before this
    /// is called; a HealthKit failure must never roll it back.
    @MainActor
    @discardableResult
    static func syncQuickLogHealthBestEffort(
        affectedDayKeys: Set<Int>,
        periodDays: [PeriodDay],
        logs: [DailyLog]
    ) async -> [Error] {
        guard HealthKitBridge.syncEnabled, !affectedDayKeys.isEmpty else { return [] }

        var errors: [Error] = []
        let localPeriods = periodDays
            .filter { affectedDayKeys.contains($0.dayKey) && !$0.importedFromHealth }
            .sorted { $0.dayKey < $1.dayKey }
        let startFlags = HealthKitPlanners.cycleStartFlags(
            for: periodDays.filter { !$0.importedFromHealth }.map(\.dayKey),
            calendar: Cal.gregorian
        )
        let periodWrites = localPeriods.map { period in
            HealthKitBridge.PeriodWriteSnapshot(
                date: period.date,
                flowRaw: period.flowRaw,
                isCycleStart: startFlags[period.dayKey] ?? true
            )
        }
        if !periodWrites.isEmpty {
            do {
                try await HealthKitBridge.syncPeriodRevision(
                    deleteDate: nil,
                    writes: periodWrites
                )
            } catch {
                errors.append(error)
            }
        }

        for log in logs where affectedDayKeys.contains(log.dayKey) {
            do {
                try await HealthKitBridge.syncDailyLog(log)
            } catch {
                errors.append(error)
            }
        }
        return errors
    }

    static func fetchRemaining(context: ModelContext) throws -> (periodDays: [PeriodDay], logs: [DailyLog]) {
        let periodDays = try context.fetch(
            FetchDescriptor<PeriodDay>(sortBy: [SortDescriptor(\PeriodDay.dayKey, order: .reverse)])
        )
        let logs = try context.fetch(
            FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\DailyLog.dayKey, order: .reverse)])
        )
        return (periodDays, logs)
    }

    @MainActor
    static func rescheduleReminders(
        notificationManager: NotificationManager,
        periodDays: [PeriodDay],
        logs: [DailyLog],
        dailyEnabled: Bool,
        dailyHour: Int,
        periodEnabled: Bool,
        periodAdvanceDays: Int,
        smartEnabled: Bool,
        pmsEnabled: Bool,
        storePremium: Bool,
        manualCycle: ManualCycle
    ) {
        let prediction = CyclePredictor.predict(from: periodDays, manual: manualCycle)
        notificationManager.scheduleDailyReminder(enabled: dailyEnabled, hour: dailyHour)
        let advance = storePremium ? periodAdvanceDays : 2
        notificationManager.schedulePeriodReminder(enabled: periodEnabled, advanceDays: advance, nextPeriodStart: prediction.nextPeriodStart)
        notificationManager.schedulePMSReminder(enabled: storePremium && pmsEnabled, nextPeriodStart: prediction.nextPeriodStart)
        notificationManager.scheduleSmartReminders(enabled: storePremium && smartEnabled, prediction: prediction, logs: logs)
    }
}
