import Foundation
import UIKit

/// 专业级临床就诊报告 PDF 生成器。扩展 DataExport 的风格,生成增强版 PDF。
/// 不接触 SwiftData 直接操作,只接收已查询好的数据数组。
enum ClinicalReportEngine {

    enum DateRange: String, CaseIterable, Identifiable {
        case threeMonths = "3M"
        case sixMonths = "6M"
        case twelveMonths = "12M"
        case all = "all"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .threeMonths:  return String(localized: "近 3 个月")
            case .sixMonths:    return String(localized: "近 6 个月")
            case .twelveMonths: return String(localized: "近 12 个月")
            case .all:          return String(localized: "全部")
            }
        }

        func startDate(from today: Date) -> Date? {
            let cal = Cal.current
            switch self {
            case .threeMonths:  return cal.date(byAdding: .month, value: -3, to: today)
            case .sixMonths:    return cal.date(byAdding: .month, value: -6, to: today)
            case .twelveMonths: return cal.date(byAdding: .month, value: -12, to: today)
            case .all:          return nil
            }
        }
    }

    struct ReportData {
        let periodDays: [PeriodDay]
        let logs: [DailyLog]
        let medications: [Medication]
        let intakes: [MedicationIntake]
        let prediction: CyclePredictor.Prediction
        let includeNotes: Bool
        let range: DateRange
    }

    // MARK: - PDF 生成

    static func generatePDF(from data: ReportData) -> URL? {
        let pageWidth: CGFloat = 595   // A4 @72dpi
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40

        let today = Cal.startOfDay(Date())
        let rangeStart = data.range.startDate(from: today)
        let rangeEnd: Date? = today

        // 按日期范围过滤(排除未来日期,使用一致的显式边界)
        let filteredPeriods = data.periodDays.filter { d in
            let day = Cal.startOfDay(d.date)
            if let end = rangeEnd, day > end { return false }
            if let start = rangeStart, day < start { return false }
            return true
        }
        let filteredLogs = data.logs.filter { l in
            let day = Cal.startOfDay(l.date)
            if let end = rangeEnd, day > end { return false }
            if let start = rangeStart, day < start { return false }
            return true
        }
        let filteredIntakes = data.intakes.filter { i in
            let day = Cal.startOfDay(DayKey.date(from: i.dayKey))
            if let end = rangeEnd, day > end { return false }
            if let start = rangeStart, day < start { return false }
            return true
        }

        // 计算统计
        let stats = computeStats(periods: filteredPeriods, logs: filteredLogs,
                                 intakes: filteredIntakes, medications: data.medications,
                                 rangeStart: rangeStart, rangeEnd: rangeEnd)

        // 从过滤后的周期重新计算 regularity,保持与范围一致
        let filteredRegularity = computeRegularity(from: filteredPeriods)

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 20)
        ]
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13)
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        let disclaimerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: UIColor.gray
        ]

        let filename = UUID().uuidString + "-" + String(localized: "Maren-临床就诊报告.pdf")
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let data_out = renderer.pdfData(actions: { ctx in
            var y: CGFloat = margin
            ctx.beginPage()

            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > pageHeight - margin {
                    ctx.beginPage()
                    y = margin
                }
            }

            /// 安全换行分页:用 TextKit (NSLayoutManager + NSTextContainer)
            /// 精确测量页面可用高度能容纳多少字符,再用 NSString.draw 在 PDF 中绘制。
            /// 保证:字符覆盖完整(不遗漏)、前向推进(每次至少前进 1 字符)、无裁剪。
            func drawWrapped(_ text: String, _ attrs: [NSAttributedString.Key: Any],
                             lineHeight: CGFloat) {
                let maxWidth = pageWidth - margin * 2
                let paragraphs = text.components(separatedBy: "\n")

                for para in paragraphs {
                    let trimmed = para.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        y += lineHeight * 0.5
                        continue
                    }

                    let nsText = trimmed as NSString
                    let totalLen = nsText.length
                    guard totalLen > 0 else { continue }

                    var drawn = 0
                    while drawn < totalLen {
                        var availHeight = pageHeight - margin - y
                        if availHeight <= lineHeight * 2 {
                            ctx.beginPage()
                            y = margin
                            availHeight = pageHeight - margin * 2
                        }
                        let safeHeight = availHeight - lineHeight

                        let remainingLength = totalLen - drawn
                        let remainingText = nsText.substring(with: NSRange(location: drawn, length: remainingLength))

                        let ts = NSTextStorage(string: remainingText, attributes: attrs)
                        let lm = NSLayoutManager()
                        ts.addLayoutManager(lm)
                        let tc = NSTextContainer(size: CGSize(width: maxWidth, height: safeHeight))
                        tc.lineFragmentPadding = 0
                        lm.addTextContainer(tc)

                        let visibleGlyphRange = lm.glyphRange(for: tc)
                        let localCharRange = lm.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

                        var fitLen = min(max(1, localCharRange.length), remainingLength)
                        // Ensure fitLen ends on a composed-character boundary without exceeding remainingLength
                        while fitLen > 1 {
                            let endIdx = drawn + fitLen - 1
                            let seqRange = nsText.rangeOfComposedCharacterSequence(at: endIdx)
                            if seqRange.location + seqRange.length == drawn + fitLen {
                                break
                            }
                            fitLen -= 1
                        }

                        let chunk = nsText.substring(with: NSRange(location: drawn, length: fitLen))
                        let nsChunk = chunk as NSString

                        let chunkRect = nsChunk.boundingRect(
                            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: attrs, context: nil)
                        let chunkHeight = max(lineHeight,
                            ceil(chunkRect.height / lineHeight) * lineHeight)
                        newPageIfNeeded(chunkHeight)
                        nsChunk.draw(
                            with: CGRect(x: margin, y: y, width: maxWidth,
                                         height: chunkHeight),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: attrs, context: nil)
                        y += chunkHeight
                        drawn += fitLen
                    }
                }
            }

            func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], lineHeight: CGFloat) {
                drawWrapped(text, attrs, lineHeight: lineHeight)
            }

            /// Keep a dated body-detail row together when it is close to a page break.
            /// The rows are intentionally small, but pre-measuring them prevents a
            /// continuation such as "Apple Health fields:" from starting a page alone.
            func drawBlock(_ lines: [String], _ attrs: [NSAttributedString.Key: Any],
                          lineHeight: CGFloat) {
                let maxWidth = pageWidth - margin * 2
                let rowHeights = lines.map { line -> CGFloat in
                    let rect = (line as NSString).boundingRect(
                        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attrs, context: nil)
                    return max(lineHeight, ceil(rect.height / lineHeight) * lineHeight)
                }
                let blockHeight = rowHeights.reduce(0, +)
                newPageIfNeeded(blockHeight)
                for (line, rowHeight) in zip(lines, rowHeights) {
                    // Draw directly after the one block-level page check. Calling
                    // drawWrapped here would perform another near-bottom page check
                    // and could split the block after its date line.
                    (line as NSString).draw(
                        with: CGRect(x: margin, y: y, width: maxWidth, height: rowHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attrs, context: nil)
                    y += rowHeight
                }
            }

            func drawSeparator() {
                y += 4
                UIColor.lightGray.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                path.stroke()
                y += 8
            }

            // 标题
            draw(String(localized: "Maren 临床就诊报告"), titleAttrs, lineHeight: 28)
            let rangeLabel = data.range.label
            let dateRangeText = String(localized: "报告范围:\(rangeLabel)")
            draw(dateRangeText, bodyAttrs, lineHeight: 16)
            draw(String(localized: "生成时间:\(Cal.fullDateFormatter.string(from: Date()))"), bodyAttrs, lineHeight: 16)
            y += 4

            // 非诊断声明
            draw(String(localized: "⚠ 本报告基于用户自行记录的数据,由设备端统计引擎生成,仅供就诊沟通参考,不构成医学诊断或治疗建议。请以医生的专业判断为准。"),
                 disclaimerAttrs, lineHeight: 18)
            y += 4
            drawSeparator()

            // 1. 周期概览
            draw(String(localized: "一、周期概览"), headAttrs, lineHeight: 20)
            draw(String(localized: "观测周期数:\(stats.observedCycles) 个"), bodyAttrs, lineHeight: 15)
            if let avg = stats.avgCycleLength {
                draw(String(localized: "平均周期长度:\(String(format: "%.1f", avg)) 天(范围 \(stats.minCycleLength ?? 0)–\(stats.maxCycleLength ?? 0) 天)"), bodyAttrs, lineHeight: 15)
            }
            if let std = stats.cycleStdDev {
                draw(String(localized: "周期标准差:\(String(format: "%.1f", std)) 天 — \(stats.variabilityLabel)"), bodyAttrs, lineHeight: 15)
            }
            if let avg = stats.avgPeriodLength {
                draw(String(localized: "平均经期长度:\(String(format: "%.1f", avg)) 天(范围 \(stats.minPeriodLength ?? 0)–\(stats.maxPeriodLength ?? 0) 天)"), bodyAttrs, lineHeight: 15)
            }
            draw(String(localized: "规律度评估:\(filteredRegularity)"), bodyAttrs, lineHeight: 15)
            y += 4

            // 2. 经期详情
            draw(String(localized: "二、经期记录"), headAttrs, lineHeight: 20)
            if filteredPeriods.isEmpty {
                draw("—", bodyAttrs, lineHeight: 15)
            } else {
                for d in filteredPeriods.sorted(by: { $0.date < $1.date }) {
                    let origin = d.importedFromHealth
                        ? "    \(String(localized: "来源:Apple 健康"))"
                        : ""
                    draw("\(isoDay.string(from: d.date))    \(d.flow.label)\(origin)",
                         bodyAttrs, lineHeight: 14)
                }
            }
            y += 4

            // 3. 经期流量分布
            draw(String(localized: "三、流量分布"), headAttrs, lineHeight: 20)
            let flowDist = stats.flowDistribution
            for level in FlowLevel.allCases {
                let count = flowDist[level.rawValue] ?? 0
                if count > 0 {
                    draw(String(localized: "  \(level.label): \(count) 天"),
                         bodyAttrs, lineHeight: 15)
                }
            }
            y += 4

            // 4. 每日记录摘要
            draw(String(localized: "四、每日记录摘要"), headAttrs, lineHeight: 20)
            if filteredLogs.isEmpty {
                draw("—", bodyAttrs, lineHeight: 15)
            } else {
                if let avgMood = stats.avgMood {
                    draw(String(localized: "平均心情评分:\(String(format: "%.1f", avgMood)) / 5"), bodyAttrs, lineHeight: 15)
                }
                if let avgSleep = stats.avgSleep {
                    draw(String(localized: "平均睡眠:\(String(format: "%.1f", avgSleep)) 小时"), bodyAttrs, lineHeight: 15)
                }
                if let avgWeight = stats.avgWeight {
                    draw(String(localized: "平均体重:\(String(format: "%.1f", avgWeight)) kg"), bodyAttrs, lineHeight: 15)
                }
                if let avgBasalBodyTemperature = stats.avgBasalBodyTemperatureCelsius {
                    draw(String(localized: "平均基础体温:\(Self.formatTemperature(avgBasalBodyTemperature)) °C"),
                         bodyAttrs, lineHeight: 15)
                }
                if stats.spottingRecordedDays > 0 {
                    draw(String(localized: "点滴出血:有记录 \(stats.spottingDays) 天,已记录 \(stats.spottingRecordedDays) 天"),
                         bodyAttrs, lineHeight: 15)
                }
                // 追踪项频次
                if !stats.topTrackers.isEmpty {
                    draw(String(localized: "高频追踪项:"), bodyAttrs, lineHeight: 15)
                    for (key, count) in stats.topTrackers {
                        draw(String(localized: "  \(Symptoms.label(for: key)): \(count) 次"),
                             bodyAttrs, lineHeight: 14)
                    }
                }
                let bodySignalLogs = filteredLogs
                    .filter {
                        $0.basalBodyTemperatureCelsius != nil
                            || $0.spotting != nil
                            || !$0.healthImportedFields.isEmpty
                    }
                    .sorted(by: { $0.date < $1.date })
                if !bodySignalLogs.isEmpty {
                    draw(String(localized: "身体指标明细"), bodyAttrs, lineHeight: 15)
                    for log in bodySignalLogs {
                        var parts = [isoDay.string(from: log.date)]
                        if let temperature = log.basalBodyTemperatureCelsius {
                            parts.append(String(localized: "基础体温 \(Self.formatTemperature(temperature)) °C"))
                        }
                        if let spotting = log.spotting {
                            parts.append(spotting
                                         ? String(localized: "点滴出血:有")
                                         : String(localized: "点滴出血:无"))
                        }
                        if !log.healthImportedFields.isEmpty {
                            let fieldLabels = log.healthImportedFields
                                .sorted()
                                .map { Self.healthFieldLabel(for: $0) }
                            let separator = Locale.current.language.languageCode?.identifier == "zh"
                                ? "、" : ", "
                            let fields = fieldLabels.joined(separator: separator)
                            parts.append(String(localized: "来源:Maren + Apple 健康"))
                            parts.append(String(localized: "Apple 健康字段:\(fields)"))
                        }
                        drawBlock(parts, bodyAttrs, lineHeight: 14)
                    }
                }
            }
            y += 4

            // 5. 用药打卡记录(中性术语,不使用依从性/合规)
            draw(String(localized: "五、用药打卡记录"), headAttrs, lineHeight: 20)
            if data.medications.isEmpty {
                draw("—", bodyAttrs, lineHeight: 15)
            } else {
                for med in data.medications {
                    let medIntakes = filteredIntakes.filter { $0.medicationId == med.id }
                    let takenDays = Set(medIntakes.map { $0.dayKey }).count
                    // 分母 = max(报告范围起始, 药物创建日期) 到报告结束的可用日历天数
                    let medCreated = Cal.startOfDay(med.createdAt)
                    let eligibleStart = rangeStart ?? medCreated
                    let effectiveStart = max(eligibleStart, medCreated)
                    let eligibleDays = max(1, Cal.daysBetween(effectiveStart, today) + 1)
                    let displayName = "\(med.name) \(med.emoji)"
                    draw(String(localized: "\(displayName): \(takenDays) / \(eligibleDays) 天打卡记录"),
                         bodyAttrs, lineHeight: 15)
                }
                draw(String(localized: "打卡分母为报告范围内该药可用的日历天数(从该药创建日起),非临床依从率。"),
                     disclaimerAttrs, lineHeight: 13)
            }
            y += 4

            // 6. 备注(可选)
            if data.includeNotes {
                draw(String(localized: "六、用户备注"), headAttrs, lineHeight: 20)
                let notesWithContent = filteredLogs.filter { !$0.note.isEmpty }
                if notesWithContent.isEmpty {
                    draw("—", bodyAttrs, lineHeight: 15)
                } else {
                    for log in notesWithContent.sorted(by: { $0.date < $1.date }) {
                        draw("\(isoDay.string(from: log.date)): \(log.note)", bodyAttrs, lineHeight: 14)
                    }
                }
                y += 4
            }

            // 7. 方法论说明
            drawSeparator()
            draw(String(localized: "七、方法论说明"), headAttrs, lineHeight: 20)
            draw(String(localized: "本报告所有统计均基于用户在 Maren 中自行记录或从 Apple 健康导入的数据,在设备端本地计算。周期长度通过相邻经期首日间隔估算(仅计 15–120 天范围内的有效周期);经期长度通过连续经期记录(允许中间 ≤2 天间隔)聚类得出;心情、睡眠、体重和基础体温等指标取所有有记录日期的算术平均值;点滴出血统计明确记录为有的日期。追踪项频次统计所有 DailyLog 中出现的症状/自定义追踪项。用药打卡记录 = 该药有打卡记录的天数 / 报告范围内可用的日历天数(从该药创建日起)。"),
                 bodyAttrs, lineHeight: 14)
            y += 4

            // 底部声明
            draw(String(localized: "⚠ 免责声明:本报告仅供参考,不构成医学诊断、治疗建议或生育指导。数据准确性取决于用户记录的完整性和及时性。如有健康疑问,请咨询专业医疗人员。"),
                 disclaimerAttrs, lineHeight: 14)
        })

        do {
            try data_out.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - 统计计算

    struct Stats {
        var observedCycles: Int = 0
        var avgCycleLength: Double?
        var minCycleLength: Int?
        var maxCycleLength: Int?
        var cycleStdDev: Double?
        var variabilityLabel: String = ""
        var avgPeriodLength: Double?
        var minPeriodLength: Int?
        var maxPeriodLength: Int?
        var avgMood: Double?
        var avgSleep: Double?
        var avgWeight: Double?
        var avgBasalBodyTemperatureCelsius: Double?
        var spottingDays: Int = 0
        var spottingRecordedDays: Int = 0
        var topTrackers: [(String, Int)] = []
        var flowDistribution: [Int: Int] = [:]
        var totalDaysInRange: Int = 1
    }

    /// 与 CyclePredictor 一致的常量
    private static let maxGapWithinPeriod = 2
    private static let minCycle = 15
    private static let maxCycle = 120

    static func computeStats(periods: [PeriodDay], logs: [DailyLog],
                              intakes: [MedicationIntake], medications: [Medication],
                              rangeStart: Date? = nil, rangeEnd: Date? = nil,
                              effectiveEnd: Date = Date()) -> Stats {
        var s = Stats()

        // 过滤输入数据到指定范围(排除未来日期,使用一致的显式边界)
        // effectiveEnd 作为隐式上界:当 rangeEnd 未指定时排除 effectiveEnd 之后的记录
        let upperBound = rangeEnd ?? effectiveEnd
        let filteredPeriods = periods.filter { d in
            let day = Cal.startOfDay(d.date)
            if day > upperBound { return false }
            if let start = rangeStart, day < start { return false }
            return true
        }
        let filteredLogs = logs.filter { l in
            let day = Cal.startOfDay(l.date)
            if day > upperBound { return false }
            if let start = rangeStart, day < start { return false }
            return true
        }
        let filteredIntakes = intakes.filter { i in
            let day = Cal.startOfDay(DayKey.date(from: i.dayKey))
            if day > upperBound { return false }
            if let start = rangeStart, day < start { return false }
            return true
        }

        // 使用显式范围计算观测窗口天数;all-time 时用最早相关记录
        if let start = rangeStart, let end = rangeEnd {
            s.totalDaysInRange = max(1, Cal.daysBetween(start, end) + 1)
        } else {
            // all-time:找到最早的相关记录(跨 periods/logs/intakes)
            var earliest: Date?
            for p in filteredPeriods {
                let d = Cal.startOfDay(p.date)
                if earliest == nil || d < earliest! { earliest = d }
            }
            for l in filteredLogs {
                let d = Cal.startOfDay(l.date)
                if earliest == nil || d < earliest! { earliest = d }
            }
            for i in filteredIntakes {
                let d = Cal.startOfDay(DayKey.date(from: i.dayKey))
                if earliest == nil || d < earliest! { earliest = d }
            }
            let today = Cal.startOfDay(effectiveEnd)
            if let first = earliest {
                s.totalDaysInRange = max(1, Cal.daysBetween(first, today) + 1)
            }
        }

        // 流量分布
        for p in filteredPeriods {
            s.flowDistribution[p.flow.rawValue, default: 0] += 1
        }

        // 每日记录统计(独立于经期数据)
        if !filteredLogs.isEmpty {
            let moods = filteredLogs.compactMap { $0.mood }
            if !moods.isEmpty {
                s.avgMood = Double(moods.reduce(0) { $0 + $1.rawValue }) / Double(moods.count)
            }
            let sleeps = filteredLogs.compactMap { $0.sleepHours }
            if !sleeps.isEmpty {
                s.avgSleep = sleeps.reduce(0, +) / Double(sleeps.count)
            }
            let weights = filteredLogs.compactMap { $0.weight }
            if !weights.isEmpty {
                s.avgWeight = weights.reduce(0, +) / Double(weights.count)
            }
            let basalBodyTemperatures: [Double] = filteredLogs.compactMap { log in
                guard let value = log.basalBodyTemperatureCelsius,
                      HealthKitPlanners.isValidBasalBodyTemperature(value) else { return nil }
                return value
            }
            if !basalBodyTemperatures.isEmpty {
                s.avgBasalBodyTemperatureCelsius = basalBodyTemperatures.reduce(0, +)
                    / Double(basalBodyTemperatures.count)
            }
            s.spottingRecordedDays = filteredLogs.reduce(into: 0) { count, log in
                if log.spotting != nil { count += 1 }
            }
            s.spottingDays = filteredLogs.reduce(into: 0) { count, log in
                if log.spotting == true { count += 1 }
            }
        }

        // 追踪项频次(独立于经期数据)
        var trackerCounts: [String: Int] = [:]
        for log in filteredLogs { for sym in log.symptoms { trackerCounts[sym, default: 0] += 1 } }
        s.topTrackers = trackerCounts.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }

        // 以下周期统计需要经期数据
        guard !filteredPeriods.isEmpty else { return s }

        // 去重 + 排序参与计算的经期日
        let sortedPeriods = Array(Set(filteredPeriods.map { Cal.startOfDay($0.date) }))
            .sorted()
            .map { d in filteredPeriods.first { Cal.startOfDay($0.date) == d }! }

        // 经期段聚类:使用前一个日期的间隔,不使用 spanStart
        var spans: [(start: Date, length: Int)] = []
        var spanStart = Cal.startOfDay(sortedPeriods.first!.date)
        var spanLen = 1

        for i in 1..<sortedPeriods.count {
            let prevDate = Cal.startOfDay(sortedPeriods[i - 1].date)
            let curDate = Cal.startOfDay(sortedPeriods[i].date)
            let gap = Cal.current.dateComponents([.day], from: prevDate, to: curDate).day ?? 0
            if gap <= Self.maxGapWithinPeriod {
                spanLen += 1
            } else {
                spans.append((spanStart, spanLen))
                spanStart = curDate
                spanLen = 1
            }
        }
        spans.append((spanStart, spanLen))

        // 真正的周期起点(间隔 >= 15 天,与 CyclePredictor 一致)
        var cycleStarts: [Date] = []
        var cycleStartPeriodLengths: [Int] = []
        for span in spans {
            if let last = cycleStarts.last {
                let gap = Cal.current.dateComponents([.day], from: last, to: span.start).day ?? 0
                if gap < Self.minCycle { continue }
            }
            cycleStarts.append(span.start)
            cycleStartPeriodLengths.append(span.length)
        }

        // 周期长度:只计 15-120 天范围内的有效长度
        var cycleLengths: [Int] = []
        if cycleStarts.count >= 2 {
            for i in 1..<cycleStarts.count {
                let len = Cal.current.dateComponents([.day], from: cycleStarts[i - 1], to: cycleStarts[i]).day ?? 0
                if len >= Self.minCycle && len <= Self.maxCycle {
                    cycleLengths.append(len)
                }
            }
        }

        // observedCycles = 有效周期长度的数量,不是原始起点数
        s.observedCycles = cycleLengths.count

        if !cycleLengths.isEmpty {
            s.avgCycleLength = Double(cycleLengths.reduce(0, +)) / Double(cycleLengths.count)
            s.minCycleLength = cycleLengths.min()
            s.maxCycleLength = cycleLengths.max()
            let mean = s.avgCycleLength!
            let variance = cycleLengths.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(cycleLengths.count)
            s.cycleStdDev = variance.squareRoot()
            s.variabilityLabel = (s.cycleStdDev ?? 0) < 2.5 ? String(localized: "规律")
                : (s.cycleStdDev ?? 0) < 6.0 ? String(localized: "较规律")
                : String(localized: "不规律")
        }
        if !cycleStartPeriodLengths.isEmpty {
            s.avgPeriodLength = Double(cycleStartPeriodLengths.reduce(0, +)) / Double(cycleStartPeriodLengths.count)
            s.minPeriodLength = cycleStartPeriodLengths.min()
            s.maxPeriodLength = cycleStartPeriodLengths.max()
        }

        return s
    }

    /// 从过滤后的周期数据重新计算规律度(与 CyclePredictor 相同的逻辑)
    static func computeRegularity(from periods: [PeriodDay]) -> String {
        guard !periods.isEmpty else { return "—" }

        let today = Cal.startOfDay(Date())
        let sortedDates = Array(Set(periods.map { Cal.startOfDay($0.date) }))
            .filter { $0 <= today }
            .sorted()
        guard !sortedDates.isEmpty else { return "—" }

        // 聚类经期段
        var spans: [(start: Date, length: Int)] = []
        var spanStart = sortedDates[0]
        var spanEnd = sortedDates[0]
        var spanLen = 1
        for i in 1..<sortedDates.count {
            let gap = Cal.current.dateComponents([.day], from: spanEnd, to: sortedDates[i]).day ?? 0
            if gap <= Self.maxGapWithinPeriod {
                spanLen += 1
                spanEnd = sortedDates[i]
            } else {
                spans.append((spanStart, spanLen))
                spanStart = sortedDates[i]
                spanEnd = sortedDates[i]
                spanLen = 1
            }
        }
        spans.append((spanStart, spanLen))

        // 真正的周期起点
        var cycleStarts: [Date] = []
        for span in spans {
            if let last = cycleStarts.last {
                let gap = Cal.current.dateComponents([.day], from: last, to: span.start).day ?? 0
                if gap < Self.minCycle { continue }
            }
            cycleStarts.append(span.start)
        }

        // 周期长度
        var lengths: [Int] = []
        if cycleStarts.count >= 2 {
            for i in 1..<cycleStarts.count {
                let len = Cal.current.dateComponents([.day], from: cycleStarts[i - 1], to: cycleStarts[i]).day ?? 0
                if len >= Self.minCycle && len <= Self.maxCycle {
                    lengths.append(len)
                }
            }
        }

        guard !lengths.isEmpty else { return "—" }
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let variance = lengths.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(lengths.count)
        let std = variance.squareRoot()

        switch std {
        case ..<2.5: return String(localized: "规律")
        case ..<6.0: return String(localized: "较规律")
        default:     return String(localized: "不规律")
        }
    }

    // MARK: - 工具

    /// Keep report temperatures compact and stable across locales. A trailing zero
    /// is removed, but at least one fractional digit remains (e.g. 36.5 or 36.42).
    static func formatTemperature(_ value: Double) -> String {
        let formatted = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        guard formatted.last == "0" else { return formatted }
        return String(formatted.dropLast())
    }

    /// Convert persisted HealthKit field identifiers into report-facing labels.
    static func healthFieldLabel(for rawKey: String) -> String {
        switch rawKey {
        case HealthKitPlanners.FieldKey.sleep.rawValue:
            return String(localized: "睡眠")
        case HealthKitPlanners.FieldKey.weight.rawValue:
            return String(localized: "体重")
        case HealthKitPlanners.FieldKey.basalBodyTemperature.rawValue:
            return String(localized: "基础体温")
        case HealthKitPlanners.FieldKey.spotting.rawValue:
            return String(localized: "点滴出血")
        default:
            return rawKey
        }
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 删除已生成的临时报告文件
    static func cleanupTempFile(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError
                    where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // ShareSheet may already have removed the file after sharing/canceling.
        } catch {
            NSLog("Maren clinical report cleanup failed for %@: %@", url.path, error.localizedDescription)
        }
    }

    // MARK: - DEBUG 自检

    @discardableResult
    static func selfCheck() -> Bool {
        // 验证 DateRange 全覆盖
        let ranges: [DateRange] = [.threeMonths, .sixMonths, .twelveMonths, .all]
        guard ranges.count == DateRange.allCases.count else { return false }
        // 空数据不崩溃
        let emptyStats = computeStats(periods: [], logs: [], intakes: [], medications: [])
        guard emptyStats.observedCycles == 0 else { return false }
        // 经期段聚类:连续 4 天不应分成 2 段
        let cal = Cal.current
        let today = Cal.startOfDay(Date())
        let span4: [PeriodDay] = (0..<4).compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -10 + i, to: today) else { return nil }
            return PeriodDay(date: d, flow: .medium)
        }
        let stats4 = computeStats(periods: span4, logs: [], intakes: [], medications: [])
        // 4 天连续 → 1 个周期起点段,长度 4, observedCycles = 0 (只有一个起点,无间隔)
        guard stats4.observedCycles == 0 else { return false }
        return true
    }
}
