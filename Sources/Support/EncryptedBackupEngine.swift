import Foundation
import CryptoKit

#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Errors exposed by the encrypted-backup boundary.
///
/// In particular, `authenticationFailed` intentionally covers an incorrect
/// password, a modified header, ciphertext, nonce, salt, or authentication
/// tag.  Callers can therefore show one safe message without revealing which
/// part of a backup was wrong.
public enum EncryptedBackupError: Error, LocalizedError, Equatable {
    case passwordTooShort
    case passwordConfirmationMismatch
    case inputTooLarge
    case unsupportedFormat
    case unsupportedSchema
    case authenticationFailed
    case invalidSnapshot
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "The backup password must contain at least 8 characters."
        case .passwordConfirmationMismatch:
            return "The backup passwords do not match."
        case .inputTooLarge:
            return "This backup is larger than the supported limit."
        case .unsupportedFormat:
            return "This file is not a supported Maren backup."
        case .unsupportedSchema:
            return "This backup was created by an unsupported schema version."
        case .authenticationFailed:
            return "The backup could not be authenticated or decrypted."
        case .invalidSnapshot:
            return "The backup contains invalid record data."
        case .invalidConfiguration:
            return "The backup encryption configuration is invalid."
        }
    }
}

/// Short alias for callers that prefer `BackupError` in integration code.
public typealias BackupError = EncryptedBackupError

// MARK: - Limits and preferences

/// Resource limits applied before and after decoding an encrypted backup.
///
/// The limits are intentionally finite even though an encrypted file is
/// authenticated.  This keeps malformed or imported files from consuming an
/// unreasonable amount of memory while being decoded.
public struct BackupLimits: Codable, Equatable, Sendable {
    public var maxEncryptedBytes: Int
    public var maxPlaintextBytes: Int
    public var maxPeriodDays: Int
    public var maxDailyLogs: Int
    public var maxMedications: Int
    public var maxMedicationIntakes: Int
    public var maxCustomSymptoms: Int
    public var maxSymptomsPerLog: Int
    public var maxHealthImportedFieldsPerLog: Int
    public var maxStringLength: Int
    public var maxScheduleSlotsJSONLength: Int

    public static let standard = BackupLimits(
        maxEncryptedBytes: 32 * 1024 * 1024,
        maxPlaintextBytes: 24 * 1024 * 1024,
        maxPeriodDays: 100_000,
        maxDailyLogs: 100_000,
        maxMedications: 10_000,
        maxMedicationIntakes: 500_000,
        maxCustomSymptoms: 10_000,
        maxSymptomsPerLog: 256,
        maxHealthImportedFieldsPerLog: 16,
        maxStringLength: 8_192,
        maxScheduleSlotsJSONLength: 64 * 1024
    )

    public init(maxEncryptedBytes: Int,
                maxPlaintextBytes: Int,
                maxPeriodDays: Int,
                maxDailyLogs: Int,
                maxMedications: Int,
                maxMedicationIntakes: Int,
                maxCustomSymptoms: Int,
                maxSymptomsPerLog: Int,
                maxHealthImportedFieldsPerLog: Int,
                maxStringLength: Int,
                maxScheduleSlotsJSONLength: Int) {
        self.maxEncryptedBytes = maxEncryptedBytes
        self.maxPlaintextBytes = maxPlaintextBytes
        self.maxPeriodDays = maxPeriodDays
        self.maxDailyLogs = maxDailyLogs
        self.maxMedications = maxMedications
        self.maxMedicationIntakes = maxMedicationIntakes
        self.maxCustomSymptoms = maxCustomSymptoms
        self.maxSymptomsPerLog = maxSymptomsPerLog
        self.maxHealthImportedFieldsPerLog = maxHealthImportedFieldsPerLog
        self.maxStringLength = maxStringLength
        self.maxScheduleSlotsJSONLength = maxScheduleSlotsJSONLength
    }

    public init() {
        self = .standard
    }
}

/// Public, model-independent contraception preference payload. It intentionally
/// contains no effectiveness or other medical claims.
public struct BackupContraceptionPreference: Codable, Equatable, Sendable {
    public var methodRaw: String
    public var startDayKey: Int?
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int
    public var note: String
    public var updatedAt: Date

    public init(methodRaw: String = "none",
                startDayKey: Int? = nil,
                reminderEnabled: Bool = false,
                reminderHour: Int = 9,
                reminderMinute: Int = 0,
                note: String = "",
                updatedAt: Date = Date()) {
        self.methodRaw = methodRaw
        self.startDayKey = startDayKey
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.note = note
        self.updatedAt = updatedAt
    }

    init(profile: ContraceptionSettings) {
        let snapshot = profile.snapshot
        self.init(methodRaw: snapshot.method.rawValue,
                  startDayKey: snapshot.startDayKey,
                  reminderEnabled: snapshot.reminderEnabled,
                  reminderHour: snapshot.reminderHour,
                  reminderMinute: snapshot.reminderMinute,
                  note: snapshot.note,
                  updatedAt: snapshot.updatedAt)
    }
}

/// The deliberately small set of UserDefaults values that may travel with a
/// backup.  This type is a whitelist: adding a new preference should be an
/// explicit source-code decision rather than an accidental UserDefaults dump.
///
/// It excludes StoreKit entitlement state, HealthKit authorization/sync/type
/// selections, lock/Face ID/device permissions, onboarding state, and all
/// notification authorization state.
public struct BackupPreferences: Codable, Equatable, Sendable {
    public var theme: String?
    public var manualCycleEnabled: Bool
    public var manualCycleLength: Int
    public var manualPeriodLength: Int
    public var hideSensitiveNotifications: Bool
    public var lifeStageRaw: String?
    public var contraception: BackupContraceptionPreference?

    public init(theme: String? = nil,
                manualCycleEnabled: Bool = false,
                manualCycleLength: Int = 28,
                manualPeriodLength: Int = 5,
                hideSensitiveNotifications: Bool = false,
                lifeStageRaw: String? = nil,
                contraception: BackupContraceptionPreference? = nil) {
        self.theme = theme
        self.manualCycleEnabled = manualCycleEnabled
        self.manualCycleLength = manualCycleLength
        self.manualPeriodLength = manualPeriodLength
        self.hideSensitiveNotifications = hideSensitiveNotifications
        self.lifeStageRaw = lifeStageRaw
        self.contraception = contraception
    }

    /// Captures only the keys in this type's whitelist.  It deliberately does
    /// not enumerate the defaults domain, which could silently include a new
    /// sensitive or device-specific key in a future app version.
    public static func fromCurrentDeviceDefaults(_ defaults: UserDefaults = .standard) -> BackupPreferences {
        let theme = defaults.string(forKey: "theme")
        let enabled = defaults.object(forKey: "cycle.manualEnabled") as? Bool ?? false
        let cycleLength = defaults.object(forKey: "cycle.manualCycleLength") as? Int ?? 28
        let periodLength = defaults.object(forKey: "cycle.manualPeriodLength") as? Int ?? 5
        let hideSensitive = defaults.object(forKey: "notif.hideSensitiveContent") as? Bool ?? false
        let lifeStageRaw = defaults.string(forKey: LifeStage.userDefaultsKey)
        let contraception = BackupContraceptionPreference(
            profile: ContraceptionSettings.load(from: defaults))
        return BackupPreferences(theme: theme,
                                 manualCycleEnabled: enabled,
                                 manualCycleLength: cycleLength,
                                 manualPeriodLength: periodLength,
                                 hideSensitiveNotifications: hideSensitive,
                                 lifeStageRaw: lifeStageRaw,
                                 contraception: contraception)
    }
}

// MARK: - Pure backup payloads

public struct BackupPeriodDayPayload: Codable, Equatable, Sendable {
    public var dayKey: Int
    public var flowRaw: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var importedFromHealth: Bool

    public init(dayKey: Int,
                flowRaw: Int = 2,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                importedFromHealth: Bool = false) {
        self.dayKey = dayKey
        self.flowRaw = flowRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.importedFromHealth = importedFromHealth
    }
}

public struct BackupDailyLogPayload: Codable, Equatable, Sendable {
    public var dayKey: Int
    public var moodRaw: Int
    public var energy: Int
    public var pain: Int
    public var sleepHours: Double?
    public var weight: Double?
    public var steps: Int?
    public var exerciseMinutes: Int?
    public var basalBodyTemperatureCelsius: Double?
    public var spotting: Bool?
    public var healthImportedFields: [String]
    public var symptoms: [String]
    public var note: String
    public var updatedAt: Date

    public init(dayKey: Int,
                moodRaw: Int = 0,
                energy: Int = 0,
                pain: Int = -1,
                sleepHours: Double? = nil,
                weight: Double? = nil,
                steps: Int? = nil,
                exerciseMinutes: Int? = nil,
                basalBodyTemperatureCelsius: Double? = nil,
                spotting: Bool? = nil,
                healthImportedFields: [String] = [],
                symptoms: [String] = [],
                note: String = "",
                updatedAt: Date = Date()) {
        self.dayKey = dayKey
        self.moodRaw = moodRaw
        self.energy = energy
        self.pain = pain
        self.sleepHours = sleepHours
        self.weight = weight
        self.steps = steps
        self.exerciseMinutes = exerciseMinutes
        self.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
        self.spotting = spotting
        self.healthImportedFields = healthImportedFields
        self.symptoms = symptoms
        self.note = note
        self.updatedAt = updatedAt
    }
}

public struct BackupMedicationPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var reminderEnabled: Bool
    public var reminderHour: Int
    public var reminderMinute: Int
    public var proScheduleEnabled: Bool
    public var scheduleSlotsJSON: String
    public var createdAt: Date

    public init(id: UUID = UUID(),
                name: String = "",
                emoji: String = "💊",
                reminderEnabled: Bool = false,
                reminderHour: Int = 9,
                reminderMinute: Int = 0,
                proScheduleEnabled: Bool = false,
                scheduleSlotsJSON: String = "[]",
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.proScheduleEnabled = proScheduleEnabled
        self.scheduleSlotsJSON = scheduleSlotsJSON
        self.createdAt = createdAt
    }
}

public struct BackupMedicationIntakePayload: Codable, Equatable, Sendable {
    public var key: String
    public var medicationId: UUID
    public var dayKey: Int
    public var takenAt: Date

    public init(key: String? = nil,
                medicationId: UUID,
                dayKey: Int,
                takenAt: Date = Date()) {
        self.key = key ?? "\(medicationId.uuidString)-\(dayKey)"
        self.medicationId = medicationId
        self.dayKey = dayKey
        self.takenAt = takenAt
    }
}

public struct BackupCustomSymptomPayload: Codable, Equatable, Sendable {
    public var key: String
    public var label: String
    public var emoji: String
    public var createdAt: Date

    public init(key: String,
                label: String,
                emoji: String,
                createdAt: Date = Date()) {
        self.key = key
        self.label = label
        self.emoji = emoji
        self.createdAt = createdAt
    }
}

public typealias PeriodDayPayload = BackupPeriodDayPayload
public typealias DailyLogPayload = BackupDailyLogPayload
public typealias MedicationPayload = BackupMedicationPayload
public typealias MedicationIntakePayload = BackupMedicationIntakePayload
public typealias CustomSymptomPayload = BackupCustomSymptomPayload

/// A complete, model-independent snapshot of the five SwiftData collections.
public struct BackupSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var periodDays: [BackupPeriodDayPayload]
    public var dailyLogs: [BackupDailyLogPayload]
    public var medications: [BackupMedicationPayload]
    public var medicationIntakes: [BackupMedicationIntakePayload]
    public var customSymptoms: [BackupCustomSymptomPayload]
    public var preferences: BackupPreferences

    public init(schemaVersion: Int = BackupSnapshot.currentSchemaVersion,
                periodDays: [BackupPeriodDayPayload] = [],
                dailyLogs: [BackupDailyLogPayload] = [],
                medications: [BackupMedicationPayload] = [],
                medicationIntakes: [BackupMedicationIntakePayload] = [],
                customSymptoms: [BackupCustomSymptomPayload] = [],
                preferences: BackupPreferences = BackupPreferences()) {
        self.schemaVersion = schemaVersion
        self.periodDays = periodDays
        self.dailyLogs = dailyLogs
        self.medications = medications
        self.medicationIntakes = medicationIntakes
        self.customSymptoms = customSymptoms
        self.preferences = preferences
    }

    public var counts: BackupRecordCounts {
        BackupRecordCounts(periodDays: periodDays.count,
                           dailyLogs: dailyLogs.count,
                           medications: medications.count,
                           medicationIntakes: medicationIntakes.count,
                           customSymptoms: customSymptoms.count)
    }

    /// Validates a snapshot before it is encoded or applied by an importer.
    @discardableResult
    public func validated(using limits: BackupLimits = .standard) throws -> BackupSnapshot {
        try BackupSnapshotValidator.validate(self, limits: limits)
        return self
    }
}

/// Counts shown by a backup preview and merge confirmation UI.
public struct BackupRecordCounts: Codable, Equatable, Sendable {
    public let periodDays: Int
    public let dailyLogs: Int
    public let medications: Int
    public let medicationIntakes: Int
    public let customSymptoms: Int

    public init(periodDays: Int,
                dailyLogs: Int,
                medications: Int,
                medicationIntakes: Int,
                customSymptoms: Int) {
        self.periodDays = periodDays
        self.dailyLogs = dailyLogs
        self.medications = medications
        self.medicationIntakes = medicationIntakes
        self.customSymptoms = customSymptoms
    }

    public var total: Int {
        periodDays + dailyLogs + medications + medicationIntakes + customSymptoms
    }
}

// MARK: - Versioned encrypted envelope

public struct BackupKDFParameters: Codable, Equatable, Sendable {
    public let algorithm: String
    public let salt: Data
    public let iterations: Int
    public let keyLength: Int

    public init(algorithm: String = "PBKDF2-HMAC-SHA256",
                salt: Data,
                iterations: Int,
                keyLength: Int = 32) {
        self.algorithm = algorithm
        self.salt = salt
        self.iterations = iterations
        self.keyLength = keyLength
    }
}

/// Codable outer envelope.  `ciphertext` and `tag` are separate to make the
/// format easy to inspect and migrate while the complete header is included
/// in AES-GCM associated data.
public struct EncryptedBackupEnvelope: Codable, Equatable, Sendable {
    public static let formatIdentifier = "cd.cc.vela.encrypted-backup"
    public static let currentSchemaVersion = 1

    public let format: String
    public let schemaVersion: Int
    public let appIdentifier: String
    public let appVersion: String
    public let buildNumber: String
    public let createdAt: Date
    public let kdf: BackupKDFParameters
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data

    public init(format: String = EncryptedBackupEnvelope.formatIdentifier,
                schemaVersion: Int = EncryptedBackupEnvelope.currentSchemaVersion,
                appIdentifier: String,
                appVersion: String = "unknown",
                buildNumber: String = "unknown",
                createdAt: Date,
                kdf: BackupKDFParameters,
                nonce: Data,
                ciphertext: Data,
                tag: Data) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.appIdentifier = appIdentifier
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.createdAt = createdAt
        self.kdf = kdf
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public struct BackupPreview: Codable, Equatable, Sendable {
    public let appIdentifier: String
    public let appVersion: String
    public let buildNumber: String
    public let schemaVersion: Int
    public let createdAt: Date
    public let counts: BackupRecordCounts

    public init(appIdentifier: String,
                appVersion: String = "unknown",
                buildNumber: String = "unknown",
                schemaVersion: Int,
                createdAt: Date,
                counts: BackupRecordCounts) {
        self.appIdentifier = appIdentifier
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.counts = counts
    }
}

public struct DecryptedBackup: Equatable, Sendable {
    public let snapshot: BackupSnapshot
    public let preview: BackupPreview

    public init(snapshot: BackupSnapshot, preview: BackupPreview) {
        self.snapshot = snapshot
        self.preview = preview
    }
}

// MARK: - Engine

public struct EncryptedBackupEngine: Sendable {
    public static let minimumPasswordLength = 8
    public static let minimumPBKDF2Iterations = 210_000
    public static let maximumPBKDF2Iterations = 1_000_000
    public static let saltLength = 16
    public static let nonceLength = 12
    public static let keyLength = 32
    public static let authenticationTagLength = 16

    public struct Configuration: Equatable, Sendable {
        public var appIdentifier: String
        public var appVersion: String
        public var buildNumber: String
        public var iterations: Int
        public var limits: BackupLimits

        public init(appIdentifier: String = "cd.cc.vela",
                    appVersion: String? = nil,
                    buildNumber: String? = nil,
                    iterations: Int = EncryptedBackupEngine.minimumPBKDF2Iterations,
                    limits: BackupLimits = .standard) {
            self.appIdentifier = appIdentifier
            self.appVersion = appVersion
                ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                ?? "unknown"
            self.buildNumber = buildNumber
                ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                ?? "unknown"
            self.iterations = iterations
            self.limits = limits
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Password validation helper for save/import forms.  The password is
    /// never retained by the engine; it exists only for the duration of this
    /// call or an encryption/decryption operation.
    public static func validatePassword(_ password: String,
                                        confirmation: String? = nil) throws {
        guard password.count >= minimumPasswordLength else {
            throw EncryptedBackupError.passwordTooShort
        }
        guard password.utf8.count <= 4 * 1024 else {
            throw EncryptedBackupError.inputTooLarge
        }
        if let confirmation, password != confirmation {
            throw EncryptedBackupError.passwordConfirmationMismatch
        }
    }

    public static func passwordsMatch(_ password: String, _ confirmation: String) -> Bool {
        password == confirmation && password.count >= minimumPasswordLength
    }

    public static func isValidPassword(_ password: String, confirmation: String? = nil) -> Bool {
        (try? validatePassword(password, confirmation: confirmation)) != nil
    }

    /// Encodes a validated snapshot into an authenticated AES-GCM envelope.
    public func encrypt(_ snapshot: BackupSnapshot,
                        password: String,
                        createdAt: Date = Date()) throws -> Data {
        try validateConfiguration()
        try Self.validatePassword(password)
        try snapshot.validated(using: configuration.limits)

        let plaintext = try Self.makeJSONEncoder().encode(snapshot)
        guard plaintext.count <= configuration.limits.maxPlaintextBytes else {
            throw EncryptedBackupError.inputTooLarge
        }

        let salt = Self.randomData(count: Self.saltLength)
        let nonceData = Self.randomData(count: Self.nonceLength)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let key = try Self.deriveKey(password: password, salt: salt,
                                     iterations: configuration.iterations)
        let canonicalCreatedAt = Self.canonicalDate(createdAt)
        let kdf = BackupKDFParameters(salt: salt,
                                      iterations: configuration.iterations,
                                      keyLength: Self.keyLength)
        let header = EncryptedBackupEnvelope(
            appIdentifier: configuration.appIdentifier,
            appVersion: configuration.appVersion,
            buildNumber: configuration.buildNumber,
            createdAt: canonicalCreatedAt,
            kdf: kdf,
            nonce: nonceData,
            ciphertext: Data(),
            tag: Data())
        let aad = try Self.authenticatedHeaderData(for: header)
        let sealed = try AES.GCM.seal(plaintext,
                                      using: SymmetricKey(data: key),
                                      nonce: nonce,
                                      authenticating: aad)
        let envelope = EncryptedBackupEnvelope(
            format: header.format,
            schemaVersion: header.schemaVersion,
            appIdentifier: header.appIdentifier,
            appVersion: header.appVersion,
            buildNumber: header.buildNumber,
            createdAt: header.createdAt,
            kdf: header.kdf,
            nonce: header.nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag)
        let encoded = try Self.makeJSONEncoder().encode(envelope)
        guard encoded.count <= configuration.limits.maxEncryptedBytes else {
            throw EncryptedBackupError.inputTooLarge
        }
        return encoded
    }

    /// Decrypts and validates a snapshot.  For callers that also need
    /// metadata/counts, use `decryptDocument` or `preview`.
    public func decrypt(_ data: Data, password: String) throws -> BackupSnapshot {
        try decryptDocument(data, password: password).snapshot
    }

    public func decryptDocument(_ data: Data, password: String) throws -> DecryptedBackup {
        try validateConfiguration()
        try Self.validatePassword(password)
        guard data.count <= configuration.limits.maxEncryptedBytes else {
            throw EncryptedBackupError.inputTooLarge
        }

        // A malformed or truncated encrypted document is treated as an
        // authentication failure.  This keeps wrong-password and tamper paths
        // indistinguishable to the public API.  Format/schema are deliberately
        // not inspected until after AES-GCM has authenticated the full header.
        let envelope: EncryptedBackupEnvelope
        do {
            envelope = try Self.makeJSONDecoder().decode(EncryptedBackupEnvelope.self, from: data)
        } catch {
            throw EncryptedBackupError.authenticationFailed
        }

        do {
            try Self.validateEnvelopeHeader(envelope, limits: configuration.limits)
            let key = try Self.deriveKey(password: password,
                                         salt: envelope.kdf.salt,
                                         iterations: envelope.kdf.iterations)
            let nonce = try AES.GCM.Nonce(data: envelope.nonce)
            let sealed = try AES.GCM.SealedBox(nonce: nonce,
                                               ciphertext: envelope.ciphertext,
                                               tag: envelope.tag)
            let aad = try Self.authenticatedHeaderData(for: envelope)
            let plaintext = try AES.GCM.open(sealed,
                                             using: SymmetricKey(data: key),
                                             authenticating: aad)
            guard plaintext.count <= configuration.limits.maxPlaintextBytes else {
                throw EncryptedBackupError.inputTooLarge
            }

            // These values are authenticated header fields.  Only now can we
            // safely distinguish a genuinely signed future/foreign envelope
            // from a caller who merely changed JSON bytes in an existing one.
            guard envelope.format == EncryptedBackupEnvelope.formatIdentifier else {
                throw EncryptedBackupError.unsupportedFormat
            }
            guard envelope.schemaVersion == EncryptedBackupEnvelope.currentSchemaVersion else {
                throw EncryptedBackupError.unsupportedSchema
            }

            let snapshot = try Self.makeJSONDecoder().decode(BackupSnapshot.self, from: plaintext)
            guard snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion else {
                throw EncryptedBackupError.unsupportedSchema
            }
            do {
                try snapshot.validated(using: configuration.limits)
            } catch {
                throw EncryptedBackupError.authenticationFailed
            }

            let preview = BackupPreview(appIdentifier: envelope.appIdentifier,
                                        appVersion: envelope.appVersion,
                                        buildNumber: envelope.buildNumber,
                                        schemaVersion: snapshot.schemaVersion,
                                        createdAt: envelope.createdAt,
                                        counts: snapshot.counts)
            return DecryptedBackup(snapshot: snapshot, preview: preview)
        } catch let error as EncryptedBackupError {
            // Schema and size are meaningful after successful authentication;
            // all cryptographic/field failures use the same safe error.
            switch error {
            case .unsupportedFormat, .unsupportedSchema, .inputTooLarge:
                throw error
            default:
                throw EncryptedBackupError.authenticationFailed
            }
        } catch {
            throw EncryptedBackupError.authenticationFailed
        }
    }

    public func preview(_ data: Data, password: String) throws -> BackupPreview {
        try decryptDocument(data, password: password).preview
    }

    /// Test/integration helper for inspecting or deliberately mutating an
    /// envelope.  It performs the same size and format/schema checks as import
    /// but never decrypts or exposes plaintext.
    public static func decodeEnvelope(_ data: Data,
                                      limits: BackupLimits = .standard) throws -> EncryptedBackupEnvelope {
        guard data.count <= limits.maxEncryptedBytes else {
            throw EncryptedBackupError.inputTooLarge
        }
        let envelope: EncryptedBackupEnvelope
        do {
            envelope = try makeJSONDecoder().decode(EncryptedBackupEnvelope.self, from: data)
        } catch {
            throw EncryptedBackupError.unsupportedFormat
        }
        guard envelope.format == EncryptedBackupEnvelope.formatIdentifier else {
            throw EncryptedBackupError.unsupportedFormat
        }
        guard envelope.schemaVersion == EncryptedBackupEnvelope.currentSchemaVersion else {
            throw EncryptedBackupError.unsupportedSchema
        }
        return envelope
    }

    public static func encodeEnvelope(_ envelope: EncryptedBackupEnvelope,
                                      limits: BackupLimits = .standard) throws -> Data {
        let data = try makeJSONEncoder().encode(envelope)
        guard data.count <= limits.maxEncryptedBytes else {
            throw EncryptedBackupError.inputTooLarge
        }
        return data
    }

#if DEBUG
    /// Re-seals an envelope after changing authenticated header fields.  This
    /// is test-only so tests can cover the post-authentication unsupported
    /// format/schema branch without exposing key-derivation primitives to app
    /// integration callers.
    static func authenticatedEnvelopeForTesting(_ data: Data,
                                                password: String,
                                                format: String? = nil,
                                                schemaVersion: Int? = nil) throws -> Data {
        try validatePassword(password)
        let original = try decodeEnvelope(data)
        try validateEnvelopeHeader(original, limits: .standard)
        let key = try deriveKey(password: password,
                                salt: original.kdf.salt,
                                iterations: original.kdf.iterations)
        let nonce = try AES.GCM.Nonce(data: original.nonce)
        let sealed = try AES.GCM.SealedBox(nonce: nonce,
                                           ciphertext: original.ciphertext,
                                           tag: original.tag)
        let originalAAD = try authenticatedHeaderData(for: original)
        let plaintext = try AES.GCM.open(sealed,
                                         using: SymmetricKey(data: key),
                                         authenticating: originalAAD)

        let changedHeader = EncryptedBackupEnvelope(
            format: format ?? original.format,
            schemaVersion: schemaVersion ?? original.schemaVersion,
            appIdentifier: original.appIdentifier,
            appVersion: original.appVersion,
            buildNumber: original.buildNumber,
            createdAt: original.createdAt,
            kdf: original.kdf,
            nonce: original.nonce,
            ciphertext: Data(),
            tag: Data())
        let changedAAD = try authenticatedHeaderData(for: changedHeader)
        let resealed = try AES.GCM.seal(plaintext,
                                        using: SymmetricKey(data: key),
                                        nonce: nonce,
                                        authenticating: changedAAD)
        let changed = EncryptedBackupEnvelope(
            format: changedHeader.format,
            schemaVersion: changedHeader.schemaVersion,
            appIdentifier: changedHeader.appIdentifier,
            appVersion: changedHeader.appVersion,
            buildNumber: changedHeader.buildNumber,
            createdAt: changedHeader.createdAt,
            kdf: changedHeader.kdf,
            nonce: changedHeader.nonce,
            ciphertext: resealed.ciphertext,
            tag: resealed.tag)
        return try encodeEnvelope(changed)
    }
#endif

    // MARK: Private crypto helpers

    private func validateConfiguration() throws {
        guard !configuration.appIdentifier.isEmpty,
              configuration.appIdentifier.unicodeScalars.count <= 256,
              !configuration.appVersion.isEmpty,
              configuration.appVersion.unicodeScalars.count <= 64,
              !configuration.buildNumber.isEmpty,
              configuration.buildNumber.unicodeScalars.count <= 64,
              configuration.iterations >= Self.minimumPBKDF2Iterations,
              configuration.iterations <= Self.maximumPBKDF2Iterations,
              configuration.limits.maxEncryptedBytes > 0,
              configuration.limits.maxPlaintextBytes > 0,
              configuration.limits.maxPlaintextBytes <= configuration.limits.maxEncryptedBytes,
              configuration.limits.maxPeriodDays >= 0,
              configuration.limits.maxDailyLogs >= 0,
              configuration.limits.maxMedications >= 0,
              configuration.limits.maxMedicationIntakes >= 0,
              configuration.limits.maxCustomSymptoms >= 0,
              configuration.limits.maxSymptomsPerLog >= 0,
              configuration.limits.maxHealthImportedFieldsPerLog >= 0,
              configuration.limits.maxStringLength > 0,
              configuration.limits.maxScheduleSlotsJSONLength > 0 else {
            throw EncryptedBackupError.invalidConfiguration
        }
    }

    private static func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max,
                                                          using: &generator) })
    }

    private static func canonicalDate(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        let micros = (seconds * 1_000_000).rounded()
        return Date(timeIntervalSince1970: micros / 1_000_000)
    }

    private struct AuthenticatedHeader: Codable {
        let format: String
        let schemaVersion: Int
        let appIdentifier: String
        let appVersion: String
        let buildNumber: String
        let createdAtMicros: Int64
        let kdf: BackupKDFParameters
        let nonce: Data
    }

    private static func authenticatedHeaderData(for envelope: EncryptedBackupEnvelope) throws -> Data {
        let seconds = envelope.createdAt.timeIntervalSince1970
        guard seconds.isFinite,
              abs(seconds) <= Double(Int64.max) / 1_000_000 else {
            throw EncryptedBackupError.authenticationFailed
        }
        let micros = Int64((seconds * 1_000_000).rounded())
        let header = AuthenticatedHeader(format: envelope.format,
                                         schemaVersion: envelope.schemaVersion,
                                         appIdentifier: envelope.appIdentifier,
                                         appVersion: envelope.appVersion,
                                         buildNumber: envelope.buildNumber,
                                         createdAtMicros: micros,
                                         kdf: envelope.kdf,
                                         nonce: envelope.nonce)
        return try makeJSONEncoder().encode(header)
    }

    private static func deriveKey(password: String,
                                  salt: Data,
                                  iterations: Int) throws -> Data {
        guard iterations >= minimumPBKDF2Iterations,
              iterations <= maximumPBKDF2Iterations,
              salt.count >= saltLength else {
            throw EncryptedBackupError.authenticationFailed
        }
        let passwordData = Data(password.utf8)
        guard !passwordData.isEmpty else {
            throw EncryptedBackupError.authenticationFailed
        }

        #if canImport(CommonCrypto)
        var result = Data(repeating: 0, count: keyLength)
        let status: Int32 = result.withUnsafeMutableBytes { output in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    let outputPointer = output.bindMemory(to: UInt8.self).baseAddress
                    let passwordPointer = passwordBytes.bindMemory(to: Int8.self).baseAddress
                    let saltPointer = saltBytes.bindMemory(to: UInt8.self).baseAddress
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer,
                        passwordData.count,
                        saltPointer,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outputPointer,
                        keyLength)
                }
            }
        }
        guard status == kCCSuccess else {
            throw EncryptedBackupError.authenticationFailed
        }
        return result
        #else
        // CryptoKit fallback for platforms that expose CryptoKit but not the
        // CommonCrypto module.  Apple iOS builds use the CommonCrypto branch.
        var block = Data()
        var previous = Data()
        for blockIndex in 1...1 { // one 32-byte SHA-256 block
            var input = salt
            var index = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &index) { input.append(contentsOf: $0) }
            previous = hmacSHA256(key: passwordData, data: input)
            var accumulator = previous
            if iterations > 1 {
                for _ in 2...iterations {
                    previous = hmacSHA256(key: passwordData, data: previous)
                    for i in 0..<accumulator.count { accumulator[i] ^= previous[i] }
                }
            }
            block.append(accumulator)
        }
        return Data(block.prefix(keyLength))
        #endif
    }

    #if !canImport(CommonCrypto)
    private static func hmacSHA256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
    #endif

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private static func validateEnvelopeHeader(_ envelope: EncryptedBackupEnvelope,
                                               limits: BackupLimits) throws {
        guard envelope.appIdentifier.unicodeScalars.count > 0,
              envelope.appIdentifier.unicodeScalars.count <= 256,
              envelope.appVersion.unicodeScalars.count > 0,
              envelope.appVersion.unicodeScalars.count <= 64,
              envelope.buildNumber.unicodeScalars.count > 0,
              envelope.buildNumber.unicodeScalars.count <= 64,
              envelope.kdf.algorithm == "PBKDF2-HMAC-SHA256",
              envelope.kdf.keyLength == keyLength,
              envelope.kdf.iterations >= minimumPBKDF2Iterations,
              envelope.kdf.iterations <= maximumPBKDF2Iterations,
              envelope.kdf.salt.count >= saltLength,
              envelope.kdf.salt.count <= 1024,
              envelope.nonce.count == nonceLength,
              envelope.tag.count == authenticationTagLength,
              !envelope.ciphertext.isEmpty,
              envelope.createdAt.timeIntervalSince1970.isFinite else {
            throw EncryptedBackupError.authenticationFailed
        }
    }
}

// MARK: - Snapshot validation

private enum BackupSnapshotValidator {
    private static let allowedHealthFields: Set<String> = [
        "sleep", "weight", "basalBodyTemperature", "spotting", "steps", "exercise"
    ]
    private static let allowedThemes: Set<String> = ["rose", "teal", "violet", "amber", "ink"]

    static func validate(_ snapshot: BackupSnapshot, limits: BackupLimits) throws {
        guard snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion else {
            throw EncryptedBackupError.unsupportedSchema
        }
        guard snapshot.periodDays.count <= limits.maxPeriodDays,
              snapshot.dailyLogs.count <= limits.maxDailyLogs,
              snapshot.medications.count <= limits.maxMedications,
              snapshot.medicationIntakes.count <= limits.maxMedicationIntakes,
              snapshot.customSymptoms.count <= limits.maxCustomSymptoms else {
            throw EncryptedBackupError.inputTooLarge
        }

        var periodKeys = Set<Int>()
        for item in snapshot.periodDays {
            try validateDayKey(item.dayKey)
            guard (0...3).contains(item.flowRaw),
                  validDate(item.createdAt), validDate(item.updatedAt),
                  periodKeys.insert(item.dayKey).inserted else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }

        var logKeys = Set<Int>()
        for item in snapshot.dailyLogs {
            try validateDayKey(item.dayKey)
            guard (0...5).contains(item.moodRaw),
                  (0...5).contains(item.energy),
                  (-1...5).contains(item.pain),
                  validOptionalFinite(item.sleepHours, range: 0...24, strictlyPositive: true),
                  validOptionalFinite(item.weight, range: 20...400),
                  validOptionalInt(item.steps, range: 0...200_000),
                  validOptionalInt(item.exerciseMinutes, range: 0...1_440),
                  validOptionalFinite(item.basalBodyTemperatureCelsius, range: 33...43),
                  validString(item.note, max: limits.maxStringLength),
                  item.symptoms.count <= limits.maxSymptomsPerLog,
                  item.healthImportedFields.count <= limits.maxHealthImportedFieldsPerLog,
                  logKeys.insert(item.dayKey).inserted else {
                throw EncryptedBackupError.invalidSnapshot
            }
            try validateStrings(item.symptoms, max: limits.maxStringLength, allowEmpty: false)
            try validateUnique(item.symptoms)
            try validateStrings(item.healthImportedFields,
                                max: 64,
                                allowEmpty: false)
            try validateUnique(item.healthImportedFields)
            guard Set(item.healthImportedFields).isSubset(of: allowedHealthFields) else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }

        var medicationIDs = Set<UUID>()
        for item in snapshot.medications {
            guard medicationIDs.insert(item.id).inserted,
                  validString(item.name, max: 256),
                  !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validString(item.emoji, max: 64),
                  !item.emoji.isEmpty,
                  (0...23).contains(item.reminderHour),
                  (0...59).contains(item.reminderMinute),
                  validString(item.scheduleSlotsJSON, max: limits.maxScheduleSlotsJSONLength),
                  validDate(item.createdAt) else {
                throw EncryptedBackupError.invalidSnapshot
            }
            try validateScheduleJSON(item.scheduleSlotsJSON)
        }

        var intakeKeys = Set<String>()
        for item in snapshot.medicationIntakes {
            try validateDayKey(item.dayKey)
            let expectedKey = item.medicationId.uuidString + "-" + String(item.dayKey)
            guard intakeKeys.insert(item.key).inserted,
                  item.key == expectedKey,
                  validString(item.key, max: 256),
                  validDate(item.takenAt) else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }

        let snapshotMedicationIDs = Set(snapshot.medications.map(\.id))
        guard snapshot.medicationIntakes.allSatisfy({
            snapshotMedicationIDs.contains($0.medicationId)
        }) else {
            throw EncryptedBackupError.invalidSnapshot
        }

        var customKeys = Set<String>()
        for item in snapshot.customSymptoms {
            guard customKeys.insert(item.key).inserted,
                  item.key.hasPrefix("c:"),
                  UUID(uuidString: String(item.key.dropFirst(2))) != nil,
                  validString(item.key, max: 256),
                  validString(item.label, max: 256),
                  !item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validString(item.emoji, max: 64),
                  !item.emoji.isEmpty,
                  validDate(item.createdAt) else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }

        guard itemThemeIsValid(snapshot.preferences.theme),
              (15...120).contains(snapshot.preferences.manualCycleLength),
              (1...14).contains(snapshot.preferences.manualPeriodLength) else {
            throw EncryptedBackupError.invalidSnapshot
        }
        try validatePreferences(snapshot.preferences)
    }

    private static func itemThemeIsValid(_ theme: String?) -> Bool {
        guard let theme else { return true }
        return allowedThemes.contains(theme)
    }

    private static func validatePreferences(_ preferences: BackupPreferences) throws {
        if let raw = preferences.lifeStageRaw {
            guard ["cycleTracking", "perimenopause"].contains(raw),
                  validString(raw, max: 64) else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }

        guard let contraception = preferences.contraception else { return }
        guard validString(contraception.methodRaw, max: 64),
              ContraceptionSettings.Method(rawValue: contraception.methodRaw) != nil,
              (0...23).contains(contraception.reminderHour),
              (0...59).contains(contraception.reminderMinute),
              validString(contraception.note, max: 500),
              validDate(contraception.updatedAt) else {
            throw EncryptedBackupError.invalidSnapshot
        }
        if let startDayKey = contraception.startDayKey {
            try validateDayKey(startDayKey)
        }

        let method = ContraceptionSettings.Method(rawValue: contraception.methodRaw)!
        guard method.supportsDailyReminder || !contraception.reminderEnabled else {
            throw EncryptedBackupError.invalidSnapshot
        }
        if method == .none {
            guard contraception.startDayKey == nil,
                  !contraception.reminderEnabled,
                  contraception.note.isEmpty else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }
    }

    private static func validateDayKey(_ key: Int) throws {
        let year = key / 10_000
        let month = (key / 100) % 100
        let day = key % 100
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw EncryptedBackupError.invalidSnapshot
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard components.isValidDate(in: calendar) else {
            throw EncryptedBackupError.invalidSnapshot
        }
    }

    private static func validDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return false }
        // Wide enough for old records and future migrations, but rejects
        // Foundation's practically unbounded distantPast/distantFuture.
        return (-2208988800.0...16_725_312_000.0).contains(seconds) // 1900...2500
    }

    private static func validOptionalFinite(_ value: Double?,
                                            range: ClosedRange<Double>,
                                            strictlyPositive: Bool = false) -> Bool {
        guard let value else { return true }
        return value.isFinite && range.contains(value) && (!strictlyPositive || value > 0)
    }

    private static func validOptionalInt(_ value: Int?, range: ClosedRange<Int>) -> Bool {
        guard let value else { return true }
        return range.contains(value)
    }

    private static func validString(_ value: String, max: Int) -> Bool {
        guard value.unicodeScalars.count <= max else { return false }
        return !value.unicodeScalars.contains { scalar in
            scalar.value == 0
                || (scalar.value < 0x20
                    && scalar.value != 0x09
                    && scalar.value != 0x0A
                    && scalar.value != 0x0D)
        }
    }

    private static func validateStrings(_ values: [String], max: Int, allowEmpty: Bool) throws {
        for value in values {
            guard (allowEmpty || !value.isEmpty), validString(value, max: max) else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }
    }

    private static func validateUnique(_ values: [String]) throws {
        guard Set(values).count == values.count else {
            throw EncryptedBackupError.invalidSnapshot
        }
    }

    private static func validateScheduleJSON(_ value: String) throws {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let slots = object as? [[String: Any]],
              slots.count <= 6 else {
            throw EncryptedBackupError.invalidSnapshot
        }
        for slot in slots {
            guard let id = slot["id"] as? String,
                  UUID(uuidString: id) != nil,
                  let hour = slot["hour"] as? Int,
                  (0...23).contains(hour),
                  let minute = slot["minute"] as? Int,
                  (0...59).contains(minute),
                  let weekdays = slot["weekdays"] as? [Int],
                  weekdays.count <= 7,
                  weekdays.allSatisfy({ (1...7).contains($0) }),
                  Set(weekdays).count == weekdays.count else {
                throw EncryptedBackupError.invalidSnapshot
            }
        }
    }
}

// MARK: - Model capture (no SwiftData mutation)

extension BackupSnapshot {
    /// Captures the five SwiftData model collections into pure DTOs.  This is
    /// intentionally an internal overload because the app's SwiftData model
    /// classes are internal; the encrypted format itself remains Foundation
    /// only and can be tested without a model container.
    init(periodDays: [PeriodDay],
         dailyLogs: [DailyLog],
         medications: [Medication],
         medicationIntakes: [MedicationIntake],
         customSymptoms: [CustomSymptom],
         preferences: BackupPreferences? = nil) {
        self.init(periodDays: periodDays.map {
            BackupPeriodDayPayload(dayKey: $0.dayKey,
                                   flowRaw: $0.flowRaw,
                                   createdAt: $0.createdAt,
                                   updatedAt: $0.updatedAt,
                                   importedFromHealth: $0.importedFromHealth)
        }, dailyLogs: dailyLogs.map {
            BackupDailyLogPayload(dayKey: $0.dayKey,
                                  moodRaw: $0.moodRaw,
                                  energy: $0.energy,
                                  pain: $0.pain,
                                  sleepHours: $0.sleepHours,
                                  weight: $0.weight,
                                  steps: $0.steps,
                                  exerciseMinutes: $0.exerciseMinutes,
                                  basalBodyTemperatureCelsius: $0.basalBodyTemperatureCelsius,
                                  spotting: $0.spotting,
                                  healthImportedFields: $0.healthImportedFields,
                                  symptoms: $0.symptoms,
                                  note: $0.note,
                                  updatedAt: $0.updatedAt)
        }, medications: medications.map {
            BackupMedicationPayload(id: $0.id,
                                    name: $0.name,
                                    emoji: $0.emoji,
                                    reminderEnabled: $0.reminderEnabled,
                                    reminderHour: $0.reminderHour,
                                    reminderMinute: $0.reminderMinute,
                                    proScheduleEnabled: $0.proScheduleEnabled,
                                    scheduleSlotsJSON: $0.scheduleSlotsJSON,
                                    createdAt: $0.createdAt)
        }, medicationIntakes: medicationIntakes.map {
            BackupMedicationIntakePayload(key: $0.key,
                                          medicationId: $0.medicationId,
                                          dayKey: $0.dayKey,
                                          takenAt: $0.takenAt)
        }, customSymptoms: customSymptoms.map {
            BackupCustomSymptomPayload(key: $0.key,
                                       label: $0.label,
                                       emoji: $0.emoji,
                                       createdAt: $0.createdAt)
        }, preferences: preferences ?? BackupPreferences.fromCurrentDeviceDefaults())
    }

    static func capture(periodDays: [PeriodDay],
                        dailyLogs: [DailyLog],
                        medications: [Medication],
                        medicationIntakes: [MedicationIntake],
                        customSymptoms: [CustomSymptom],
                        preferences: BackupPreferences? = nil) -> BackupSnapshot {
        BackupSnapshot(periodDays: periodDays,
                       dailyLogs: dailyLogs,
                       medications: medications,
                       medicationIntakes: medicationIntakes,
                       customSymptoms: customSymptoms,
                       preferences: preferences)
    }
}

// MARK: - Deterministic merge planning

public enum BackupMergeMode: String, Codable, Equatable, Sendable {
    case merge
    case replace
}

/// A side-effect-free plan.  Applying this plan to SwiftData is deliberately
/// left to the integration layer so a UI can preview and confirm it first.
public struct BackupMergePlan: Equatable, Sendable {
    public let mode: BackupMergeMode
    public let periodDaysToInsert: [BackupPeriodDayPayload]
    public let periodDaysToUpdate: [BackupPeriodDayPayload]
    public let periodDayKeysToDelete: [Int]
    public let dailyLogsToInsert: [BackupDailyLogPayload]
    public let dailyLogsToUpdate: [BackupDailyLogPayload]
    public let dailyLogKeysToDelete: [Int]
    public let medicationsToInsert: [BackupMedicationPayload]
    public let medicationIDsToDelete: [UUID]
    public let medicationIntakesToInsert: [BackupMedicationIntakePayload]
    public let intakeKeysToDelete: [String]
    public let customSymptomsToInsert: [BackupCustomSymptomPayload]
    public let customSymptomKeysToDelete: [String]
    public let preferencesToApply: BackupPreferences

    public var periodDaysToAdd: [BackupPeriodDayPayload] { periodDaysToInsert }
    public var dailyLogsToAdd: [BackupDailyLogPayload] { dailyLogsToInsert }
    public var isEmpty: Bool {
        periodDaysToInsert.isEmpty && periodDaysToUpdate.isEmpty && periodDayKeysToDelete.isEmpty
            && dailyLogsToInsert.isEmpty && dailyLogsToUpdate.isEmpty && dailyLogKeysToDelete.isEmpty
            && medicationsToInsert.isEmpty && medicationIDsToDelete.isEmpty
            && medicationIntakesToInsert.isEmpty && intakeKeysToDelete.isEmpty
            && customSymptomsToInsert.isEmpty && customSymptomKeysToDelete.isEmpty
    }

    public var changeCount: Int {
        periodDaysToInsert.count + periodDaysToUpdate.count + periodDayKeysToDelete.count
            + dailyLogsToInsert.count + dailyLogsToUpdate.count + dailyLogKeysToDelete.count
            + medicationsToInsert.count + medicationIDsToDelete.count
            + medicationIntakesToInsert.count + intakeKeysToDelete.count
            + customSymptomsToInsert.count + customSymptomKeysToDelete.count
    }

    fileprivate init(mode: BackupMergeMode,
                     periodDaysToInsert: [BackupPeriodDayPayload],
                     periodDaysToUpdate: [BackupPeriodDayPayload],
                     periodDayKeysToDelete: [Int],
                     dailyLogsToInsert: [BackupDailyLogPayload],
                     dailyLogsToUpdate: [BackupDailyLogPayload],
                     dailyLogKeysToDelete: [Int],
                     medicationsToInsert: [BackupMedicationPayload],
                     medicationIDsToDelete: [UUID],
                     medicationIntakesToInsert: [BackupMedicationIntakePayload],
                     intakeKeysToDelete: [String],
                     customSymptomsToInsert: [BackupCustomSymptomPayload],
                     customSymptomKeysToDelete: [String],
                     preferencesToApply: BackupPreferences) {
        self.mode = mode
        self.periodDaysToInsert = periodDaysToInsert
        self.periodDaysToUpdate = periodDaysToUpdate
        self.periodDayKeysToDelete = periodDayKeysToDelete
        self.dailyLogsToInsert = dailyLogsToInsert
        self.dailyLogsToUpdate = dailyLogsToUpdate
        self.dailyLogKeysToDelete = dailyLogKeysToDelete
        self.medicationsToInsert = medicationsToInsert
        self.medicationIDsToDelete = medicationIDsToDelete
        self.medicationIntakesToInsert = medicationIntakesToInsert
        self.intakeKeysToDelete = intakeKeysToDelete
        self.customSymptomsToInsert = customSymptomsToInsert
        self.customSymptomKeysToDelete = customSymptomKeysToDelete
        self.preferencesToApply = preferencesToApply
    }
}

public enum BackupMergePlanner {
    /// Plans a merge without mutating either input snapshot or SwiftData.
    ///
    /// Merge conflicts are deterministic: period/daily records replace only
    /// when the incoming `updatedAt` is strictly newer; existing medication
    /// UUIDs, intake keys, and custom-symptom keys always win.  Replace mode
    /// explicitly deletes every current key and inserts the complete incoming
    /// snapshot.
    public static func plan(current: BackupSnapshot,
                            incoming: BackupSnapshot,
                            mode: BackupMergeMode = .merge) -> BackupMergePlan {
        let currentPeriods = Dictionary(current.periodDays.map { ($0.dayKey, $0) },
                                        uniquingKeysWith: { first, _ in first })
        let currentLogs = Dictionary(current.dailyLogs.map { ($0.dayKey, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let currentMedications = Set(current.medications.map(\.id))
        let currentIntakeKeys = Set(current.medicationIntakes.map(\.key))
        let currentCustomKeys = Set(current.customSymptoms.map(\.key))

        switch mode {
        case .replace:
            return BackupMergePlan(
                mode: .replace,
                periodDaysToInsert: incoming.periodDays.sorted { $0.dayKey < $1.dayKey },
                periodDaysToUpdate: [],
                periodDayKeysToDelete: current.periodDays.map(\.dayKey).sorted(),
                dailyLogsToInsert: incoming.dailyLogs.sorted { $0.dayKey < $1.dayKey },
                dailyLogsToUpdate: [],
                dailyLogKeysToDelete: current.dailyLogs.map(\.dayKey).sorted(),
                medicationsToInsert: incoming.medications.sorted { $0.id.uuidString < $1.id.uuidString },
                medicationIDsToDelete: current.medications.map(\.id).sorted { $0.uuidString < $1.uuidString },
                medicationIntakesToInsert: incoming.medicationIntakes.sorted { $0.key < $1.key },
                intakeKeysToDelete: current.medicationIntakes.map(\.key).sorted(),
                customSymptomsToInsert: incoming.customSymptoms.sorted { $0.key < $1.key },
                customSymptomKeysToDelete: current.customSymptoms.map(\.key).sorted(),
                preferencesToApply: incoming.preferences)

        case .merge:
            var periodInsert: [BackupPeriodDayPayload] = []
            var periodUpdate: [BackupPeriodDayPayload] = []
            for item in incoming.periodDays {
                guard let existing = currentPeriods[item.dayKey] else {
                    periodInsert.append(item)
                    continue
                }
                if item.updatedAt > existing.updatedAt { periodUpdate.append(item) }
            }

            var logInsert: [BackupDailyLogPayload] = []
            var logUpdate: [BackupDailyLogPayload] = []
            for item in incoming.dailyLogs {
                guard let existing = currentLogs[item.dayKey] else {
                    logInsert.append(item)
                    continue
                }
                if item.updatedAt > existing.updatedAt { logUpdate.append(item) }
            }

            return BackupMergePlan(
                mode: .merge,
                periodDaysToInsert: periodInsert.sorted { $0.dayKey < $1.dayKey },
                periodDaysToUpdate: periodUpdate.sorted { $0.dayKey < $1.dayKey },
                periodDayKeysToDelete: [],
                dailyLogsToInsert: logInsert.sorted { $0.dayKey < $1.dayKey },
                dailyLogsToUpdate: logUpdate.sorted { $0.dayKey < $1.dayKey },
                dailyLogKeysToDelete: [],
                medicationsToInsert: incoming.medications
                    .filter { !currentMedications.contains($0.id) }
                    .sorted { $0.id.uuidString < $1.id.uuidString },
                medicationIDsToDelete: [],
                medicationIntakesToInsert: incoming.medicationIntakes
                    .filter { !currentIntakeKeys.contains($0.key) }
                    .sorted { $0.key < $1.key },
                intakeKeysToDelete: [],
                customSymptomsToInsert: incoming.customSymptoms
                    .filter { !currentCustomKeys.contains($0.key) }
                    .sorted { $0.key < $1.key },
                customSymptomKeysToDelete: [],
                preferencesToApply: incoming.preferences)
        }
    }

    public static func makePlan(current: BackupSnapshot,
                                incoming: BackupSnapshot,
                                mode: BackupMergeMode = .merge) -> BackupMergePlan {
        plan(current: current, incoming: incoming, mode: mode)
    }
}
