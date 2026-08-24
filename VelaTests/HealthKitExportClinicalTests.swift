import Foundation
import XCTest
@testable import Vela

/// Focused regression coverage for the HealthKit-aware export and report paths.
final class HealthKitExportClinicalTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testPeriodCSVKeepsStableHealthOriginColumns() {
        let period = PeriodDay(date: date(2026, 1, 10), flow: .medium)
        period.importedFromHealth = true

        let csv = DataExport.periodCSV([period])
        let header = csv.components(separatedBy: "\n").first!

        XCTAssertTrue(header.contains("flow_code"))
        XCTAssertTrue(header.contains("imported_from_health"))
        XCTAssertTrue(header.contains("source_label"))
        XCTAssertTrue(csv.contains(",true,"))
    }

    func testLogCSVExportsBBTSpottingAndImportedFieldMarkers() {
        let log = DailyLog(
            date: date(2026, 1, 11),
            steps: 12_345,
            exerciseMinutes: 42,
            basalBodyTemperatureCelsius: 36.42,
            spotting: true
        )
        log.healthImportedFields = [
            HealthKitPlanners.FieldKey.weight.rawValue,
            HealthKitPlanners.FieldKey.basalBodyTemperature.rawValue,
            HealthKitPlanners.FieldKey.steps.rawValue,
            HealthKitPlanners.FieldKey.exercise.rawValue
        ]

        let csv = DataExport.logCSV([log])
        let header = csv.components(separatedBy: "\n").first!

        XCTAssertTrue(header.contains("basal_body_temperature_celsius"))
        XCTAssertTrue(header.contains("spotting"))
        XCTAssertTrue(header.contains("steps"))
        XCTAssertTrue(header.contains("exercise_minutes"))
        XCTAssertTrue(header.contains("health_imported_fields"))
        XCTAssertTrue(header.contains("source_label"))
        XCTAssertTrue(csv.contains("36.42"))
        XCTAssertTrue(csv.contains(",12345,42,"))
        XCTAssertTrue(csv.contains(",true,basalBodyTemperature|exercise|steps|weight,"))
        XCTAssertTrue(csv.contains("Maren + Apple 健康"))
    }

    func testLogCSVLeavesOptionalActivityValuesBlankAndEscapesNotes() {
        let log = DailyLog(date: date(2026, 1, 12), note: "hello, \"quoted\"\nline")
        let csv = DataExport.logCSV([log])
        let lines = csv.components(separatedBy: "\n")
        let header = lines.first!

        XCTAssertTrue(header.contains("steps"))
        XCTAssertTrue(header.contains("exercise_minutes"))
        XCTAssertTrue(csv.contains("\"hello, \"\"quoted\"\"\nline\""))
        XCTAssertFalse(csv.contains(",0,0,"))
    }

    func testContraceptionCSVExportsConfiguredProfileAndNoneAsNotConfigured() {
        let updatedAt = date(2026, 1, 13)
        let configured = ContraceptionSettings(
            method: .pill,
            startDayKey: 20260113,
            reminderEnabled: true,
            reminderHour: 8,
            reminderMinute: 5,
            note: "note, local",
            updatedAt: updatedAt)
        let configuredCSV = DataExport.contraceptionSettingsCSV(profile: configured)

        XCTAssertTrue(configuredCSV.contains("configured,method,start_day_key"))
        XCTAssertTrue(configuredCSV.contains("true,pill,20260113,true,8,5"))
        XCTAssertTrue(configuredCSV.contains("\"note, local\""))

        let noneCSV = DataExport.contraceptionSettingsCSV(
            profile: ContraceptionSettings(method: .none, note: "ignored"))
        XCTAssertTrue(noneCSV.contains("false,,,,,,,"))
        XCTAssertFalse(noneCSV.contains(",none,"))
        XCTAssertFalse(noneCSV.contains("ignored"))
    }

    func testClinicalStatsIncludeBBTAverageAndSpottingCounts() {
        let logs = [
            DailyLog(
                date: date(2026, 2, 1),
                basalBodyTemperatureCelsius: 36.4,
                spotting: true
            ),
            DailyLog(
                date: date(2026, 2, 2),
                basalBodyTemperatureCelsius: 36.6,
                spotting: false
            ),
            DailyLog(
                date: date(2026, 2, 3),
                basalBodyTemperatureCelsius: 45.0
            )
        ]

        let stats = ClinicalReportEngine.computeStats(
            periods: [],
            logs: logs,
            intakes: [],
            medications: [],
            rangeStart: date(2026, 2, 1),
            rangeEnd: date(2026, 2, 3)
        )

        XCTAssertEqual(stats.avgBasalBodyTemperatureCelsius ?? .nan, 36.5, accuracy: 0.000_001)
        XCTAssertEqual(stats.spottingDays, 1)
        XCTAssertEqual(stats.spottingRecordedDays, 2)
    }

    func testSampleDataDemonstratesBBTAndSpottingWithoutPersistence() {
        XCTAssertTrue(SampleData.dailyLogs.contains { $0.basalBodyTemperatureCelsius != nil })
        XCTAssertTrue(SampleData.dailyLogs.contains { $0.spotting != nil })
        XCTAssertTrue(SampleData.selfCheck())
    }
}
