import Foundation

/// Bounded, descriptive summaries of records that can be shown in the
/// perimenopause tracking context.
///
/// The engine intentionally knows nothing about SwiftData or the meaning of
/// a person's life-stage choice. It only counts supplied records, compares
/// two equal calendar-day windows, and reports simple averages.
enum PerimenopauseTrendEngine {

    // MARK: - Policy constants

    /// These are storage keys, not inferred clinical categories.
    static let relevantSymptomKeys: [String] = [
        "hotFlashes",
        "nightSweats",
        "vaginalDryness",
        "brainFog",
        "heartRacing",
        "jointPain",
        "sleepInterrupted",
    ]

    /// Existing Vela sleep trackers are accepted as observations for the
    /// neutral `sleepInterrupted` row. The raw keys remain available through
    /// `DailyRecord.symptomKeys` for callers that need them elsewhere.
    static let sleepSymptomAliases: Set<String> = [
        "sleepInterrupted",
        "insomnia",
        "restlessSleep",
        "earlyMorningWake",
    ]

    /// A ten percentage-point change is the smallest reported direction.
    /// Smaller changes are deliberately labelled stable.
    static let directionThreshold = 0.10

    /// Both sides of a comparison need at least this many recorded days.
    static let minimumComparisonDays = 3

    /// Averages are shown only after this many actual values are present on
    /// the corresponding side of the comparison.
    static let minimumAverageSamples = 3

    // MARK: - Input DTOs

    /// One user-supplied daily observation. Either a `date` or a `dayKey` is
    /// enough to identify the day; when both exist, `dayKey` wins because it
    /// is the app's stable storage identity.
    struct DailyRecord: Hashable {
        let date: Date?
        let dayKey: Int?
        let symptomKeys: Set<String>
        let mood: Double?
        let sleepHours: Double?

        init(date: Date,
             symptomKeys: Set<String> = [],
             mood: Double? = nil,
             sleepHours: Double? = nil) {
            self.date = date
            self.dayKey = nil
            self.symptomKeys = symptomKeys
            self.mood = mood
            self.sleepHours = sleepHours
        }

        init(dayKey: Int,
             symptomKeys: Set<String> = [],
             mood: Double? = nil,
             sleepHours: Double? = nil) {
            self.date = nil
            self.dayKey = dayKey
            self.symptomKeys = symptomKeys
            self.mood = mood
            self.sleepHours = sleepHours
        }

        /// Useful for adapters that may have either identity available.
        init(date: Date? = nil,
             dayKey: Int? = nil,
             symptomKeys: Set<String> = [],
             mood: Double? = nil,
             sleepHours: Double? = nil) {
            self.date = date
            self.dayKey = dayKey
            self.symptomKeys = symptomKeys
            self.mood = mood
            self.sleepHours = sleepHours
        }

        var symptoms: Set<String> { symptomKeys }
    }

    /// Complete input for one bounded report. `periodStartDayKeys` and
    /// `periodStartDates` are both supported so a caller can map existing
    /// `PeriodDay` values without making this engine depend on that model.
    struct Input {
        let dailyRecords: [DailyRecord]
        let periodStartDates: [Date]
        let periodStartDayKeys: [Int]
        let asOf: Date
        let calendar: Calendar

        init(dailyRecords: [DailyRecord] = [],
             periodStartDates: [Date] = [],
             periodStartDayKeys: [Int] = [],
             asOf: Date = Date(),
             calendar: Calendar = Calendar(identifier: .gregorian)) {
            self.dailyRecords = dailyRecords
            self.periodStartDates = periodStartDates
            self.periodStartDayKeys = periodStartDayKeys
            self.asOf = asOf
            self.calendar = calendar
        }

        init(records: [DailyRecord] = [],
             periodStartDates: [Date] = [],
             periodStartDayKeys: [Int] = [],
             asOf: Date = Date(),
             calendar: Calendar = Calendar(identifier: .gregorian)) {
            self.init(dailyRecords: records,
                      periodStartDates: periodStartDates,
                      periodStartDayKeys: periodStartDayKeys,
                      asOf: asOf,
                      calendar: calendar)
        }

        var records: [DailyRecord] { dailyRecords }
    }

    // MARK: - Output DTOs

    enum Direction: String, Codable, CaseIterable, Identifiable {
        case rising
        case falling
        case stable
        case insufficient

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rising:       return String(localized: "Rising")
            case .falling:      return String(localized: "Falling")
            case .stable:       return String(localized: "Stable")
            case .insufficient: return String(localized: "Not enough data")
            }
        }
    }

    struct SymptomTrend: Hashable, Identifiable {
        let key: String
        let recentCount: Int
        let previousCount: Int
        let recentRate: Double?
        let previousRate: Double?
        let direction: Direction

        var id: String { key }
        var count: Int { recentCount }
        var rate: Double? { recentRate }
    }

    struct AverageComparison: Hashable {
        let recentAverage: Double?
        let previousAverage: Double?
        let recentSampleCount: Int
        let previousSampleCount: Int

        var recent: Double? { recentAverage }
        var previous: Double? { previousAverage }
        var isRecentSufficient: Bool {
            recentSampleCount >= minimumAverageSamples
        }
        var isPreviousSufficient: Bool {
            previousSampleCount >= minimumAverageSamples
        }
        var isSufficient: Bool {
            isRecentSufficient && isPreviousSufficient
        }
    }

    struct CycleLengthSummary: Hashable {
        let lengths: [Int]
        let minimum: Int?
        let maximum: Int?
        let range: Int?

        var count: Int { lengths.count }
        var min: Int? { minimum }
        var max: Int? { maximum }
        var minDays: Int? { minimum }
        var maxDays: Int? { maximum }
        var rangeDays: Int? { range }
    }

    /// Facts for the most recent `days` calendar days and a same-sized
    /// immediately preceding window.
    struct Window: Identifiable {
        let days: Int
        let startDate: Date
        let endDate: Date
        let previousStartDate: Date
        let previousEndDate: Date
        let coverageDays: Int
        let previousCoverageDays: Int
        let symptomTrends: [SymptomTrend]
        let cycleLength: CycleLengthSummary
        let sleep: AverageComparison
        let mood: AverageComparison

        var id: Int { days }
        var windowDays: Int { days }
        var dataCoverageDays: Int { coverageDays }
        var symptomCounts: [String: Int] {
            Dictionary(uniqueKeysWithValues: symptomTrends.map {
                ($0.key, $0.recentCount)
            })
        }
        var symptomDirections: [String: Direction] {
            Dictionary(uniqueKeysWithValues: symptomTrends.map {
                ($0.key, $0.direction)
            })
        }
        var isDataSparse: Bool {
            coverageDays < minimumComparisonDays ||
                previousCoverageDays < minimumComparisonDays
        }
        var recentSleepAverage: Double? { sleep.recentAverage }
        var previousSleepAverage: Double? { sleep.previousAverage }
        var recentMoodAverage: Double? { mood.recentAverage }
        var previousMoodAverage: Double? { mood.previousAverage }

        func symptomTrend(for key: String) -> SymptomTrend? {
            let canonicalKey = Self.canonicalSymptomKey(key)
            return symptomTrends.first { $0.key == canonicalKey }
        }

        func symptomCount(for key: String) -> Int {
            symptomTrend(for: key)?.recentCount ?? 0
        }

        private static func canonicalSymptomKey(_ key: String) -> String {
            PerimenopauseTrendEngine.sleepSymptomAliases.contains(key)
                ? "sleepInterrupted"
                : key
        }
    }

    struct Report {
        let asOf: Date
        let thirtyDay: Window
        let ninetyDay: Window

        var thirty: Window { thirtyDay }
        var ninety: Window { ninetyDay }
    }

    typealias Output = Report
    typealias Result = Report

    // MARK: - Evaluation

    static func evaluate(_ input: Input) -> Report {
        var calendar = input.calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let anchor = calendar.startOfDay(for: input.asOf)
        let records = normalizedRecords(input.dailyRecords, anchor: anchor, calendar: calendar)
        let periodStarts = normalizedPeriodStarts(input, anchor: anchor, calendar: calendar)

        return Report(
            asOf: anchor,
            thirtyDay: makeWindow(days: 30,
                                  anchor: anchor,
                                  records: records,
                                  periodStarts: periodStarts,
                                  calendar: calendar),
            ninetyDay: makeWindow(days: 90,
                                  anchor: anchor,
                                  records: records,
                                  periodStarts: periodStarts,
                                  calendar: calendar)
        )
    }

    static func analyze(_ input: Input) -> Report {
        evaluate(input)
    }

    // MARK: - Internal normalization

    private struct NormalizedRecord {
        let day: Date
        let dayKey: Int
        let symptomKeys: Set<String>
        let mood: Double?
        let sleepHours: Double?
    }

    private struct DateWindow {
        let recentStart: Date
        let recentEnd: Date
        let previousStart: Date
        let previousEnd: Date

        func containsRecent(_ date: Date) -> Bool {
            date >= recentStart && date < recentEnd
        }

        func containsPrevious(_ date: Date) -> Bool {
            date >= previousStart && date < previousEnd
        }
    }

    private static func normalizedRecords(_ rawRecords: [DailyRecord],
                                          anchor: Date,
                                          calendar: Calendar) -> [NormalizedRecord] {
        var byDay: [Int: NormalizedRecord] = [:]

        for raw in rawRecords {
            guard let day = dayStart(for: raw, calendar: calendar), day <= anchor else {
                continue
            }
            let key = dayKey(for: day, calendar: calendar)
            let symptoms = Set(raw.symptomKeys.compactMap(canonicalSymptomKey))
            let mood = validMood(raw.mood)
            let sleep = validSleep(raw.sleepHours)

            if let existing = byDay[key] {
                // A same-day duplicate can come from two adapters. Union
                // tags and retain the last non-nil scalar value, rather than
                // letting a duplicate inflate coverage or event counts.
                byDay[key] = NormalizedRecord(
                    day: existing.day,
                    dayKey: key,
                    symptomKeys: existing.symptomKeys.union(symptoms),
                    mood: mood ?? existing.mood,
                    sleepHours: sleep ?? existing.sleepHours
                )
            } else {
                byDay[key] = NormalizedRecord(
                    day: day,
                    dayKey: key,
                    symptomKeys: symptoms,
                    mood: mood,
                    sleepHours: sleep
                )
            }
        }

        return byDay.values.sorted { $0.day < $1.day }
    }

    private static func normalizedPeriodStarts(_ input: Input,
                                               anchor: Date,
                                               calendar: Calendar) -> [Date] {
        let dates = input.periodStartDates.compactMap {
            calendar.startOfDay(for: $0) <= anchor ? calendar.startOfDay(for: $0) : nil
        }
        let dayKeyDates: [Date] = input.periodStartDayKeys.compactMap { key -> Date? in
            guard let date = date(for: key, calendar: calendar), date <= anchor else {
                return nil
            }
            return date
        }
        return Array(Set(dates + dayKeyDates)).sorted()
    }

    private static func dayStart(for record: DailyRecord,
                                 calendar: Calendar) -> Date? {
        if let key = record.dayKey, let date = date(for: key, calendar: calendar) {
            return date
        }
        guard let date = record.date else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func date(for dayKey: Int, calendar: Calendar) -> Date? {
        guard dayKey >= 1_000_101 else { return nil }
        let year = dayKey / 10_000
        let month = (dayKey / 100) % 100
        let day = dayKey % 100
        guard year >= 1, month >= 1, month <= 12, day >= 1, day <= 31 else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 1) * 10_000 +
            (components.month ?? 1) * 100 +
            (components.day ?? 1)
    }

    private static func canonicalSymptomKey(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return sleepSymptomAliases.contains(trimmed) ? "sleepInterrupted" : trimmed
    }

    private static func validMood(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (1...5).contains(value) else { return nil }
        return value
    }

    private static func validSleep(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 24 else { return nil }
        return value
    }

    // MARK: - Window calculations

    private static func makeWindow(days: Int,
                                   anchor: Date,
                                   records: [NormalizedRecord],
                                   periodStarts: [Date],
                                   calendar: Calendar) -> Window {
        let window = makeDateWindow(days: days, anchor: anchor, calendar: calendar)
        let recentRecords = records.filter { window.containsRecent($0.day) }
        let previousRecords = records.filter { window.containsPrevious($0.day) }
        let coverageDays = recentRecords.count
        let previousCoverageDays = previousRecords.count

        let trends = relevantSymptomKeys.map { key in
            let recentCount = recentRecords.reduce(into: 0) { result, record in
                if record.symptomKeys.contains(key) { result += 1 }
            }
            let previousCount = previousRecords.reduce(into: 0) { result, record in
                if record.symptomKeys.contains(key) { result += 1 }
            }
            let recentRate = coverageDays > 0
                ? Double(recentCount) / Double(coverageDays)
                : nil
            let previousRate = previousCoverageDays > 0
                ? Double(previousCount) / Double(previousCoverageDays)
                : nil
            return SymptomTrend(
                key: key,
                recentCount: recentCount,
                previousCount: previousCount,
                recentRate: recentRate,
                previousRate: previousRate,
                direction: direction(recentRate: recentRate,
                                     previousRate: previousRate,
                                     recentCoverage: coverageDays,
                                     previousCoverage: previousCoverageDays)
            )
        }

        return Window(
            days: days,
            startDate: window.recentStart,
            endDate: calendar.date(byAdding: .day, value: -1, to: window.recentEnd) ?? window.recentEnd,
            previousStartDate: window.previousStart,
            previousEndDate: calendar.date(byAdding: .day, value: -1, to: window.previousEnd) ?? window.previousEnd,
            coverageDays: coverageDays,
            previousCoverageDays: previousCoverageDays,
            symptomTrends: trends,
            cycleLength: cycleSummary(periodStarts: periodStarts,
                                       window: window,
                                       calendar: calendar),
            sleep: averageComparison(recentRecords: recentRecords,
                                     previousRecords: previousRecords,
                                     value: { $0.sleepHours }),
            mood: averageComparison(recentRecords: recentRecords,
                                    previousRecords: previousRecords,
                                    value: { $0.mood })
        )
    }

    private static func makeDateWindow(days: Int,
                                       anchor: Date,
                                       calendar: Calendar) -> DateWindow {
        let recentStart = calendar.date(byAdding: .day, value: -(days - 1), to: anchor) ?? anchor
        let previousStart = calendar.date(byAdding: .day, value: -days, to: recentStart) ?? recentStart
        return DateWindow(
            recentStart: recentStart,
            recentEnd: calendar.date(byAdding: .day, value: 1, to: anchor) ?? anchor,
            previousStart: previousStart,
            previousEnd: recentStart
        )
    }

    private static func direction(recentRate: Double?,
                                  previousRate: Double?,
                                  recentCoverage: Int,
                                  previousCoverage: Int) -> Direction {
        guard recentCoverage >= minimumComparisonDays,
              previousCoverage >= minimumComparisonDays,
              let recentRate,
              let previousRate else {
            return .insufficient
        }
        let change = recentRate - previousRate
        if change >= directionThreshold { return .rising }
        if change <= -directionThreshold { return .falling }
        return .stable
    }

    private static func averageComparison(
        recentRecords: [NormalizedRecord],
        previousRecords: [NormalizedRecord],
        value: (NormalizedRecord) -> Double?
    ) -> AverageComparison {
        let recentValues = recentRecords.compactMap(value)
        let previousValues = previousRecords.compactMap(value)
        return AverageComparison(
            recentAverage: average(recentValues),
            previousAverage: average(previousValues),
            recentSampleCount: recentValues.count,
            previousSampleCount: previousValues.count
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        guard values.count >= minimumAverageSamples else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func cycleSummary(periodStarts: [Date],
                                     window: DateWindow,
                                     calendar: Calendar) -> CycleLengthSummary {
        guard periodStarts.count >= 2 else {
            return CycleLengthSummary(lengths: [], minimum: nil, maximum: nil, range: nil)
        }

        var lengths: [Int] = []
        for index in 1..<periodStarts.count {
            let previous = periodStarts[index - 1]
            let current = periodStarts[index]
            guard window.containsRecent(current),
                  let length = calendar.dateComponents([.day], from: previous, to: current).day,
                  length > 0 else {
                continue
            }
            lengths.append(length)
        }

        let minimum = lengths.min()
        let maximum = lengths.max()
        let range: Int?
        if let minimum, let maximum {
            range = maximum - minimum
        } else {
            range = nil
        }
        return CycleLengthSummary(lengths: lengths,
                                  minimum: minimum,
                                  maximum: maximum,
                                  range: range)
    }
}
