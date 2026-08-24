import Foundation

/// Foundation-only, side-effect-free planners for HealthKit import/export logic.
/// No HealthKit, SwiftData, or UserDependencies dependencies.
enum HealthKitPlanners {

    // MARK: - Field Keys

    /// Canonical field identifiers for HealthKit sync selection.
    enum FieldKey: String, CaseIterable {
        case sleep
        case weight
        case basalBodyTemperature
        case spotting
        case steps
        case exercise
    }

    // MARK: - Core Value Types

    /// Half-open time interval [start, end).
    struct Interval: Equatable, Sendable {
        let start: Date
        let end: Date
    }

    /// Single sample with provenance.
    struct DatedValue: Equatable, Sendable {
        let date: Date
        let value: Double
        let sourceIdentifier: String
    }

    /// Aggregated value for a calendar day.
    struct DailyValue: Equatable, Sendable {
        let dayKey: Int
        let value: Double
    }

    // MARK: - Selection Migration

    /// Migrates legacy selection state to the current `FieldKey` model.
    /// - Parameters:
    ///   - saved: Previously persisted dictionary (explicit false entries mean "disabled"; nil means no record).
    ///   - oldSyncEnabled: Legacy single-toggle state (true → menstrual only).
    ///   - menstrualIdentifier: Identifier string for menstrual flow (e.g., HKCategoryTypeIdentifier.menstrualFlow.rawValue).
    ///   - supported: Current supported type identifiers.
    /// - Returns: Set of identifiers that should be enabled after migration.
    static func selectionMigration(
        saved: [String: Bool]?,
        oldSyncEnabled: Bool,
        menstrualIdentifier: String,
        supported: Set<String>
    ) -> Set<String> {
        if let saved {
            let explicit = saved.filter { $0.value }.keys
            return supported.intersection(explicit)
        }
        if oldSyncEnabled {
            return supported.intersection([menstrualIdentifier])
        }
        return []
    }

    // MARK: - Day Key

    /// Computes yyyymmdd day key using the supplied calendar.
    static func dayKey(for date: Date, calendar: Calendar) -> Int {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return (comps.year ?? 1970) * 10_000 + (comps.month ?? 1) * 100 + (comps.day ?? 1)
    }

    /// Returns the half-open calendar-day interval containing `date`.
    /// Calendar arithmetic keeps the interval DST-safe (for example, a local
    /// spring-forward day is 23 elapsed hours and a fall-back day is 25).
    static func dailyRange(for date: Date, calendar: Calendar) -> Interval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return Interval(start: start, end: end)
    }

    /// Splits a half-open range into clipped, calendar-day intervals.
    /// The supplied calendar controls both day boundaries and DST behavior.
    static func dailyRanges(
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [Interval] {
        guard start < end else { return [] }

        var cursor = calendar.startOfDay(for: start)
        var ranges: [Interval] = []
        while cursor < end {
            let day = dailyRange(for: cursor, calendar: calendar)
            guard day.end > cursor else { break }
            let clippedStart = Swift.max(start, day.start)
            let clippedEnd = Swift.min(end, day.end)
            if clippedStart < clippedEnd {
                ranges.append(Interval(start: clippedStart, end: clippedEnd))
            }
            cursor = day.end
        }
        return ranges
    }

    // MARK: - Sleep Interval Merging

    /// Merges overlapping/adjacent sleep intervals.
    /// - Filters out intervals where end <= start or non-finite time intervals.
    /// - Returns merged intervals sorted by start.
    static func unionSleepIntervals(_ intervals: [Interval]) -> [Interval] {
        let valid = intervals.filter { $0.end > $0.start && $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite }
        guard !valid.isEmpty else { return [] }
        let sorted = valid.sorted { $0.start < $1.start }
        var merged: [Interval] = []
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                current = Interval(start: current.start, end: max(current.end, next.end))
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    // MARK: - Sleep Split by Calendar Day

    /// Splits merged sleep intervals into per-calendar-day hour totals.
    /// - Handles DST transitions (23/25-hour days) by using actual elapsed seconds.
    /// - Rejects non-finite durations; caps at 24 actual hours per calendar day.
    /// - Returns [dayKey: hours].
    static func splitSleepIntervalsByDay(_ intervals: [Interval], calendar: Calendar) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for interval in intervals {
            var cursor = interval.start
            while cursor < interval.end {
                let dayStart = calendar.startOfDay(for: cursor)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let segmentEnd = min(interval.end, dayEnd)
                let seconds = segmentEnd.timeIntervalSince(cursor)
                guard seconds.isFinite, seconds > 0 else { break }
                let hours = min(seconds / 3600.0, 24)
                let key = dayKey(for: cursor, calendar: calendar)
                result[key, default: 0] += hours
                cursor = segmentEnd
            }
        }
        return result.filter { $0.value.isFinite && $0.value > 0 && $0.value <= 24 }
    }

    // MARK: - Latest Valid Value Per Day

    /// Selects the latest valid sample per calendar day, excluding a source.
    /// - Parameters:
    ///   - samples: All samples to consider.
    ///   - calendar: Calendar for day grouping.
    ///   - excludingSourceIdentifier: Source identifier to ignore (e.g., our own bundle ID).
    ///   - isValid: Predicate to validate the numeric value.
    /// - Returns: [dayKey: value] of the latest valid sample per day.
    static func latestValidValuesByDay(
        _ samples: [DatedValue],
        calendar: Calendar,
        excludingSourceIdentifier: String,
        isValid: (Double) -> Bool
    ) -> [Int: Double] {
        var latestPerDay: [Int: (date: Date, value: Double)] = [:]
        for sample in samples {
            guard sample.sourceIdentifier != excludingSourceIdentifier else { continue }
            guard sample.value.isFinite, isValid(sample.value) else { continue }
            let key = dayKey(for: sample.date, calendar: calendar)
            if let existing = latestPerDay[key] {
                if sample.date > existing.date {
                    latestPerDay[key] = (sample.date, sample.value)
                }
            } else {
                latestPerDay[key] = (sample.date, sample.value)
            }
        }
        return Dictionary(uniqueKeysWithValues: latestPerDay.map { ($0.key, $0.value.value) })
    }

    // MARK: - Validators

    /// Valid weight range: 20...400 kg.
    static func isValidWeight(_ kg: Double) -> Bool {
        kg.isFinite && kg >= 20 && kg <= 400
    }

    /// Valid basal body temperature range: 33...43 °C.
    static func isValidBasalBodyTemperature(_ celsius: Double) -> Bool {
        celsius.isFinite && celsius >= 33 && celsius <= 43
    }

    /// Valid sleep duration: >0...24 hours.
    static func isValidSleepHours(_ hours: Double) -> Bool {
        hours.isFinite && hours > 0 && hours <= 24
    }

    /// Valid daily step total: 0...200,000 count units.
    static func isValidSteps(_ steps: Int) -> Bool {
        (0...200_000).contains(steps)
    }

    /// Converts a finite HealthKit cumulative step total to the app's Int
    /// representation, rejecting values outside the supported daily range.
    static func normalizedSteps(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value <= 200_000 else { return nil }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        guard rounded >= 0, rounded <= 200_000 else { return nil }
        let steps = Int(rounded)
        return isValidSteps(steps) ? steps : nil
    }

    /// Valid daily exercise total: 0...1,440 minute units.
    static func isValidExerciseMinutes(_ minutes: Int) -> Bool {
        (0...1_440).contains(minutes)
    }

    /// Converts a finite HealthKit cumulative exercise total to whole minutes,
    /// rejecting values outside the supported daily range.
    static func normalizedExerciseMinutes(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value <= 1_440 else { return nil }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        guard rounded >= 0, rounded <= 1_440 else { return nil }
        let minutes = Int(rounded)
        return isValidExerciseMinutes(minutes) ? minutes : nil
    }

    // MARK: - Import Rules

    /// Determines whether a field should be imported from HealthKit.
    /// - Returns: true only if the local value is not recorded OR the field is already marked as imported.
    static func shouldImportField(
        localValueIsRecorded: Bool,
        importedFields: Set<FieldKey>,
        field: FieldKey
    ) -> Bool {
        !localValueIsRecorded || importedFields.contains(field)
    }

    /// Returns an updated set of imported-field markers.
    static func updatedImportedFields(
        existing: Set<FieldKey>,
        field: FieldKey,
        imported: Bool
    ) -> Set<FieldKey> {
        var updated = existing
        if imported {
            updated.insert(field)
        } else {
            updated.remove(field)
        }
        return updated
    }

    /// Determines whether a period day should be imported/updated from HealthKit.
    /// - Returns: true for nil (no local record) or true (already imported); false for manually created.
    static func shouldImportPeriodDay(existingImportedFromHealth: Bool?) -> Bool {
        existingImportedFromHealth != false
    }

    // MARK: - Lookback Window

    /// Clamps requested lookback days to 1...maximum (default 730 ≈ 2 years).
    static func clampedLookbackDays(requested: Int, maximum: Int = 730) -> Int {
        Swift.min(Swift.max(requested, 1), maximum)
    }

    /// Computes the import date range [start, now) using clamped lookback days.
    static func importDateRange(now: Date, requestedDays: Int, calendar: Calendar) -> (start: Date, end: Date) {
        let days = clampedLookbackDays(requested: requestedDays)
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        return (start, now)
    }

    // MARK: - Menstrual Cycle Start Metadata

    /// Computes the `HKMetadataKeyMenstrualCycleStart` value for each local
    /// period day.  HealthKit stores this bit on every sample, so changing one
    /// day can also require rewriting the immediately following local day:
    /// inserting a day can turn the old first day into a continuation, while
    /// deleting a first day can promote the next day to a new cycle start.
    ///
    /// `dayKeys` may be unsorted and may contain duplicates (for example while
    /// a legacy store is being repaired).  The result is keyed by the unique
    /// day key and therefore remains deterministic.
    static func cycleStartFlags(
        for dayKeys: [Int],
        calendar: Calendar
    ) -> [Int: Bool] {
        let sorted = Array(Set(dayKeys)).sorted()
        guard !sorted.isEmpty else { return [:] }

        func date(for dayKey: Int) -> Date? {
            var components = DateComponents()
            components.year = dayKey / 10_000
            components.month = (dayKey / 100) % 100
            components.day = dayKey % 100
            return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
        }

        var result: [Int: Bool] = [:]
        for (index, dayKey) in sorted.enumerated() {
            guard index > 0,
                  let previousDate = date(for: sorted[index - 1]),
                  let currentDate = date(for: dayKey) else {
                result[dayKey] = true
                continue
            }
            let gap = calendar.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            result[dayKey] = gap > 1
        }
        return result
    }

    /// Returns the local period-day keys whose HealthKit cycle-start metadata
    /// may change after one period day is inserted, edited, or deleted.
    ///
    /// HealthKit stores the cycle-start bit on every sample.  The changed day
    /// and its immediate successor are therefore the only samples that need
    /// rewriting for an upsert; after a deletion, the next remaining local
    /// day is promoted (or confirmed) as the new boundary.  Imported Health
    /// days are excluded by the caller before invoking this pure planner.
    static func periodDayKeysToResync(
        afterChanging changedDayKey: Int,
        existingDayKeys: [Int],
        deleting: Bool
    ) -> [Int] {
        let sorted = Array(Set(existingDayKeys)).sorted()
        guard deleting else {
            guard let index = sorted.firstIndex(of: changedDayKey) else { return [] }
            return Array(sorted[index..<min(index + 2, sorted.count)])
        }
        guard let next = sorted.first(where: { $0 > changedDayKey }) else { return [] }
        return [next]
    }
}
