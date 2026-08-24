import Foundation

/// The tracking context selected by the person using the app.
///
/// This is a preference, not a conclusion about a person's health. The
/// default is deliberately the general cycle-tracking context when a stored
/// value is missing or no longer recognised.
enum LifeStage: String, Codable, CaseIterable, Identifiable {
    case cycleTracking = "cycleTracking"
    case perimenopause = "perimenopause"

    /// Stable storage key. Keep this value unchanged when adding cases.
    static let userDefaultsKey = "vela.lifeStage"

    /// Alias for callers that use the shorter storage terminology.
    static let defaultsKey = userDefaultsKey

    /// Safe fallback for missing, malformed, or future values.
    static let defaultValue: LifeStage = .cycleTracking

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cycleTracking:
            return String(localized: "Cycle tracking")
        case .perimenopause:
            return String(localized: "Perimenopause")
        }
    }

    /// Decoding is tolerant of values written by a newer build or a damaged
    /// preference payload. The explicit choice remains the only source of the
    /// value; no record is inspected to choose a case.
    init(from decoder: Decoder) throws {
        let rawValue = try? decoder.singleValueContainer().decode(String.self)
        self = rawValue.flatMap(LifeStage.init(rawValue:)) ?? Self.defaultValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Reads the preference without inferring anything from logged data.
    static func load(from defaults: UserDefaults = .standard) -> LifeStage {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let value = LifeStage(rawValue: rawValue) else {
            return defaultValue
        }
        return value
    }

    /// Stores only the explicitly selected context.
    static func save(_ value: LifeStage, to defaults: UserDefaults = .standard) {
        defaults.set(value.rawValue, forKey: userDefaultsKey)
    }

    /// Convenience for UI code that wants the current explicit preference.
    static var current: LifeStage { load() }
}
