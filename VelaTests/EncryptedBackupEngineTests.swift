import Foundation
import XCTest
@testable import Vela

final class EncryptedBackupEngineTests: XCTestCase {
    private let password = "correct horse battery staple"
    private let createdAt = Date(timeIntervalSince1970: 1_755_000_000)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.calendar!.date(from: components)!
    }

    private func fixtureSnapshot() -> BackupSnapshot {
        let medicationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let customID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let created = date(2026, 8, 1)
        let updated = date(2026, 8, 2)
        return BackupSnapshot(
            periodDays: [
                BackupPeriodDayPayload(dayKey: 20260801,
                                       flowRaw: 3,
                                       createdAt: created,
                                       updatedAt: updated,
                                       importedFromHealth: true)
            ],
            dailyLogs: [
                BackupDailyLogPayload(dayKey: 20260801,
                                      moodRaw: 4,
                                      energy: 3,
                                      pain: 1,
                                      sleepHours: 7.5,
                                      weight: 60.2,
                                      steps: 12_345,
                                      exerciseMinutes: 42,
                                      basalBodyTemperatureCelsius: 36.6,
                                      spotting: true,
                                      healthImportedFields: ["basalBodyTemperature", "spotting", "steps", "exercise"],
                                      symptoms: ["cramps", "c:\(customID.uuidString)"],
                                      note: "A small, private note",
                                      updatedAt: updated)
            ],
            medications: [
                BackupMedicationPayload(id: medicationID,
                                        name: "Myo-inositol",
                                        emoji: "💊",
                                        reminderEnabled: true,
                                        reminderHour: 8,
                                        reminderMinute: 30,
                                        proScheduleEnabled: false,
                                        scheduleSlotsJSON: "[]",
                                        createdAt: created)
            ],
            medicationIntakes: [
                BackupMedicationIntakePayload(medicationId: medicationID,
                                              dayKey: 20260801,
                                              takenAt: updated)
            ],
            customSymptoms: [
                BackupCustomSymptomPayload(key: "c:\(customID.uuidString)",
                                           label: "Headache",
                                           emoji: "🫨",
                                           createdAt: created)
            ],
            preferences: BackupPreferences(theme: "teal",
                                           manualCycleEnabled: true,
                                           manualCycleLength: 32,
                                           manualPeriodLength: 6,
                                           hideSensitiveNotifications: true,
                                           lifeStageRaw: "perimenopause",
                                           contraception: BackupContraceptionPreference(
                                               methodRaw: "pill",
                                               startDayKey: 20260801,
                                               reminderEnabled: true,
                                               reminderHour: 8,
                                               reminderMinute: 15,
                                               note: "local note",
                                               updatedAt: updated)))
    }

    private func envelope(_ data: Data,
                          format: String? = nil,
                          schemaVersion: Int? = nil,
                          appIdentifier: String? = nil,
                          nonce: Data? = nil,
                          ciphertext: Data? = nil,
                          tag: Data? = nil) throws -> Data {
        let original = try EncryptedBackupEngine.decodeEnvelope(data)
        let changed = EncryptedBackupEnvelope(
            format: format ?? original.format,
            schemaVersion: schemaVersion ?? original.schemaVersion,
            appIdentifier: appIdentifier ?? original.appIdentifier,
            appVersion: original.appVersion,
            buildNumber: original.buildNumber,
            createdAt: original.createdAt,
            kdf: original.kdf,
            nonce: nonce ?? original.nonce,
            ciphertext: ciphertext ?? original.ciphertext,
            tag: tag ?? original.tag)
        return try EncryptedBackupEngine.encodeEnvelope(changed)
    }

    private func error(from work: () throws -> Void) -> EncryptedBackupError? {
        do {
            try work()
            return nil
        } catch let error as EncryptedBackupError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(error)")
            return nil
        }
    }

    func testRoundTripAndPreview() throws {
        let engine = EncryptedBackupEngine(configuration: .init(appIdentifier: "test.vela",
                                                               appVersion: "2.3.4",
                                                               buildNumber: "42"))
        let snapshot = fixtureSnapshot()
        let data = try engine.encrypt(snapshot, password: password, createdAt: createdAt)

        XCTAssertLessThan(data.count, BackupLimits.standard.maxEncryptedBytes)
        XCTAssertEqual(try engine.decrypt(data, password: password), snapshot)

        let preview = try engine.preview(data, password: password)
        XCTAssertEqual(preview.appIdentifier, "test.vela")
        XCTAssertEqual(preview.appVersion, "2.3.4")
        XCTAssertEqual(preview.buildNumber, "42")
        XCTAssertEqual(preview.schemaVersion, BackupSnapshot.currentSchemaVersion)
        XCTAssertEqual(preview.createdAt, createdAt)
        XCTAssertEqual(preview.counts,
                       BackupRecordCounts(periodDays: 1,
                                          dailyLogs: 1,
                                          medications: 1,
                                          medicationIntakes: 1,
                                          customSymptoms: 1))
    }

    func testWrongPasswordAndTamperingShareSafeError() throws {
        let engine = EncryptedBackupEngine()
        let data = try engine.encrypt(fixtureSnapshot(), password: password, createdAt: createdAt)
        let wrongPasswordError = error { _ = try engine.decrypt(data, password: "another valid password") }
        XCTAssertEqual(wrongPasswordError, .authenticationFailed)

        var ciphertext = try EncryptedBackupEngine.decodeEnvelope(data).ciphertext
        ciphertext[0] ^= 0x80
        let tamperedCiphertext = try envelope(data, ciphertext: ciphertext)
        XCTAssertEqual(error { _ = try engine.decrypt(tamperedCiphertext, password: password) },
                       .authenticationFailed)

        var tag = try EncryptedBackupEngine.decodeEnvelope(data).tag
        tag[0] ^= 0x01
        let tamperedTag = try envelope(data, tag: tag)
        XCTAssertEqual(error { _ = try engine.decrypt(tamperedTag, password: password) },
                       .authenticationFailed)

        let tamperedHeader = try envelope(data, appIdentifier: "another.app")
        XCTAssertEqual(error { _ = try engine.decrypt(tamperedHeader, password: password) },
                       .authenticationFailed)
    }

    func testUnsupportedFormatAndSchemaAreSeparateFromAuthentication() throws {
        let engine = EncryptedBackupEngine()
        let data = try engine.encrypt(fixtureSnapshot(), password: password, createdAt: createdAt)

        // Direct JSON edits are unauthenticated tampering, even when the
        // edited value is format/schema metadata.
        let tamperedFormat = try envelope(data, format: "other.backup")
        XCTAssertEqual(error { _ = try engine.decrypt(tamperedFormat, password: password) },
                       .authenticationFailed)

        let tamperedSchema = try envelope(data, schemaVersion: 999)
        XCTAssertEqual(error { _ = try engine.decrypt(tamperedSchema, password: password) },
                       .authenticationFailed)

#if DEBUG
        // A genuinely authenticated future/foreign envelope remains
        // distinguishable after GCM verification.
        let unsupportedFormat = try EncryptedBackupEngine.authenticatedEnvelopeForTesting(
            data, password: password, format: "other.backup")
        XCTAssertEqual(error { _ = try engine.decrypt(unsupportedFormat, password: password) },
                       .unsupportedFormat)

        let unsupportedSchema = try EncryptedBackupEngine.authenticatedEnvelopeForTesting(
            data, password: password, schemaVersion: 999)
        XCTAssertEqual(error { _ = try engine.decrypt(unsupportedSchema, password: password) },
                       .unsupportedSchema)
#endif
    }

    func testPasswordValidationAndConfirmationHelper() throws {
        XCTAssertThrowsError(try EncryptedBackupEngine.validatePassword("1234567")) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .passwordTooShort)
        }
        XCTAssertThrowsError(try EncryptedBackupEngine.validatePassword(password,
                                                                         confirmation: "different password")) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .passwordConfirmationMismatch)
        }
        XCTAssertTrue(EncryptedBackupEngine.passwordsMatch(password, password))
        XCTAssertFalse(EncryptedBackupEngine.passwordsMatch("short", "short"))
        XCTAssertTrue(EncryptedBackupEngine.isValidPassword(password, confirmation: password))
    }

    func testWhitelistExcludesPremiumHealthAndDevicePreferences() throws {
        let suiteName = "EncryptedBackupEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "store.premium")
        defaults.set(true, forKey: "health.syncEnabled")
        defaults.set(["menstrualFlow": true], forKey: "health.selectedTypes")
        defaults.set(true, forKey: "lock.enabled")
        defaults.set(true, forKey: "onboarding.done")
        defaults.set("violet", forKey: "theme")
        defaults.set(true, forKey: "cycle.manualEnabled")
        defaults.set(40, forKey: "cycle.manualCycleLength")
        defaults.set(7, forKey: "cycle.manualPeriodLength")
        defaults.set(true, forKey: "notif.hideSensitiveContent")
        LifeStage.save(.perimenopause, to: defaults)
        XCTAssertTrue(ContraceptionSettings(
            method: .pill,
            startDayKey: 20260801,
            reminderEnabled: true,
            reminderHour: 8,
            reminderMinute: 15,
            note: "local note",
            updatedAt: createdAt).save(to: defaults))

        let preferences = BackupPreferences.fromCurrentDeviceDefaults(defaults)
        XCTAssertEqual(preferences.theme, "violet")
        XCTAssertTrue(preferences.manualCycleEnabled)
        XCTAssertTrue(preferences.hideSensitiveNotifications)
        XCTAssertEqual(preferences.lifeStageRaw, "perimenopause")
        XCTAssertEqual(preferences.contraception?.methodRaw, "pill")
        XCTAssertEqual(preferences.contraception?.reminderHour, 8)
        let encoded = try JSONEncoder().encode(preferences)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("premium"))
        XCTAssertFalse(text.contains("health"))
        XCTAssertFalse(text.contains("lock"))
        XCTAssertFalse(text.contains("onboarding"))
        XCTAssertFalse(text.contains("effectiveness"))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testMergeRulesAndExplicitReplaceMode() throws {
        let currentDate = date(2026, 8, 1)
        let newer = date(2026, 8, 3)
        let older = date(2026, 7, 31)
        let existingMedicationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let newMedicationID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let customKey = "c:\(UUID(uuidString: "55555555-5555-4555-8555-555555555555")!.uuidString)"
        let current = BackupSnapshot(
            periodDays: [BackupPeriodDayPayload(dayKey: 20260801, flowRaw: 1,
                                                createdAt: currentDate, updatedAt: currentDate)],
            dailyLogs: [BackupDailyLogPayload(dayKey: 20260801, moodRaw: 2,
                                              updatedAt: currentDate)],
            medications: [BackupMedicationPayload(id: existingMedicationID, name: "Existing",
                                                  createdAt: currentDate)],
            medicationIntakes: [BackupMedicationIntakePayload(medicationId: existingMedicationID,
                                                               dayKey: 20260801,
                                                               takenAt: currentDate)],
            customSymptoms: [BackupCustomSymptomPayload(key: customKey, label: "Old", emoji: "🙂",
                                                        createdAt: currentDate)])
        let incoming = BackupSnapshot(
            periodDays: [BackupPeriodDayPayload(dayKey: 20260801, flowRaw: 3,
                                                createdAt: currentDate, updatedAt: newer),
                         BackupPeriodDayPayload(dayKey: 20260802, flowRaw: 2,
                                                createdAt: newer, updatedAt: newer)],
            dailyLogs: [BackupDailyLogPayload(dayKey: 20260801, moodRaw: 5,
                                              updatedAt: older),
                        BackupDailyLogPayload(dayKey: 20260802, moodRaw: 4,
                                              updatedAt: newer)],
            medications: [BackupMedicationPayload(id: existingMedicationID, name: "Incoming ignored",
                                                  createdAt: newer),
                          BackupMedicationPayload(id: newMedicationID, name: "New",
                                                  createdAt: newer)],
            medicationIntakes: [BackupMedicationIntakePayload(medicationId: existingMedicationID,
                                                               dayKey: 20260801,
                                                               takenAt: newer),
                                BackupMedicationIntakePayload(medicationId: existingMedicationID,
                                                               dayKey: 20260802,
                                                               takenAt: newer)],
            customSymptoms: [BackupCustomSymptomPayload(key: customKey, label: "Incoming ignored",
                                                        emoji: "😶", createdAt: newer),
                             BackupCustomSymptomPayload(key: "c:\(newMedicationID.uuidString)",
                                                        label: "New custom", emoji: "✨",
                                                        createdAt: newer)])

        let plan = BackupMergePlanner.plan(current: current, incoming: incoming)
        XCTAssertEqual(plan.mode, .merge)
        XCTAssertEqual(plan.periodDaysToUpdate.map(\.dayKey), [20260801])
        XCTAssertEqual(plan.periodDaysToInsert.map(\.dayKey), [20260802])
        XCTAssertTrue(plan.dailyLogsToUpdate.isEmpty, "older incoming daily log must not win")
        XCTAssertEqual(plan.dailyLogsToInsert.map(\.dayKey), [20260802])
        XCTAssertEqual(plan.medicationsToInsert.map(\.id), [newMedicationID])
        XCTAssertEqual(plan.medicationIntakesToInsert.map(\.dayKey), [20260802])
        XCTAssertEqual(plan.customSymptomsToInsert.count, 1)

        let replace = BackupMergePlanner.plan(current: current,
                                              incoming: incoming,
                                              mode: .replace)
        XCTAssertEqual(replace.mode, .replace)
        XCTAssertEqual(replace.periodDayKeysToDelete, [20260801])
        XCTAssertEqual(replace.dailyLogKeysToDelete, [20260801])
        XCTAssertEqual(replace.medicationIDsToDelete, [existingMedicationID])
        XCTAssertEqual(replace.intakeKeysToDelete.count, 1)
        XCTAssertEqual(replace.customSymptomKeysToDelete, [customKey])
        XCTAssertEqual(replace.periodDaysToInsert.count, 2)
        XCTAssertEqual(replace.dailyLogsToInsert.count, 2)
    }

    func testSnapshotFieldAndSizeValidation() throws {
        var invalid = fixtureSnapshot()
        invalid.periodDays[0].flowRaw = 99
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.dailyLogs[0].basalBodyTemperatureCelsius = 100
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.dailyLogs[0].healthImportedFields = ["not-a-health-field"]
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.preferences.lifeStageRaw = "unknown"
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.preferences.contraception = BackupContraceptionPreference(
            methodRaw: "iud",
            reminderEnabled: true,
            updatedAt: createdAt)
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.preferences.contraception = BackupContraceptionPreference(
            methodRaw: "pill",
            reminderHour: 24,
            updatedAt: createdAt)
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.preferences.contraception = BackupContraceptionPreference(
            methodRaw: "pill",
            startDayKey: 20260230,
            updatedAt: createdAt)
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.dailyLogs[0].steps = 200_001
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.dailyLogs[0].exerciseMinutes = 1_441
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        invalid.periodDays[0].dayKey = 20260230
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        invalid = fixtureSnapshot()
        let orphanMedicationID = UUID()
        invalid.medicationIntakes[0].medicationId = orphanMedicationID
        invalid.medicationIntakes[0].key = orphanMedicationID.uuidString + "-20260801"
        XCTAssertThrowsError(try invalid.validated()) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .invalidSnapshot)
        }

        var limits = BackupLimits.standard
        limits.maxEncryptedBytes = 64
        limits.maxPlaintextBytes = 64
        let tinyEngine = EncryptedBackupEngine(configuration: .init(limits: limits))
        XCTAssertThrowsError(try tinyEngine.encrypt(fixtureSnapshot(), password: password)) { error in
            XCTAssertEqual(error as? EncryptedBackupError, .inputTooLarge)
        }
    }

    func testMultilineNotesRoundTrip() throws {
        var snapshot = fixtureSnapshot()
        snapshot.dailyLogs[0].note = "first line\nsecond line\rthird line\twith a tab"
        let engine = EncryptedBackupEngine()
        let data = try engine.encrypt(snapshot, password: password, createdAt: createdAt)
        XCTAssertEqual(try engine.decrypt(data, password: password), snapshot)
    }

    func testDailyLogSnapshotCaptureIncludesStepsAndExercise() {
        let log = DailyLog(date: date(2026, 8, 1), steps: 1_234, exerciseMinutes: 25)
        XCTAssertTrue(log.hasContent)

        let snapshot = BackupSnapshot(periodDays: [],
                                      dailyLogs: [log],
                                      medications: [],
                                      medicationIntakes: [],
                                      customSymptoms: [])
        XCTAssertEqual(snapshot.dailyLogs.first?.steps, 1_234)
        XCTAssertEqual(snapshot.dailyLogs.first?.exerciseMinutes, 25)
    }

    func testOldDailyLogPayloadWithoutStepsOrExerciseStillDecodes() throws {
        struct LegacyDailyLogPayload: Codable {
            let dayKey: Int
            let moodRaw: Int
            let energy: Int
            let pain: Int
            let sleepHours: Double?
            let weight: Double?
            let basalBodyTemperatureCelsius: Double?
            let spotting: Bool?
            let healthImportedFields: [String]
            let symptoms: [String]
            let note: String
            let updatedAt: Date
        }
        let oldPayload = LegacyDailyLogPayload(
            dayKey: 20260801,
            moodRaw: 3,
            energy: 2,
            pain: 1,
            sleepHours: 7.0,
            weight: 60.0,
            basalBodyTemperatureCelsius: 36.5,
            spotting: false,
            healthImportedFields: ["sleep"],
            symptoms: [],
            note: "old",
            updatedAt: createdAt)
        let data = try JSONEncoder().encode(oldPayload)
        let decoded = try JSONDecoder().decode(BackupDailyLogPayload.self, from: data)

        XCTAssertNil(decoded.steps)
        XCTAssertNil(decoded.exerciseMinutes)
        XCTAssertEqual(decoded.dayKey, 20260801)
        XCTAssertEqual(decoded.note, "old")
    }

    func testOldBackupPreferencesWithoutNewKeysStillDecode() throws {
        struct LegacyPreferences: Codable {
            let theme: String?
            let manualCycleEnabled: Bool
            let manualCycleLength: Int
            let manualPeriodLength: Int
            let hideSensitiveNotifications: Bool
        }
        let old = LegacyPreferences(theme: "rose",
                                    manualCycleEnabled: true,
                                    manualCycleLength: 30,
                                    manualPeriodLength: 5,
                                    hideSensitiveNotifications: false)
        let data = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(BackupPreferences.self, from: data)

        XCTAssertEqual(decoded.theme, "rose")
        XCTAssertTrue(decoded.manualCycleEnabled)
        XCTAssertNil(decoded.lifeStageRaw)
        XCTAssertNil(decoded.contraception)
    }
}
