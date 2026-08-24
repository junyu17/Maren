import Foundation
import SwiftData
import XCTest
@testable import Vela

@MainActor
final class DedupSweepTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            PeriodDay.self,
            DailyLog.self,
            Medication.self,
            MedicationIntake.self,
            CustomSymptom.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }

    private func mergedLog(from container: ModelContainer) throws -> DailyLog {
        let context = ModelContext(container)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(logs.count, 1)
        return try XCTUnwrap(logs.first)
    }

    func testDailyLogDedupBackfillsNewFieldsAndUnionsImportedMarkers() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = date(2026, 8, 1)

        let winner = DailyLog(date: day, mood: .good, energy: 2, pain: 1,
                              sleepHours: 7, weight: 60,
                              symptoms: ["cramps"], note: "winner")
        winner.updatedAt = day.addingTimeInterval(120)
        winner.healthImportedFields = ["sleep"]

        let other = DailyLog(date: day, mood: .great, energy: 5, pain: 4,
                             sleepHours: 8, weight: 61,
                             symptoms: ["headache"], note: "other")
        other.updatedAt = day.addingTimeInterval(60)
        other.basalBodyTemperatureCelsius = 36.7
        other.spotting = false
        other.steps = 12_345
        other.exerciseMinutes = 42
        other.healthImportedFields = [
            "steps", "exercise", "basalBodyTemperature", "spotting", "weight"
        ]

        context.insert(winner)
        context.insert(other)
        try context.save()

        DedupSweep.run(in: container)
        let merged = try mergedLog(from: container)

        XCTAssertEqual(merged.mood, Mood.good)
        XCTAssertEqual(merged.energy, 2)
        XCTAssertEqual(merged.pain, 1)
        XCTAssertEqual(merged.sleepHours, Optional(7.0))
        XCTAssertEqual(merged.weight, Optional(60.0))
        XCTAssertEqual(merged.symptoms, ["cramps", "headache"])
        XCTAssertEqual(merged.note, "winner")
        XCTAssertEqual(merged.basalBodyTemperatureCelsius, 36.7)
        XCTAssertEqual(merged.spotting, Optional(false))
        XCTAssertEqual(merged.steps, 12_345)
        XCTAssertEqual(merged.exerciseMinutes, 42)
        XCTAssertEqual(merged.healthImportedFields, [
            "basalBodyTemperature", "exercise", "sleep", "spotting", "steps", "weight"
        ])
    }

    func testDailyLogDedupPreservesWinnerNewFields() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = date(2026, 8, 2)

        let winner = DailyLog(date: day)
        winner.updatedAt = day.addingTimeInterval(120)
        winner.basalBodyTemperatureCelsius = 36.4
        winner.spotting = false
        winner.steps = 1_000
        winner.exerciseMinutes = 10
        winner.healthImportedFields = ["exercise"]

        let other = DailyLog(date: day)
        other.updatedAt = day.addingTimeInterval(60)
        other.basalBodyTemperatureCelsius = 36.9
        other.spotting = true
        other.steps = 9_000
        other.exerciseMinutes = 90
        other.healthImportedFields = ["steps", "spotting", "basalBodyTemperature"]

        context.insert(winner)
        context.insert(other)
        try context.save()

        DedupSweep.run(in: container)
        let merged = try mergedLog(from: container)

        XCTAssertEqual(merged.basalBodyTemperatureCelsius, 36.4)
        XCTAssertEqual(merged.spotting, Optional(false))
        XCTAssertEqual(merged.steps, 1_000)
        XCTAssertEqual(merged.exerciseMinutes, 10)
        XCTAssertEqual(merged.healthImportedFields, [
            "basalBodyTemperature", "exercise", "spotting", "steps"
        ])
    }
}
