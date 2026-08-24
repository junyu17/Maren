import Foundation

/// Maren Review Engine — weekly and completed-cycle summaries.
/// Pure functions, no SwiftData / SwiftUI / network dependencies.
/// All inputs are raw arrays; views fetch via @Query.
enum MarenReviewEngine {

    // MARK: - DTOs

    enum ReviewCoverage: Int, Comparable {
        case empty = 0
        case limited = 1
        case ready = 2

        static func < (lhs: ReviewCoverage, rhs: ReviewCoverage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct MetricAverages: Equatable {
        var mood: Double?
        var energy: Double?
        var sleep: Double?
    }

    struct TrackerRanking: Equatable, Identifiable {
        let key: String
        let dayCount: Int
        var id: String { key }
    }

    struct ReviewWindow: Equatable {
        let startDayKey: Int
        let endDayKey: Int
        let recordedDayKeys: [Int]
    }

    struct ReviewComparison: Equatable {
        let moodDelta: Double?
        let energyDelta: Double?
        let sleepDelta: Double?
        let moodSimilar: Bool
        let energySimilar: Bool
        let sleepSimilar: Bool
    }

    struct WeeklyReviewResult: Equatable {
        let anchorDayKey: Int
        let currentWindow: ReviewWindow
        let previousWindow: ReviewWindow
        let periodDayCount: Int
        let reviewStatus: ReviewStatus
        let averages: MetricAverages
        let comparison: ReviewComparison?
        let topTrackers: [TrackerRanking]
    }

    struct CompletedCycleResult: Equatable {
        let startDayKey: Int
        let endDayKey: Int
        let cycleLength: Int
        let periodDays: Int
        let reviewStatus: ReviewStatus
        let averages: MetricAverages
        let topTrackers: [TrackerRanking]
        let gapOver120: Bool
        let recordedLogDays: Int
    }

    enum ReviewStatus: Int {
        case empty = 0
        case limited = 1
        case ready = 2
    }

    // MARK: - Access Policy

    struct AccessPolicy: OptionSet, Sendable {
        let rawValue: Int

        static let dateRange          = AccessPolicy(rawValue: 1 << 0)
        static let coverage           = AccessPolicy(rawValue: 1 << 1)
        static let periodDayCount     = AccessPolicy(rawValue: 1 << 2)
        static let cycleBoundary      = AccessPolicy(rawValue: 1 << 3)
        static let premiumPreview     = AccessPolicy(rawValue: 1 << 4)
        static let averages           = AccessPolicy(rawValue: 1 << 5)
        static let comparisons        = AccessPolicy(rawValue: 1 << 6)
        static let topTrackers        = AccessPolicy(rawValue: 1 << 7)
        static let cycleHistory       = AccessPolicy(rawValue: 1 << 8)

        static let freePolicy: AccessPolicy = [.dateRange, .coverage, .periodDayCount,
                                                .cycleBoundary, .premiumPreview]
        static let premiumPolicy: AccessPolicy = [.dateRange, .coverage, .periodDayCount,
                                                   .cycleBoundary, .averages, .comparisons,
                                                   .topTrackers, .cycleHistory]
    }

    static func accessPolicy(isPremium: Bool) -> AccessPolicy {
        isPremium ? .premiumPolicy : .freePolicy
    }

    // MARK: - Minimum sample thresholds

    private static let minMetricSamples = 3
    private static let minRecordedDaysForComparison = 3
    private static let minRecordedDaysForTrackers = 3
    private static let minTrackerDays = 2
    private static let maxTrackerCount = 3

    // MARK: - Weekly Review

    static func weeklyReview(anchorDayKey: Int,
                             periodDays: [PeriodDay],
                             logs: [DailyLog]) -> WeeklyReviewResult {
        let today = DayKey.today

        // Dedup logs and periodDays by dayKey
        let dedupedLogs = deduplicateLogs(logs)
        let dedupedPeriods = deduplicatePeriods(periodDays)

        // Current window: latest 7 local calendar days ending at anchorDayKey
        let currentEnd = min(anchorDayKey, today)
        let currentStart = dayKeyByAddingDays(-6, to: currentEnd)

        // Previous window: immediately preceding 7 days
        let previousEnd = dayKeyByAddingDays(-1, to: currentStart)
        let previousStart = dayKeyByAddingDays(-6, to: previousEnd)

        let currentWindow = windowLogs(startDayKey: currentStart,
                                       endDayKey: currentEnd,
                                       allLogs: dedupedLogs,
                                       allPeriods: dedupedPeriods)
        let previousWindow = windowLogs(startDayKey: previousStart,
                                        endDayKey: previousEnd,
                                        allLogs: dedupedLogs,
                                        allPeriods: dedupedPeriods)

        // Period days in current window
        let periodDayCount = Array(dedupedPeriods.values).filter {
            $0.dayKey >= currentStart && $0.dayKey <= currentEnd
        }.count

        // Review status
        let status: ReviewStatus
        switch currentWindow.recordedDayKeys.count {
        case 0: status = .empty
        case 1...2: status = .limited
        default: status = .ready
        }

        // Averages (current window)
        let currentLogs = logsInWindow(currentWindow, allLogs: dedupedLogs)
        let averages = computeAverages(logs: currentLogs)

        // Comparison
        let comparison: ReviewComparison?
        if currentWindow.recordedDayKeys.count >= minRecordedDaysForComparison,
           previousWindow.recordedDayKeys.count >= minRecordedDaysForComparison {
            let prevLogs = logsInWindow(previousWindow, allLogs: dedupedLogs)
            let prevAverages = computeAverages(logs: prevLogs)
            comparison = computeComparison(current: averages, previous: prevAverages)
        } else {
            comparison = nil
        }

        // Tracker ranking
        let trackers = rankTrackers(logs: currentLogs)

        return WeeklyReviewResult(
            anchorDayKey: currentEnd,
            currentWindow: currentWindow,
            previousWindow: previousWindow,
            periodDayCount: periodDayCount,
            reviewStatus: status,
            averages: averages,
            comparison: comparison,
            topTrackers: trackers
        )
    }

    // MARK: - Completed Cycle Summary

    /// Returns the latest completed recorded cycle, regardless of length.
    /// Use `cycleStartDayKey` to select a specific cycle for stable detail view.
    /// Always uses recorded-only prediction (`manual: nil`).
    static func completedCycleSummary(periodDays: [PeriodDay],
                                       logs: [DailyLog],
                                       cycleStartDayKey: Int? = nil,
                                       today: Date = Date()) -> CompletedCycleResult? {
        let dedupedLogs = deduplicateLogs(logs)
        let dedupedPeriods = deduplicatePeriods(periodDays)

        // Build recorded-only prediction (manual: nil)
        let prediction = CyclePredictor.predict(from: Array(dedupedPeriods.values), today: today, manual: nil)

        // Find completed cycles (length != nil)
        let completed = prediction.cycles
            .filter { $0.length != nil }
            .sorted { $0.start < $1.start }

        guard !completed.isEmpty else { return nil }

        let cycle: CyclePredictor.CycleRecord
        if let startKey = cycleStartDayKey {
            guard let matched = completed.first(where: { DayKey.from($0.start) == startKey }) else {
                return nil
            }
            cycle = matched
        } else {
            cycle = completed.last!
        }

        guard let length = cycle.length else { return nil }

        let startDayKey = DayKey.from(cycle.start)
        let endDate = Cal.current.date(byAdding: .day, value: length, to: cycle.start) ?? Date.distantFuture
        let endDayKey = DayKey.from(endDate)

        // Daily logs in range [startDayKey, endDayKey)
        let cycleLogs = Array(dedupedLogs.values).filter {
            $0.dayKey >= startDayKey && $0.dayKey < endDayKey
        }

        let status: ReviewStatus
        switch cycleLogs.count {
        case 0: status = .empty
        case 1...2: status = .limited
        default: status = .ready
        }

        let averages = computeAverages(logs: cycleLogs)
        let trackers = rankTrackers(logs: cycleLogs)

        let gapOver120 = length > 120

        return CompletedCycleResult(
            startDayKey: startDayKey,
            endDayKey: endDayKey,
            cycleLength: length,
            periodDays: cycle.periodDays,
            reviewStatus: status,
            averages: averages,
            topTrackers: trackers,
            gapOver120: gapOver120,
            recordedLogDays: cycleLogs.count
        )
    }

    /// All completed cycles for history/listing (recorded-only).
    static func allCompletedCycles(periodDays: [PeriodDay],
                                    logs: [DailyLog],
                                    today: Date = Date()) -> [CompletedCycleResult] {
        let dedupedLogs = deduplicateLogs(logs)
        let dedupedPeriods = deduplicatePeriods(periodDays)

        let prediction = CyclePredictor.predict(from: Array(dedupedPeriods.values), today: today, manual: nil)

        let completed = prediction.cycles
            .filter { $0.length != nil }
            .sorted { $0.start < $1.start }

        return completed.compactMap { cycle in
            guard let length = cycle.length else { return nil }
            let startDayKey = DayKey.from(cycle.start)
            let endDate = Cal.current.date(byAdding: .day, value: length, to: cycle.start) ?? Date.distantFuture
            let endDayKey = DayKey.from(endDate)

            let cycleLogs = Array(dedupedLogs.values).filter {
                $0.dayKey >= startDayKey && $0.dayKey < endDayKey
            }

            let status: ReviewStatus
            switch cycleLogs.count {
            case 0: status = .empty
            case 1...2: status = .limited
            default: status = .ready
            }

            let averages = computeAverages(logs: cycleLogs)
            let trackers = rankTrackers(logs: cycleLogs)
            let gapOver120 = length > 120

            return CompletedCycleResult(
                startDayKey: startDayKey,
                endDayKey: endDayKey,
                cycleLength: length,
                periodDays: cycle.periodDays,
                reviewStatus: status,
                averages: averages,
                topTrackers: trackers,
                gapOver120: gapOver120,
                recordedLogDays: cycleLogs.count
            )
        }
    }

    // MARK: - Internal: Window Helpers

    private static func windowLogs(startDayKey: Int,
                                   endDayKey: Int,
                                   allLogs: [Int: DeduplicatedLog],
                                   allPeriods: [Int: PeriodDay]) -> ReviewWindow {
        let recordedDayKeys = allLogs.keys.filter {
            $0 >= startDayKey && $0 <= endDayKey
        }.sorted()
        return ReviewWindow(startDayKey: startDayKey,
                            endDayKey: endDayKey,
                            recordedDayKeys: recordedDayKeys)
    }

    private static func logsInWindow(_ window: ReviewWindow,
                                     allLogs: [Int: DeduplicatedLog]) -> [DeduplicatedLog] {
        allLogs.values.filter {
            $0.dayKey >= window.startDayKey && $0.dayKey <= window.endDayKey
        }
    }

    // MARK: - Internal: Deduplication

    struct DeduplicatedLog {
        let dayKey: Int
        var moodRaw: Int
        var energy: Int
        var sleepHours: Double?
        var symptoms: Set<String>
        var updatedAt: Date

        var mood: Mood? { Mood(rawValue: moodRaw) }
    }

    static func deduplicateLogs(_ logs: [DailyLog]) -> [Int: DeduplicatedLog] {
        // A SwiftData store should contain one row per day, but imports and old
        // versions can leave duplicates behind.  Merge each scalar independently:
        // a newer row may have reset one field while still carrying a valid value
        // for another field.  Sorting by the input index makes equal timestamps
        // deterministic without treating an unset value as an intentional erase.
        var grouped: [Int: [(index: Int, log: DailyLog)]] = [:]
        for (index, log) in logs.enumerated() {
            grouped[log.dayKey, default: []].append((index: index, log: log))
        }

        return grouped.reduce(into: [Int: DeduplicatedLog]()) { result, entry in
            let key = entry.key
            let rows = entry.value.sorted {
                if $0.log.updatedAt != $1.log.updatedAt {
                    return $0.log.updatedAt < $1.log.updatedAt
                }
                return $0.index < $1.index
            }

            var moodRaw = 0
            var energy = 0
            var sleepHours: Double?
            var symptoms = Set<String>()
            var updatedAt = rows.first?.log.updatedAt ?? Date.distantPast

            for row in rows {
                let log = row.log
                symptoms.formUnion(log.symptoms)
                updatedAt = max(updatedAt, log.updatedAt)

                if (1...5).contains(log.moodRaw) {
                    moodRaw = log.moodRaw
                }
                if (1...5).contains(log.energy) {
                    energy = log.energy
                }
                if let value = log.sleepHours, value.isFinite, (0...24).contains(value) {
                    sleepHours = value
                }
            }

            result[key] = DeduplicatedLog(
                dayKey: key,
                moodRaw: moodRaw,
                energy: energy,
                sleepHours: sleepHours,
                symptoms: symptoms,
                updatedAt: updatedAt)
        }
    }

    static func deduplicatePeriods(_ periods: [PeriodDay]) -> [Int: PeriodDay] {
        var byKey: [Int: PeriodDay] = [:]
        for p in periods {
            if let existing = byKey[p.dayKey] {
                if p.updatedAt > existing.updatedAt { byKey[p.dayKey] = p }
            } else {
                byKey[p.dayKey] = p
            }
        }
        return byKey
    }

    // MARK: - Internal: Metric Averages

    static func computeAverages(logs: [DeduplicatedLog]) -> MetricAverages {
        let moodValues = logs.map(\.moodRaw).filter { (1...5).contains($0) }
        let energyValues = logs.map(\.energy).filter { (1...5).contains($0) }
        let sleepValues = logs.compactMap(\.sleepHours).filter { $0.isFinite && (0...24).contains($0) }

        return MetricAverages(
            mood: averageIfEnough(moodValues),
            energy: averageIfEnough(energyValues),
            sleep: averageIfEnough(sleepValues))
    }

    private static func averageIfEnough(_ values: [Int]) -> Double? {
        guard values.count >= minMetricSamples else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func averageIfEnough(_ values: [Double]) -> Double? {
        guard values.count >= minMetricSamples else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Internal: Comparison

    static func computeComparison(current: MetricAverages,
                                  previous: MetricAverages) -> ReviewComparison? {
        let moodDelta: Double? = {
            guard let c = current.mood, let p = previous.mood else { return nil }
            return c - p
        }()
        let energyDelta: Double? = {
            guard let c = current.energy, let p = previous.energy else { return nil }
            return c - p
        }()
        let sleepDelta: Double? = {
            guard let c = current.sleep, let p = previous.sleep else { return nil }
            return c - p
        }()

        guard moodDelta != nil || energyDelta != nil || sleepDelta != nil else {
            return nil
        }

        return ReviewComparison(
            moodDelta: moodDelta,
            energyDelta: energyDelta,
            sleepDelta: sleepDelta,
            moodSimilar: moodDelta.map { abs($0) <= 0.3 } ?? true,
            energySimilar: energyDelta.map { abs($0) <= 0.3 } ?? true,
            sleepSimilar: sleepDelta.map { abs($0) <= 0.3 } ?? true)
    }

    // MARK: - Internal: Tracker Ranking

    static func rankTrackers(logs: [DeduplicatedLog]) -> [TrackerRanking] {
        guard logs.count >= minRecordedDaysForTrackers else { return [] }

        var dayCounts: [String: Int] = [:]
        for log in logs {
            for key in log.symptoms {
                dayCounts[key, default: 0] += 1
            }
        }

        return dayCounts
            .filter { $0.value >= minTrackerDays }
            .map { TrackerRanking(key: $0.key, dayCount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.dayCount != rhs.dayCount { return lhs.dayCount > rhs.dayCount }
                return lhs.key < rhs.key
            }
            .prefix(maxTrackerCount)
            .map { $0 }
    }

    // MARK: - Internal: Day Arithmetic

    static func dayKeyByAddingDays(_ days: Int, to dayKey: Int) -> Int {
        let date = DayKey.date(from: dayKey)
        guard let shifted = Cal.current.date(byAdding: .day, value: days, to: date) else {
            return dayKey
        }
        return DayKey.from(shifted)
    }

    /// Calendar day difference from `fromDate` to `toDate` (midnight to midnight).
    static func calendarDaysBetween(_ fromDate: Date, _ toDate: Date) -> Int {
        Cal.current.dateComponents([.day], from: Cal.startOfDay(fromDate), to: Cal.startOfDay(toDate)).day ?? 0
    }
}
