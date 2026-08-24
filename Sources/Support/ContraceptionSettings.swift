import Foundation

/// A small, local-only record of a contraception method.
///
/// This is intentionally not a SwiftData model and contains no effectiveness
/// or other medical claims. The caller decides what, if anything, to do with
/// the optional reminder preference after saving.
struct ContraceptionSettings: Codable, Equatable {
    enum Method: String, CaseIterable, Codable, Equatable, Identifiable {
        case none
        case pill
        case ring
        case patch
        case injection
        case iud
        case implant
        case condom
        case fertilityAwareness = "fertilityAwareness"
        case other

        var id: String { rawValue }

        /// A daily reminder is applicable to a pill record only. This is a
        /// UI/data-entry constraint, not a claim about any method.
        var supportsDailyReminder: Bool { self == .pill }

        var displayName: String {
            switch self {
            case .none: return String(localized: "None")
            case .pill: return String(localized: "Pill")
            case .ring: return String(localized: "Ring")
            case .patch: return String(localized: "Patch")
            case .injection: return String(localized: "Injection")
            case .iud: return String(localized: "IUD")
            case .implant: return String(localized: "Implant")
            case .condom: return String(localized: "Condom")
            case .fertilityAwareness: return String(localized: "Fertility awareness")
            case .other: return String(localized: "Other")
            }
        }
    }

    struct Snapshot: Codable, Equatable {
        let method: Method
        let startDayKey: Int?
        let reminderEnabled: Bool
        let reminderHour: Int
        let reminderMinute: Int
        let note: String
        let updatedAt: Date

        init(_ settings: ContraceptionSettings) {
            let normalized = settings.normalized
            method = normalized.method
            startDayKey = normalized.startDayKey
            reminderEnabled = normalized.reminderEnabled
            reminderHour = normalized.reminderHour
            reminderMinute = normalized.reminderMinute
            note = normalized.note
            updatedAt = normalized.updatedAt
        }
    }

    enum Storage {
        static let key = "vela.contraceptionSettings.v1"
    }

    static let storageKey = Storage.key
    static let maxNoteLength = 500

    var method: Method
    var startDayKey: Int?
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var note: String
    var updatedAt: Date

    init(
        method: Method = .none,
        startDayKey: Int? = nil,
        reminderEnabled: Bool = false,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        note: String = "",
        updatedAt: Date = Date()
    ) {
        self.method = method
        self.startDayKey = startDayKey
        self.reminderEnabled = reminderEnabled
        self.reminderHour = Self.clampHour(reminderHour)
        self.reminderMinute = Self.clampMinute(reminderMinute)
        self.note = Self.normalizedNote(note)
        self.updatedAt = updatedAt
    }

    /// Safe fallback used when the suite has no valid stored profile.
    static var empty: ContraceptionSettings { ContraceptionSettings() }

    /// Loads from an injected UserDefaults suite. Missing, malformed, and
    /// incompatible old bytes safely fall back to an empty profile.
    static func load(from defaults: UserDefaults = .standard) -> ContraceptionSettings {
        guard let data = defaults.data(forKey: Storage.key),
              let decoded = try? JSONDecoder().decode(ContraceptionSettings.self, from: data) else {
            return .empty
        }
        return decoded.normalized
    }

    /// Saves this profile as one Codable blob in the supplied local suite.
    @discardableResult
    func save(to defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(normalized) else { return false }
        defaults.set(data, forKey: Storage.key)
        return true
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: Storage.key)
    }

    /// Explicit, export-friendly value without any UserDefaults dependency.
    var snapshot: Snapshot { Snapshot(self) }

    func exportSnapshot() -> Snapshot { snapshot }

    static func exportSnapshot(from defaults: UserDefaults = .standard) -> Snapshot {
        load(from: defaults).snapshot
    }

    var normalized: ContraceptionSettings {
        var copy = self
        copy.reminderHour = Self.clampHour(copy.reminderHour)
        copy.reminderMinute = Self.clampMinute(copy.reminderMinute)
        copy.note = Self.normalizedNote(copy.note)
        if !copy.method.supportsDailyReminder {
            copy.reminderEnabled = false
        }
        if copy.method == .none {
            copy.startDayKey = nil
            copy.reminderEnabled = false
            copy.note = ""
        }
        return copy
    }

    private static func clampHour(_ value: Int) -> Int { min(max(value, 0), 23) }
    private static func clampMinute(_ value: Int) -> Int { min(max(value, 0), 59) }

    private static func normalizedNote(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNoteLength))
    }

    // Decode fields independently so older profiles missing newly introduced
    // values remain readable. A corrupt blob is handled by `load`'s fallback.
    private enum CodingKeys: String, CodingKey {
        case method, startDayKey, reminderEnabled, reminderHour, reminderMinute, note, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let methodRawValue = try container.decodeIfPresent(String.self, forKey: .method)
        method = methodRawValue.flatMap(Method.init(rawValue:)) ?? .none
        startDayKey = try container.decodeIfPresent(Int.self, forKey: .startDayKey)
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = Self.clampHour(try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 9)
        reminderMinute = Self.clampMinute(try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0)
        note = Self.normalizedNote(try container.decodeIfPresent(String.self, forKey: .note) ?? "")
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
