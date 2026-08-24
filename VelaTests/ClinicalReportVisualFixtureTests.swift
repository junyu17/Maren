import Foundation
import PDFKit
import XCTest
@testable import Vela

/// 可选的临床报告视觉回归夹具。
///
/// 默认测试不会把 PDF 留在工作区。需要人工检查分页/字体时，设置
/// `VELA_PDF_FIXTURE_DIR` 后运行本测试，完整示例会被复制到该目录。
final class ClinicalReportVisualFixtureTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(offset: Int, from today: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Cal.startOfDay(today))!
    }

    func testClinicalReportVisualFixtureExportsWhenRequested() throws {
        guard let directoryPath = ProcessInfo.processInfo.environment["VELA_PDF_FIXTURE_DIR"],
              !directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // This is intentionally a no-op in ordinary test runs. The generated PDF is
            // only needed for a human visual inspection when the opt-in environment
            // variable is present.
            return
        }

        let today = Cal.startOfDay(Date())

        // Eight cycles with slightly different lengths, including several imported
        // Health rows, keep the report representative of a real review submission.
        let cycleOffsets = [-240, -210, -179, -149, -118, -88, -58, -28]
        let flowPatterns: [[FlowLevel]] = [
            [.light, .medium, .heavy, .medium],
            [.spotting, .light, .medium, .heavy, .medium],
            [.light, .medium, .heavy, .light],
            [.medium, .heavy, .medium, .light, .light],
            [.spotting, .light, .medium, .heavy],
            [.light, .medium, .heavy, .medium, .light],
            [.light, .medium, .medium, .light],
            [.spotting, .light, .medium, .heavy, .medium],
        ]

        var periods: [PeriodDay] = []
        for (cycleIndex, offset) in cycleOffsets.enumerated() {
            for (dayIndex, flow) in flowPatterns[cycleIndex].enumerated() {
                let period = PeriodDay(date: date(offset: offset + dayIndex, from: today), flow: flow)
                // Include both manual and Apple Health-origin period rows in the fixture.
                period.importedFromHealth = cycleIndex.isMultiple(of: 3)
                periods.append(period)
            }
        }

        // Daily rows intentionally cover most of the observed window. Health-origin
        // markers, BBT, spotting, and notes exercise the long report sections.
        var logs: [DailyLog] = []
        for offset in stride(from: -240, through: -1, by: 2) {
            let mood = Mood(rawValue: abs(offset) % 5 + 1)!
            let hasSpotting = offset.isMultiple(of: 14)
            let log = DailyLog(
                date: date(offset: offset, from: today),
                mood: mood,
                energy: abs(offset) % 5 + 1,
                pain: offset.isMultiple(of: 10) ? 3 : -1,
                sleepHours: 6.0 + Double(abs(offset) % 4) * 0.5,
                weight: 57.8 + Double(abs(offset) % 7) * 0.2,
                basalBodyTemperatureCelsius: 36.25 + Double(abs(offset) % 8) * 0.05,
                spotting: hasSpotting ? true : (offset.isMultiple(of: 22) ? false : nil),
                symptoms: offset.isMultiple(of: 6) ? ["cramps", "fatigue"] : ["headache"],
                note: Self.note(for: offset)
            )

            if offset.isMultiple(of: 4) {
                log.healthImportedFields = ["sleep", "weight"]
            }
            if offset.isMultiple(of: 9) {
                log.healthImportedFields.append("basalBodyTemperature")
            }
            logs.append(log)
        }

        let metformin = Medication(name: "二甲双胍", emoji: "💊")
        metformin.createdAt = date(offset: -230, from: today)
        let vitaminD = Medication(name: "Vitamin D", emoji: "☀️")
        vitaminD.createdAt = date(offset: -170, from: today)
        let medications = [metformin, vitaminD]

        var intakes: [MedicationIntake] = []
        for offset in stride(from: -220, through: -4, by: 3) {
            intakes.append(MedicationIntake(
                medicationId: metformin.id,
                dayKey: DayKey.from(date(offset: offset, from: today))))
        }
        for offset in stride(from: -160, through: -8, by: 5) {
            intakes.append(MedicationIntake(
                medicationId: vitaminD.id,
                dayKey: DayKey.from(date(offset: offset, from: today))))
        }

        let reportData = ClinicalReportEngine.ReportData(
            periodDays: periods,
            logs: logs,
            medications: medications,
            intakes: intakes,
            prediction: .empty,
            includeNotes: true,
            range: .all
        )

        guard let generatedURL = ClinicalReportEngine.generatePDF(from: reportData) else {
            XCTFail("Clinical report PDF generation failed")
            return
        }
        defer { ClinicalReportEngine.cleanupTempFile(generatedURL) }

        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fixtureURL = directoryURL.appendingPathComponent(
            "Vela-ClinicalReport-visual-fixture.pdf",
            isDirectory: false
        )

        // The output path is a narrow, explicit test artifact path. Replacing an older
        // fixture makes repeated visual checks deterministic without touching production
        // temporary files or any other user data.
        if FileManager.default.fileExists(atPath: fixtureURL.path) {
            try FileManager.default.removeItem(at: fixtureURL)
        }
        try FileManager.default.copyItem(at: generatedURL, to: fixtureURL)

        guard let document = PDFDocument(url: fixtureURL) else {
            XCTFail("Generated fixture is not a readable PDF: \(fixtureURL.path)")
            return
        }
        XCTAssertGreaterThan(document.pageCount, 2,
                             "Fixture should cover multiple pages for visual review")

        let allText = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(allText.contains("English clinical note"),
                      "Fixture should include the long English note")
        XCTAssertTrue(allText.contains("临床记录"),
                      "Fixture should include the long Chinese note")
        XCTAssertTrue(allText.contains("Apple"),
                      "Fixture should include Health-origin fields")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))
    }

    private static func note(for offset: Int) -> String {
        guard [-238, -180, -120, -60, -2].contains(offset) else { return "" }
        let chinese = String(repeating: "这是一条用于临床沟通的长备注，记录当天的身体感受、睡眠变化和周期阶段。", count: 5)
        let english = String(repeating: "English clinical note: symptoms and daily context were recorded locally for discussion with a healthcare professional. ", count: 4)
        return "临床记录（第 \(abs(offset)) 天）\n\(chinese)\n\(english)"
    }
}
