import XCTest
import SwiftData
import PDFKit
@testable import Vela

/// 自动化回归测试:验证核心统计/预测引擎的正确性。
/// 使用固定日期和确定性输入,不依赖 UI 或网络。
final class ClinicalReportEngineTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return cal.date(from: c)!
    }

    // MARK: - 1. 连续 4 天经期不被拆成 2 段

    func testFourConsecutiveDaysOneSpan() {
        let periods = (0..<4).map { PeriodDay(date: date(2026, 1, 10 + $0), flow: .medium) }
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        // 4 天连续 → 1 个起点段 → 无间隔 → observedCycles = 0
        XCTAssertEqual(stats.observedCycles, 0)
        XCTAssertEqual(stats.avgPeriodLength, 4.0)
    }

    // MARK: - 2. 连续 5 天经期

    func testFiveConsecutiveDaysOneSpan() {
        let periods = (0..<5).map { PeriodDay(date: date(2026, 1, 10 + $0), flow: .medium) }
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        XCTAssertEqual(stats.observedCycles, 0)
        XCTAssertEqual(stats.avgPeriodLength, 5.0)
    }

    // MARK: - 3. gap <= 2 天仍算同一段

    func testGapWithinTwoDaysStillOneSpan() {
        // Day 10, 11, 13, 14 (gap of 2 between 11 and 13)
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 10), flow: .light),
            PeriodDay(date: date(2026, 1, 11), flow: .medium),
            PeriodDay(date: date(2026, 1, 13), flow: .medium),
            PeriodDay(date: date(2026, 1, 14), flow: .light),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        XCTAssertEqual(stats.avgPeriodLength, 4.0)
    }

    // MARK: - 4. gap > 2 天拆成 2 段

    func testGapMoreThanTwoDaysSplitsSpans() {
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 10), flow: .light),
            PeriodDay(date: date(2026, 1, 11), flow: .medium),
            PeriodDay(date: date(2026, 1, 15), flow: .light),
            PeriodDay(date: date(2026, 1, 16), flow: .medium),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        // 2 段各 2 天
        XCTAssertEqual(stats.avgPeriodLength, 2.0)
    }

    // MARK: - 5. 重复日期去重

    func testDuplicateDatesDeduped() {
        let d = date(2026, 1, 10)
        let periods = [
            PeriodDay(date: d, flow: .light),
            PeriodDay(date: d, flow: .heavy),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        XCTAssertEqual(stats.avgPeriodLength, 1.0)
    }

    // MARK: - 6. 未来日期排除

    func testFutureDatesExcluded() {
        let future = date(2099, 1, 1)
        let past = date(2026, 1, 10)
        let periods = [
            PeriodDay(date: past, flow: .medium),
            PeriodDay(date: future, flow: .medium),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [],
            rangeStart: nil, rangeEnd: date(2026, 12, 31))
        // 未来日期被 rangeEnd 过滤
        XCTAssertEqual(stats.avgPeriodLength, 1.0)
    }

    // MARK: - 18. effectiveEnd 使未来记录被排除(确定性)

    func testEffectiveEndExcludesFutureRecords() {
        let pastDate = date(2026, 1, 10)
        let futureDate = date(2099, 6, 15)
        let effectiveEnd = Cal.startOfDay(date(2026, 6, 1))

        let periods = [
            PeriodDay(date: pastDate, flow: .medium),
            PeriodDay(date: futureDate, flow: .heavy),
        ]
        let logs: [DailyLog] = [
            DailyLog(date: pastDate, mood: .good),
            DailyLog(date: futureDate, mood: .great),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: logs, intakes: [], medications: [],
            rangeStart: nil, rangeEnd: nil, effectiveEnd: effectiveEnd)
        // 未来日期被 effectiveEnd 过滤:只有 1 个 past 经期日
        XCTAssertEqual(stats.flowDistribution.values.reduce(0, +), 1,
                       "flowDistribution should only count past records")
        // avgMood 应只反映 past mood(.good = 3),不是 future mood(.great = 5)
        XCTAssertNotNil(stats.avgMood)
        XCTAssertEqual(stats.avgMood!, Double(Mood.good.rawValue), accuracy: 0.01,
                       "avgMood should equal the past mood, not the future mood")
    }

    // MARK: - 7. 周期长度仅计 15-120 天范围

    func testCycleLengthOnlyCounts15to120() {
        let today = Cal.startOfDay(Date())
        // 两段经期间隔 10 天(太短,不算有效周期)
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 10), flow: .medium),
            PeriodDay(date: date(2026, 1, 12), flow: .medium),
            PeriodDay(date: date(2026, 1, 22), flow: .medium),  // 间隔 10 天 < 15
            PeriodDay(date: date(2026, 1, 24), flow: .medium),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [],
            rangeStart: nil, rangeEnd: today)
        // 无有效周期长度(10 < 15)
        XCTAssertEqual(stats.observedCycles, 0)
        XCTAssertNil(stats.avgCycleLength)
    }

    // MARK: - 8. 计算统计包括 2 个有效周期

    func testTwoValidCycleLengths() {
        let periods: [PeriodDay] = [
            // 周期 1: 起点 1 月 10 日
            PeriodDay(date: date(2026, 1, 10), flow: .medium),
            PeriodDay(date: date(2026, 1, 12), flow: .medium),
            // 周期 2: 起点 2 月 9 日(间隔 30 天)
            PeriodDay(date: date(2026, 2, 9), flow: .medium),
            PeriodDay(date: date(2026, 2, 11), flow: .medium),
            // 周期 3: 起点 3 月 11 日(间隔 30 天)
            PeriodDay(date: date(2026, 3, 11), flow: .medium),
            PeriodDay(date: date(2026, 3, 13), flow: .medium),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        XCTAssertEqual(stats.observedCycles, 2)
        XCTAssertEqual(stats.avgCycleLength, 30.0)
        XCTAssertEqual(stats.minCycleLength, 30)
        XCTAssertEqual(stats.maxCycleLength, 30)
    }

    // MARK: - 9. observedCycles 反映有效长度数

    func testObservedCyclesReflectsValidLengths() {
        // 3 个周期起点,但第 2 个间隔太短(10 天)
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 10), flow: .medium),
            PeriodDay(date: date(2026, 1, 12), flow: .medium),
            PeriodDay(date: date(2026, 1, 22), flow: .medium),  // 10 天后,不计
            PeriodDay(date: date(2026, 1, 24), flow: .medium),
            PeriodDay(date: date(2026, 2, 21), flow: .medium),  // 42 天后(从 1/10),计
            PeriodDay(date: date(2026, 2, 23), flow: .medium),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [])
        // 只有 1 个有效周期长度(42 天)
        XCTAssertEqual(stats.observedCycles, 1)
        XCTAssertEqual(stats.avgCycleLength, 42.0)
    }

    // MARK: - 10. totalDaysInRange 使用过滤后实际边界

    func testTotalDaysInRangeUsesFilteredBounds() {
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
            PeriodDay(date: date(2026, 3, 31), flow: .medium),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [],
            rangeStart: date(2026, 1, 15), rangeEnd: date(2026, 3, 15))
        // 1/15 到 3/15 = 60 天
        XCTAssertEqual(stats.totalDaysInRange, 60)
    }

    // MARK: - 11. computeRegularity 从过滤后周期计算

    func testComputeRegularityFromFilteredPeriods() {
        // 创建规律周期(间隔 28 天,标准差 ≈ 0)
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
            PeriodDay(date: date(2026, 1, 29), flow: .medium),  // 28 天
            PeriodDay(date: date(2026, 2, 26), flow: .medium),  // 28 天
        ]
        let reg = ClinicalReportEngine.computeRegularity(from: periods)
        XCTAssertEqual(reg, String(localized: "规律"))
    }

    // MARK: - 12. 空数据不崩溃

    func testEmptyDataNoCrash() {
        let stats = ClinicalReportEngine.computeStats(
            periods: [], logs: [], intakes: [], medications: [])
        XCTAssertEqual(stats.observedCycles, 0)
        XCTAssertNil(stats.avgCycleLength)
        XCTAssertNil(stats.avgPeriodLength)
    }

    // MARK: - 14. 空经期 + 非空日志仍计算心情/睡眠/体重/追踪项

    func testEmptyPeriodsWithNonemptyLogsComputesDailyStats() {
        let logs: [DailyLog] = [
            DailyLog(date: date(2026, 1, 10), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 1, 11), mood: .okay, sleepHours: 7.0, weight: 60.0),
            DailyLog(date: date(2026, 1, 12), mood: .great, sleepHours: 8.0, weight: 59.5,
                     symptoms: ["cramps", "fatigue"]),
        ]
        let stats = ClinicalReportEngine.computeStats(
            periods: [], logs: logs, intakes: [], medications: [])
        // 经期为空 → observedCycles = 0
        XCTAssertEqual(stats.observedCycles, 0)
        XCTAssertNil(stats.avgPeriodLength)
        // 但心情/睡眠/体重/追踪项仍应被计算
        XCTAssertNotNil(stats.avgMood)
        XCTAssertNotNil(stats.avgSleep)
        XCTAssertNotNil(stats.avgWeight)
        XCTAssertFalse(stats.topTrackers.isEmpty)
    }

    // MARK: - 15. computeStats 内部按 rangeStart/rangeEnd 过滤

    func testComputeStatsFiltersDataInternally() {
        let today = Cal.startOfDay(Date())
        let past = date(2026, 1, 10)
        let future = date(2099, 1, 1)

        let periods: [PeriodDay] = [
            PeriodDay(date: past, flow: .medium),
            PeriodDay(date: future, flow: .medium),
        ]
        let logs: [DailyLog] = [
            DailyLog(date: past, mood: .good, symptoms: ["cramps"]),
            DailyLog(date: future, mood: .good),
        ]

        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: logs, intakes: [], medications: [],
            rangeStart: nil, rangeEnd: today)

        // 未来日期被过滤:只有 1 个经期日
        XCTAssertEqual(stats.avgPeriodLength, 1.0)
        // 未来日志不影响心情
        XCTAssertNotNil(stats.avgMood)
        XCTAssertEqual(stats.topTrackers.count, 1)
        XCTAssertEqual(stats.topTrackers.first?.0, "cramps")
    }

    // MARK: - 16. totalDaysInRange 使用显式范围

    func testTotalDaysInRangeUsesExplicitRange() {
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
        ]
        // 范围为 1/1 到 3/31 = 90 天
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: [], intakes: [], medications: [],
            rangeStart: date(2026, 1, 1), rangeEnd: date(2026, 3, 31))
        XCTAssertEqual(stats.totalDaysInRange, 90)
    }

    // MARK: - 17. all-time 范围用最早记录(跨 periods/logs/intakes)

    func testAllTimeUsesEarliestRecordAcrossDataTypes() {
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 3, 1), flow: .medium),
        ]
        let logs: [DailyLog] = [
            DailyLog(date: date(2026, 1, 1), mood: .good),
        ]
        let effectiveEnd = Cal.startOfDay(date(2026, 6, 1))
        let stats = ClinicalReportEngine.computeStats(
            periods: periods, logs: logs, intakes: [], medications: [],
            rangeStart: nil, rangeEnd: nil, effectiveEnd: effectiveEnd)
        // all-time: 1/1 到 6/1 = 152 天
        let expected = Cal.daysBetween(date(2026, 1, 1), effectiveEnd) + 1
        XCTAssertEqual(stats.totalDaysInRange, expected)
    }

    // MARK: - 13. PDF 生成不崩溃(含 file protection)

    func testPDFGenerationDoesNotCrash() {
        let periods = (0..<5).map { PeriodDay(date: date(2026, 1, 10 + $0), flow: .medium) }
        let data = ClinicalReportEngine.ReportData(
            periodDays: periods, logs: [], medications: [], intakes: [],
            prediction: .empty, includeNotes: false, range: .sixMonths)
        let url = ClinicalReportEngine.generatePDF(from: data)
        XCTAssertNotNil(url)
        if let url = url {
            // 验证文件存在且可读
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            // 清理
            ClinicalReportEngine.cleanupTempFile(url)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    // MARK: - 19. PDF 长备注不分页裁剪(回归测试)

    func testPDFLongNoteNotTruncatedAcrossPages() {
        let sentinel = "SENTINELA7X3END"
        let longNote = String(repeating: "这是一段很长的备注内容,用来测试PDF分页算法是否能正确处理超长无换行文本。", count: 200) + sentinel
        let log = DailyLog(date: date(2026, 3, 15), mood: .good, note: longNote)
        let data = ClinicalReportEngine.ReportData(
            periodDays: [], logs: [log], medications: [], intakes: [],
            prediction: .empty, includeNotes: true, range: .sixMonths)
        let url = ClinicalReportEngine.generatePDF(from: data)
        XCTAssertNotNil(url)
        guard let url = url else { return }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 50_000,
                             "PDF with 200 repeated long paragraphs should be substantial")

        guard let pdfDoc = PDFDocument(url: url) else {
            XCTFail("Failed to open generated PDF")
            ClinicalReportEngine.cleanupTempFile(url)
            return
        }
        XCTAssertGreaterThan(pdfDoc.pageCount, 1,
                             "Long note should span multiple pages")

        var allTextNormalized = ""
        for i in 0..<pdfDoc.pageCount {
            if let page = pdfDoc.page(at: i), let pageStr = page.string {
                let normalized = pageStr.components(separatedBy: .whitespacesAndNewlines).joined()
                allTextNormalized += normalized
            }
        }

        XCTAssertTrue(allTextNormalized.contains(sentinel),
                      "PDF page text must contain sentinel — note tail was truncated across pages")
        ClinicalReportEngine.cleanupTempFile(url)
    }

    // MARK: - 20. PDF 长备注完整性(更强断言)

    func testPDFLongNoteFullCoverageAcrossPages() {
        let headSentinel = "HEADA7X3START"
        let tailSentinel = "TAILA7X3END"
        let body = String(repeating: "这是一段很长的备注内容,用来测试PDF分页算法。1234567890 ", count: 300)
        let longNote = headSentinel + body + tailSentinel
        let log = DailyLog(date: date(2026, 3, 15), mood: .good, note: longNote)
        let data = ClinicalReportEngine.ReportData(
            periodDays: [], logs: [log], medications: [], intakes: [],
            prediction: .empty, includeNotes: true, range: .sixMonths)
        let url = ClinicalReportEngine.generatePDF(from: data)
        XCTAssertNotNil(url)
        guard let url = url else { return }

        guard let pdfDoc = PDFDocument(url: url) else {
            XCTFail("Failed to open generated PDF")
            ClinicalReportEngine.cleanupTempFile(url)
            return
        }
        XCTAssertGreaterThanOrEqual(pdfDoc.pageCount, 3,
                                     "Very long note should span at least 3 pages")

        var allTextNormalized = ""
        var pageTexts: [String] = []
        for i in 0..<pdfDoc.pageCount {
            if let page = pdfDoc.page(at: i), let pageStr = page.string {
                let normalized = pageStr.components(separatedBy: .whitespacesAndNewlines).joined()
                allTextNormalized += normalized
                pageTexts.append(normalized)
            } else {
                pageTexts.append("")
            }
        }

        for (i, pt) in pageTexts.enumerated() {
            XCTAssertFalse(pt.isEmpty, "Page \(i) should not be empty")
        }

        XCTAssertTrue(allTextNormalized.contains(tailSentinel),
                      "PDF text must contain tail sentinel — tail was truncated")

        XCTAssertTrue(allTextNormalized.contains(headSentinel),
                      "PDF text must contain head sentinel — head was truncated")

        if let headRange = allTextNormalized.range(of: headSentinel),
           let tailRange = allTextNormalized.range(of: tailSentinel) {
            XCTAssertLessThan(headRange.lowerBound, tailRange.lowerBound,
                              "Head sentinel must appear before tail sentinel in PDF text")
        }

        ClinicalReportEngine.cleanupTempFile(url)
    }

    // MARK: - 21. Clinical report display values stay localized and compact

    func testClinicalReportDisplayValuesAreLocalized() {
        XCTAssertEqual(ClinicalReportEngine.formatTemperature(36.5), "36.5")
        XCTAssertEqual(ClinicalReportEngine.formatTemperature(36.42), "36.42")
        XCTAssertEqual(ClinicalReportEngine.healthFieldLabel(for: "sleep"), String(localized: "睡眠"))
        XCTAssertEqual(ClinicalReportEngine.healthFieldLabel(for: "weight"), String(localized: "体重"))
        XCTAssertEqual(ClinicalReportEngine.healthFieldLabel(for: "basalBodyTemperature"),
                       String(localized: "基础体温"))
    }

    func testClinicalReportPDFUsesCompactTemperatureAndReadableHealthFields() {
        let firstDate = date(2026, 3, 15)
        var logs: [DailyLog] = []
        for offset in 0...120 {
            let day = cal.date(byAdding: .day, value: offset, to: firstDate)!
            let log = DailyLog(date: day, mood: .good,
                               basalBodyTemperatureCelsius: 36.4)
            log.healthImportedFields = ["sleep", "weight", "basalBodyTemperature"]
            logs.append(log)
        }
        let data = ClinicalReportEngine.ReportData(
            periodDays: [], logs: logs, medications: [], intakes: [],
            prediction: .empty, includeNotes: false, range: .sixMonths)
        guard let url = ClinicalReportEngine.generatePDF(from: data) else {
            XCTFail("Clinical report PDF generation failed")
            return
        }
        defer { ClinicalReportEngine.cleanupTempFile(url) }

        guard let document = PDFDocument(url: url) else {
            XCTFail("Generated PDF could not be read")
            return
        }
        XCTAssertGreaterThan(document.pageCount, 3)
        let pageTexts = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
        let text = pageTexts.joined(separator: "\n")
        XCTAssertTrue(text.contains("36.4"))
        XCTAssertFalse(text.contains("36.400000"))
        XCTAssertFalse(text.contains("basalBodyTemperature"))
        XCTAssertFalse(text.contains("sleep|weight"))

        let continuationPrefixes = [
            "Basal body temperature", "Apple Health fields:",
            "基础体温", "Apple 健康字段:"
        ]
        for (index, pageText) in pageTexts.enumerated() {
            let firstLine = pageText
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
            XCTAssertFalse(
                continuationPrefixes.contains(where: { firstLine.hasPrefix($0) }),
                "Body detail block continuation started page \(index + 1): \(firstLine)"
            )
        }
    }
}

// MARK: - CyclePredictor 测试

final class CyclePredictorTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - 最少 4 个完成周期(最近完成 + 3 历史)

    func testMinimumFourCompletedCyclesForComparison() {
        // 5 个周期起点,间隔 28 天
        let periods: [PeriodDay] = (0..<5).map { i in
            PeriodDay(date: date(2026, 1, 1 + i * 28), flow: .medium)
        }
        let p = CyclePredictor.predict(from: periods, manual: nil)
        // 5 个起点 → 4 个间隔 → 至少 4 个完成周期
        let completed = p.cycles.filter { $0.length != nil }
        XCTAssertGreaterThanOrEqual(completed.count, 4)
    }

    // MARK: - 手动周期优先

    func testManualCycleOverridesStats() {
        let periods = [PeriodDay(date: date(2026, 1, 1), flow: .medium)]
        let manual = ManualCycle(enabled: true, cycleLength: 35, periodLength: 6)
        let p = CyclePredictor.predict(from: periods, manual: manual)
        XCTAssertTrue(p.isManual)
        XCTAssertEqual(p.averageCycleLength, 35.0)
        XCTAssertEqual(p.averagePeriodLength, 6.0)
    }

    // MARK: - 空数据返回 empty

    func testEmptyDataReturnsEmpty() {
        let p = CyclePredictor.predict(from: [], manual: nil)
        XCTAssertFalse(p.hasEnoughData)
    }

    // MARK: - 周期长度限 15-120

    func testCycleLengthBounds15To120() {
        // 间隔 10 天(太短)
        let periods1 = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
            PeriodDay(date: date(2026, 1, 11), flow: .medium),
        ]
        let p1 = CyclePredictor.predict(from: periods1, manual: nil)
        XCTAssertTrue(p1.cycleLengths.isEmpty)

        // 间隔 130 天(太长)
        let periods2 = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
            PeriodDay(date: date(2026, 5, 10), flow: .medium),
        ]
        let p2 = CyclePredictor.predict(from: periods2, manual: nil)
        XCTAssertTrue(p2.cycleLengths.isEmpty)
    }
}

// MARK: - CycleComparisonEngine 测试

final class CycleComparisonEngineTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - 需要至少 4 个完成周期

    func testRequiresFourCompletedCycles() {
        let cycles: [CyclePredictor.CycleRecord] = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 28),
            .init(start: date(2026, 1, 29), periodDays: 4, length: 28),
            .init(start: date(2026, 2, 26), periodDays: 5, length: 28),
            // 只有 3 个完成,第 4 个进行中
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = cycles
        let result = CycleComparisonEngine.compare(prediction: pred, logs: [])
        XCTAssertFalse(result.hasEnoughData)
    }

    // MARK: - 最近完成周期命名

    func testLatestCompletedCycleNaming() {
        let cycles: [CyclePredictor.CycleRecord] = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 28),
            .init(start: date(2026, 1, 29), periodDays: 4, length: 28),
            .init(start: date(2026, 2, 26), periodDays: 5, length: 28),
            .init(start: date(2026, 3, 26), periodDays: 5, length: 28),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = cycles
        let result = CycleComparisonEngine.compare(prediction: pred, logs: [])
        XCTAssertTrue(result.hasEnoughData)
        XCTAssertEqual(result.latestCompletedStart, date(2026, 3, 26))
    }

    // MARK: - 追踪项频率除以历史周期数

    func testTrackerFrequencyDividedByHistoricalCycles() {
        let logs: [DailyLog] = [
            // One historical occurrence must be normalized by the three
            // historical cycles, including the two cycles with no log.
            DailyLog(date: date(2026, 1, 2), mood: .okay, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 3, 28), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 3, 29), mood: .good, symptoms: ["cramps"]),
        ]
        let cycles: [CyclePredictor.CycleRecord] = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 28),
            .init(start: date(2026, 1, 29), periodDays: 4, length: 28),
            .init(start: date(2026, 2, 26), periodDays: 5, length: 28),
            .init(start: date(2026, 3, 26), periodDays: 5, length: 28),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = cycles
        let result = CycleComparisonEngine.compare(prediction: pred, logs: logs)
        // 应该有 tracker 指标,且 baseline 是每周期平均
        let trackerMetrics = result.metrics.filter { $0.id.hasPrefix("tracker-") }
        XCTAssertEqual(trackerMetrics.count, 1)
        guard let cramps = trackerMetrics.first else { return }
        // Three historical cycles exist. One historical occurrence therefore
        // yields 0.3 entries/cycle (and not 1.0 entries/log or 1.0/cycle).
        XCTAssertTrue(cramps.baseline.contains("0.3"), cramps.baseline)
    }

    // MARK: - 15...120 day cycle length guard

    func testExcludesCyclesShorterThanFifteenDays() {
        // After excluding the 10-day cycle, only 3 valid cycles remain (< 4 needed)
        let cycles: [CyclePredictor.CycleRecord] = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 10),  // too short
            .init(start: date(2026, 1, 11), periodDays: 4, length: 28),
            .init(start: date(2026, 2, 8), periodDays: 5, length: 28),
            .init(start: date(2026, 3, 8), periodDays: 5, length: 28),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = cycles
        let result = CycleComparisonEngine.compare(prediction: pred, logs: [])
        // Only 3 completed cycles within 15...120 → not enough (need 4)
        XCTAssertFalse(result.hasEnoughData)
    }

    func testExcludesCyclesLongerThan120Days() {
        // After excluding 150-day cycle, only 3 valid remain (< 4 needed)
        let cycles: [CyclePredictor.CycleRecord] = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 150), // too long
            .init(start: date(2026, 6, 1), periodDays: 4, length: 28),
            .init(start: date(2026, 6, 29), periodDays: 5, length: 28),
            .init(start: date(2026, 7, 27), periodDays: 5, length: 28),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = cycles
        let result = CycleComparisonEngine.compare(prediction: pred, logs: [])
        // 150-day cycle excluded → only 3 valid → not enough
        XCTAssertFalse(result.hasEnoughData)
    }

    func testIncludesBoundaryFifteenAnd120Days() {
        let cycles: [CyclePredictor.CycleRecord] = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 15),  // exactly 15
            .init(start: date(2026, 1, 16), periodDays: 4, length: 28),
            .init(start: date(2026, 2, 13), periodDays: 5, length: 28),
            .init(start: date(2026, 3, 13), periodDays: 5, length: 120), // exactly 120
            .init(start: date(2026, 7, 11), periodDays: 5, length: 28),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = cycles
        let result = CycleComparisonEngine.compare(prediction: pred, logs: [])
        XCTAssertTrue(result.hasEnoughData)
    }
}

// MARK: - CorrelationEngine 测试

final class CorrelationEngineTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - 空数据全部 insufficient

    func testEmptyDataAllInsufficient() {
        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: [], prediction: .empty,
            medications: [], intakes: [])
        let results = CorrelationEngine.analyze(input: input)
        XCTAssertTrue(results.allSatisfy { !$0.sufficientData })
    }

    // MARK: - 药物打卡需要至少 3 天两组

    func testMedicationCheckInRequiresMinimumDays() {
        // 只有 2 天打卡日记录
        let med = Medication(name: "Test", emoji: "💊")
        let intakes = (0..<2).map { i -> MedicationIntake in
            let dk = DayKey.from(Calendar(identifier: .gregorian).date(byAdding: .day, value: -i, to: Date())!)
            return MedicationIntake(medicationId: med.id, dayKey: dk)
        }
        let logs = (0..<10).map { i -> DailyLog in
            let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: -i, to: Date())!
            return DailyLog(date: d, mood: .good)
        }
        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: logs, prediction: .empty,
            medications: [med], intakes: intakes)
        let results = CorrelationEngine.analyze(input: input)
        // 应该 insufficient(打卡日 < 3)
        if let medCor = results.first(where: { $0.id == "med-tracker" }) {
            XCTAssertFalse(medCor.sufficientData)
        }
    }

    // MARK: - 稳定 observation ID

    func testStableObservationIDs() {
        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: [], prediction: .empty,
            medications: [], intakes: [])
        let r1 = CorrelationEngine.analyze(input: input)
        let r2 = CorrelationEngine.analyze(input: input)
        // 相同输入应产出相同 ID
        for (a, b) in zip(r1, r2) {
            XCTAssertEqual(a.id, b.id)
        }
    }

    // MARK: - 药物打卡:每药独立,pre-createdAt 日志不参与

    func testMedicationCorrelationPerMedSeparation() {
        let cal = Cal.current
        let today = Cal.startOfDay(Date())
        let med1 = Medication(name: "Med1", emoji: "💊")
        med1.createdAt = cal.date(byAdding: .day, value: -30, to: today)!
        let med2 = Medication(name: "Med2", emoji: "☀️")
        med2.createdAt = cal.date(byAdding: .day, value: -5, to: today)!

        // Med2 5 天前创建,只给它 3 天打卡 + 3 天无打卡日志
        var intakes: [MedicationIntake] = []
        var logs: [DailyLog] = []
        for i in 0..<10 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dk = DayKey.from(d)
            if i < 3 {
                intakes.append(MedicationIntake(medicationId: med2.id, dayKey: dk))
            }
            if i < 10 {
                logs.append(DailyLog(date: d, mood: .good))
            }
        }

        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: logs, prediction: .empty,
            medications: [med1, med2], intakes: intakes)
        let results = CorrelationEngine.analyze(input: input)
        if let medCor = results.first(where: { $0.id == "med-tracker" }) {
            // Med1 没有打卡 → 不产生观测; Med2 有 3 天打卡 + 7 天无打卡
            // Med1 无 intakes, 30 天 eligible logs → 0 check-in, 30 non-check-in → 无打卡 < 3
            // Med2 有 3 天 intakes, 10 天 eligible logs → 3 check-in, 7 non-check-in
            // 只有 Med2 产生观测
            let med2Obs = medCor.observations.filter { $0.id.contains(med2.id.uuidString) }
            XCTAssertFalse(med2Obs.isEmpty, "Med2 should produce observations")
            let med1Obs = medCor.observations.filter { $0.id.contains(med1.id.uuidString) }
            XCTAssertTrue(med1Obs.isEmpty, "Med1 should not produce observations (no intakes)")
        }
    }

    // MARK: - 药物打卡:pre-createdAt 日志不参与

    func testMedicationCorrelationExcludesPreCreatedAtLogs() {
        let cal = Cal.current
        let today = Cal.startOfDay(Date())
        let med = Medication(name: "Test", emoji: "💊")
        // 药物 10 天前创建
        med.createdAt = cal.date(byAdding: .day, value: -10, to: today)!

        var intakes: [MedicationIntake] = []
        var logs: [DailyLog] = []
        // 3 天打卡(在创建后)
        for i in 0..<3 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            intakes.append(MedicationIntake(medicationId: med.id, dayKey: DayKey.from(d)))
            logs.append(DailyLog(date: d, mood: .good))
        }
        // 5 天无打卡(在创建后)
        for i in 3..<8 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            logs.append(DailyLog(date: d, mood: .good))
        }
        // 11+ 天前的日志(创建前 1 天以上)→ 不应参与
        for i in 11..<20 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            logs.append(DailyLog(date: d, mood: .okay))
        }

        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: logs, prediction: .empty,
            medications: [med], intakes: intakes)
        let results = CorrelationEngine.analyze(input: input)
        if let medCor = results.first(where: { $0.id == "med-tracker" }) {
            // 只有 3 check-in + 5 non-check-in(创建后的)→ 足够
            XCTAssertTrue(medCor.sufficientData)
            // sampleSize 应只包含创建后的唯一 eligible 日键(3+5=8 个唯一日)
            XCTAssertEqual(medCor.sampleSize, 8)
        }
    }

    // MARK: - sufficientData 为 false 时 observations 为空

    func testSufficientDataFalseWhenObservationsEmpty() {
        // 只有 1 个睡眠-心情配对 → 不足 5
        let logs: [DailyLog] = [
            DailyLog(date: Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: Date())!,
                     mood: .good, sleepHours: 7.0),
        ]
        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: logs, prediction: .empty,
            medications: [], intakes: [])
        let results = CorrelationEngine.analyze(input: input)
        for cor in results {
            if !cor.sufficientData {
                XCTAssertTrue(cor.observations.isEmpty,
                              "\(cor.id): sufficientData=false should have empty observations")
            }
        }
    }

    // MARK: - 单组数据(sleep bin 只有一个有 >= 2 天)不产生比较声明

    func testSingleBinOnlyDataNoComparisonClaim() {
        // 所有日志的 sleep 都在 6-7.5 范围,其他范围为空
        let logs: [DailyLog] = (0..<8).compactMap { i -> DailyLog? in
            guard let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: -i, to: Date()) else { return nil }
            return DailyLog(date: d, mood: .good, sleepHours: 6.5 + Double(i) * 0.1)
        }
        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: logs, prediction: .empty,
            medications: [], intakes: [])
        let results = CorrelationEngine.analyze(input: input)
        if let sleepMood = results.first(where: { $0.id == "sleep-mood" }) {
            // 只有一个 bin(mid)有数据 → 只有 1 个 observation → 不够两个组,不应声称比较
            XCTAssertEqual(sleepMood.observations.count, 1)
            XCTAssertFalse(sleepMood.sufficientData,
                           "single group should not claim sufficient data for comparison")
        }
    }

    // MARK: - 单组疼痛数据不产生比较声明

    func testSingleBinPainNoComparisonClaim() {
        // 所有日志的 pain 都 <= 2,high 组为空
        let logs: [DailyLog] = (0..<8).compactMap { i -> DailyLog? in
            guard let d = Calendar(identifier: .gregorian).date(byAdding: .day, value: -i, to: Date()) else { return nil }
            return DailyLog(date: d, mood: .good, pain: i % 3, sleepHours: 7.0)
        }
        let input = CorrelationEngine.AnalysisInput(
            periodDays: [], logs: logs, prediction: .empty,
            medications: [], intakes: [])
        let results = CorrelationEngine.analyze(input: input)
        if let sleepPain = results.first(where: { $0.id == "sleep-pain" }) {
            // pain 值 0,1,2 都 <= 2 → lowPain 组有数据,highPain 组为空 → 只有 1 个 observation
            XCTAssertLessThanOrEqual(sleepPain.observations.count, 1)
            XCTAssertFalse(sleepPain.sufficientData,
                           "single pain group should not claim sufficient data")
        }
    }

    // MARK: - 单组体重数据不产生比较声明

    func testSingleGroupCycleWeightNoComparisonClaim() {
        // 只有 1 个完成周期有体重数据 → 不够分组
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
            PeriodDay(date: date(2026, 1, 29), flow: .medium),
            PeriodDay(date: date(2026, 2, 26), flow: .medium),
            PeriodDay(date: date(2026, 3, 26), flow: .medium),
        ]
        let logs: [DailyLog] = [
            DailyLog(date: date(2026, 2, 5), mood: .good, weight: 60.0),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 28),
            .init(start: date(2026, 1, 29), periodDays: 4, length: 28),
            .init(start: date(2026, 2, 26), periodDays: 5, length: 28),
            .init(start: date(2026, 3, 26), periodDays: 5, length: 28),
        ]
        let input = CorrelationEngine.AnalysisInput(
            periodDays: periods, logs: logs, prediction: pred,
            medications: [], intakes: [])
        let results = CorrelationEngine.analyze(input: input)
        if let cycleWeight = results.first(where: { $0.id == "cycle-weight" }) {
            // 只有 1 个 cycle 有 weight → cycleWeights.count == 1 → insufficient
            XCTAssertFalse(cycleWeight.sufficientData,
                           "single cycle weight group should not claim sufficient data")
        }
    }

    // MARK: - 单阶段 tracker+mood 不产生比较声明

    func testSinglePhaseDataInsufficient() {
        let periods: [PeriodDay] = [
            PeriodDay(date: date(2026, 1, 1), flow: .medium),
            PeriodDay(date: date(2026, 1, 29), flow: .medium),
            PeriodDay(date: date(2026, 2, 26), flow: .medium),
            PeriodDay(date: date(2026, 3, 26), flow: .medium),
        ]
        // 所有日志都在经期阶段(periodDays=5,dayIndex 0-4 → menstrual)
        let logs: [DailyLog] = [
            DailyLog(date: date(2026, 1, 1), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 1, 2), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 1, 3), mood: .okay),
            DailyLog(date: date(2026, 1, 4), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 1, 29), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 1, 30), mood: .okay),
            DailyLog(date: date(2026, 1, 31), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 2, 1), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 2, 26), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 2, 27), mood: .okay),
            DailyLog(date: date(2026, 2, 28), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 3, 1), mood: .good),
            DailyLog(date: date(2026, 3, 26), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 3, 27), mood: .good, symptoms: ["cramps"]),
            DailyLog(date: date(2026, 3, 28), mood: .okay),
            DailyLog(date: date(2026, 3, 29), mood: .good, symptoms: ["cramps"]),
        ]
        var pred = CyclePredictor.Prediction.empty
        pred.hasEnoughData = true
        pred.cycles = [
            .init(start: date(2026, 1, 1), periodDays: 5, length: 28),
            .init(start: date(2026, 1, 29), periodDays: 5, length: 28),
            .init(start: date(2026, 2, 26), periodDays: 5, length: 28),
            .init(start: date(2026, 3, 26), periodDays: 5, length: 28),
        ]
        let input = CorrelationEngine.AnalysisInput(
            periodDays: periods, logs: logs, prediction: pred,
            medications: [], intakes: [])
        let results = CorrelationEngine.analyze(input: input)
        if let phaseCor = results.first(where: { $0.id == "phase-tracker" }) {
            XCTAssertFalse(phaseCor.sufficientData,
                           "data from only one phase should be insufficient for comparison")
        }
    }
}

// MARK: - SampleData 自检

final class SampleDataTests: XCTestCase {

    func testSampleDataSelfCheck() {
        XCTAssertTrue(SampleData.selfCheck())
    }

    @MainActor
    func testSampleDataNeverInsertsIntoSwiftData() {
        // 验证 virtualPeriodDays 创建的 PeriodDay 对象(@Model class)是临时对象,不会被插入 SwiftData。
        // PeriodDay 是 @Model class(不是 struct),但 SampleData 只创建临时实例,绝不写入 ModelContainer。
        let virtual = SampleData.virtualPeriodDays
        XCTAssertFalse(virtual.isEmpty)
        // 所有 dayKey 唯一
        let keys = virtual.map(\.dayKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        // 创建一个内存 ModelContainer,确认样本数据未被插入
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: PeriodDay.self, configurations: config) else {
            XCTFail("Failed to create in-memory ModelContainer")
            return
        }
        let count = (try? container.mainContext.fetchCount(FetchDescriptor<PeriodDay>())) ?? -1
        XCTAssertEqual(count, 0, "virtualPeriodDays should never be inserted into SwiftData")
    }
}
