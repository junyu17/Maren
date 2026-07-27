import Foundation
import UIKit

/// F5:一键导出。用户录入的原始数据永远可带走 —— 这是「你的数据永远属于你」的落地。
/// 生成 CSV / PDF 到临时文件,交给系统分享面板。纯本地,不上传任何服务器。
enum DataExport {

    /// 机器可读日期,固定 ISO 格式,不随语言变化,保证导出文件可被表格软件解析。
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - 入口

    /// 生成两份 CSV(经期 / 每日记录)+ 一份 PDF 概览,返回临时文件 URL。
    static func makeExportFiles(periodDays: [PeriodDay], logs: [DailyLog],
                                prediction: CyclePredictor.Prediction) -> [URL] {
        var urls: [URL] = []
        if let u = write(String(localized: "Maren-经期记录.csv"), periodCSV(periodDays)) { urls.append(u) }
        if let u = write(String(localized: "Maren-每日记录.csv"), logCSV(logs)) { urls.append(u) }
        if let u = makePDF(periodDays: periodDays, logs: logs, prediction: prediction) { urls.append(u) }
        return urls
    }

    // MARK: - CSV 内容

    static func periodCSV(_ periodDays: [PeriodDay]) -> String {
        // 表头跟随界面语言;同时额外输出一列语言无关的 flow 代码,
        // 保证换了手机语言后导出的历史文件依然能被正确解析 / 再导入。
        var rows = [[String(localized: "日期"),
                     String(localized: "流量"),
                     "flow_code"].joined(separator: ",")]
        for d in periodDays.sorted(by: { $0.date < $1.date }) {
            let cells = [isoDay.string(from: d.date), d.flow.label, "\(d.flow.rawValue)"]
            rows.append(cells.map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func logCSV(_ logs: [DailyLog]) -> String {
        var rows = [[String(localized: "日期"),
                     String(localized: "心情"),
                     String(localized: "能量"),
                     String(localized: "疼痛"),
                     String(localized: "睡眠小时"),
                     String(localized: "体重"),
                     String(localized: "症状"),
                     String(localized: "备注"),
                     "symptom_codes"].joined(separator: ",")]
        for log in logs.sorted(by: { $0.date < $1.date }) {
            let mood = log.mood?.label ?? ""
            // 未选的值导出为空,而不是 0 / -1 这种会被误读成「记了 0 分」的哨兵值。
            let energy = log.energy > 0 ? "\(log.energy)" : ""
            let pain = log.pain >= 0 ? "\(log.pain)" : ""
            let sleep = log.sleepHours.map { "\($0)" } ?? ""
            let weight = log.weight.map { "\($0)" } ?? ""
            let symptoms = log.symptoms.map { Symptoms.label(for: $0) }.joined(separator: " / ")
            let codes = log.symptoms.joined(separator: "|")
            let cells = [isoDay.string(from: log.date), mood, energy, pain, sleep, weight, symptoms, log.note, codes]
            rows.append(cells.map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: - PDF 概览(F5 承诺的 CSV / PDF 两种格式)

    static func makePDF(periodDays: [PeriodDay], logs: [DailyLog],
                        prediction: CyclePredictor.Prediction) -> URL? {
        let pageWidth: CGFloat = 595   // A4 @72dpi
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let title = String(localized: "Maren 健康记录导出")
        let generated = String(localized: "导出时间:\(Cal.fullDateFormatter.string(from: Date()))")

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22)
        ]
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13)
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray
        ]

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin
            ctx.beginPage()

            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > pageHeight - margin {
                    ctx.beginPage()
                    y = margin
                }
            }

            func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], lineHeight: CGFloat) {
                newPageIfNeeded(lineHeight)
                text.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)
                y += lineHeight
            }

            draw(title, titleAttrs, lineHeight: 30)
            draw(generated, bodyAttrs, lineHeight: 22)

            // 概览
            draw(String(localized: "周期概览"), headAttrs, lineHeight: 20)
            let avg = prediction.averageCycleLength.map { "\(Int($0.rounded()))" } ?? "—"
            let periodLen = prediction.averagePeriodLength.map { String(format: "%.1f", $0) } ?? "—"
            draw(String(localized: "平均周期:\(avg) 天    规律度:\(prediction.regularity)    已观测:\(prediction.observedCycleCount) 个周期"),
                 bodyAttrs, lineHeight: 16)
            draw(String(localized: "平均经期长度:\(periodLen) 天"), bodyAttrs, lineHeight: 22)

            draw(String(localized: "以上为基于个人记录的统计学估算,仅供参考,不构成医学建议。"),
                 bodyAttrs, lineHeight: 24)

            // 经期记录
            draw(String(localized: "经期记录"), headAttrs, lineHeight: 20)
            if periodDays.isEmpty {
                draw("—", bodyAttrs, lineHeight: 16)
            } else {
                for d in periodDays.sorted(by: { $0.date < $1.date }) {
                    draw("\(isoDay.string(from: d.date))    \(d.flow.label)", bodyAttrs, lineHeight: 15)
                }
            }
            y += 10

            // 每日记录
            draw(String(localized: "每日记录"), headAttrs, lineHeight: 20)
            if logs.isEmpty {
                draw("—", bodyAttrs, lineHeight: 16)
            } else {
                for log in logs.sorted(by: { $0.date < $1.date }) {
                    var parts: [String] = [isoDay.string(from: log.date)]
                    if let m = log.mood { parts.append(m.label) }
                    if log.energy > 0 { parts.append(String(localized: "能量 \(log.energy)")) }
                    if log.pain >= 0 { parts.append(String(localized: "疼痛 \(log.pain)")) }
                    if !log.symptoms.isEmpty {
                        parts.append(log.symptoms.map { Symptoms.label(for: $0) }.joined(separator: "/"))
                    }
                    if !log.note.isEmpty { parts.append(log.note) }
                    draw(parts.joined(separator: "    "), bodyAttrs, lineHeight: 15)
                }
            }
        }

        return writeData(String(localized: "Maren-健康记录.pdf"), data)
    }

    // MARK: - 工具

    /// CSV 字段转义:含逗号 / 引号 / 换行时用双引号包裹并转义内部引号。
    private static func esc(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private static func write(_ name: String, _ content: String) -> URL? {
        // 加 BOM,保证中文在 Excel 里不乱码。
        let data = "\u{FEFF}".data(using: .utf8)! + Data(content.utf8)
        return writeData(name, data)
    }

    private static func writeData(_ name: String, _ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
