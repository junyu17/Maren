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

    /// 生成 CSV(经期 / 每日记录 / 用药 / 打卡 / 自定义症状)+ 一份 PDF 概览,返回临时文件 URL。
    /// 隐私政策承诺「export all your data」——必须覆盖全部 5 个模型。
    static func makeExportFiles(periodDays: [PeriodDay], logs: [DailyLog],
                                medications: [Medication], intakes: [MedicationIntake],
                                customSymptoms: [CustomSymptom],
                                prediction: CyclePredictor.Prediction) -> [URL] {
        var urls: [URL] = []
        if let u = write(String(localized: "Maren-经期记录.csv"), periodCSV(periodDays)) { urls.append(u) }
        if let u = write(String(localized: "Maren-每日记录.csv"), logCSV(logs)) { urls.append(u) }
        if let u = write(String(localized: "Maren-用药.csv"), medicationCSV(medications)) { urls.append(u) }
        if let u = write(String(localized: "Maren-用药打卡.csv"), intakeCSV(intakes, medications: medications)) { urls.append(u) }
        if let u = write(String(localized: "Maren-自定义症状.csv"), customSymptomCSV(customSymptoms)) { urls.append(u) }
        if let u = makePDF(periodDays: periodDays, logs: logs, medications: medications,
                           intakes: intakes, customSymptoms: customSymptoms,
                           prediction: prediction) { urls.append(u) }
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

    /// 用药定义 CSV(药名 / emoji / 提醒设置)。
    static func medicationCSV(_ medications: [Medication]) -> String {
        var rows = [[String(localized: "名称"),
                     String(localized: "图标"),
                     String(localized: "提醒"),
                     String(localized: "提醒时间"),
                     String(localized: "高级排程")].joined(separator: ",")]
        for m in medications.sorted(by: { $0.createdAt < $1.createdAt }) {
            let reminder = m.reminderEnabled ? String(localized: "开") : String(localized: "关")
            let time = m.reminderEnabled
                ? String(format: "%02d:%02d", m.reminderHour, m.reminderMinute)
                : ""
            let slots = m.proScheduleEnabled ? m.slots.map { slot in
                String(format: "%02d:%02d", slot.hour, slot.minute) + " " + slot.weekdaysLabel
            } : []
            let cells = [m.name, m.emoji, reminder, time, slots.joined(separator: "; ")]
            rows.append(cells.map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// 用药打卡 CSV(哪一天、哪个药)。用药名而非 UUID,用户可读。
    static func intakeCSV(_ intakes: [MedicationIntake], medications: [Medication]) -> String {
        // 药 id -> 药名,导出成用户可读的名称(找不到的药回退显示 UUID)。
        let nameByID = Dictionary(medications.map { ($0.id, $0.name) },
                                  uniquingKeysWith: { a, _ in a })
        var rows = [[String(localized: "日期"),
                     String(localized: "用药"),
                     String(localized: "打卡时间")].joined(separator: ",")]
        for i in intakes.sorted(by: { $0.takenAt < $1.takenAt }) {
            let name = nameByID[i.medicationId] ?? i.medicationId.uuidString
            let cells = [isoDay.string(from: Cal.startOfDay(i.takenAt)),
                         name,
                         DateFormatter.localizedString(from: i.takenAt, dateStyle: .short, timeStyle: .short)]
            rows.append(cells.map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// 自定义症状 CSV(key -> 显示名 映射,供解读每日记录里的 symptom_codes)。
    static func customSymptomCSV(_ symptoms: [CustomSymptom]) -> String {
        var rows = [[String(localized: "代码"),
                     String(localized: "名称"),
                     String(localized: "图标")].joined(separator: ",")]
        for s in symptoms.sorted(by: { $0.createdAt < $1.createdAt }) {
            let cells = [s.key, s.label, s.emoji]
            rows.append(cells.map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: - PDF 概览(F5 承诺的 CSV / PDF 两种格式)

    static func makePDF(periodDays: [PeriodDay], logs: [DailyLog],
                        medications: [Medication], intakes: [MedicationIntake],
                        customSymptoms: [CustomSymptom],
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

            /// 绘制文本,支持折行:超宽文本按宽度换行,而不是画出页面边界外。
            func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], lineHeight: CGFloat) {
                let maxWidth = pageWidth - margin * 2
                let ns = text as NSString
                let size = ns.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading],
                                           attributes: attrs, context: nil)
                let lines = max(1, Int(ceil(size.height / lineHeight)))
                newPageIfNeeded(lineHeight * CGFloat(lines))
                ns.draw(with: CGRect(x: margin, y: y, width: maxWidth,
                                     height: lineHeight * CGFloat(lines)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attrs, context: nil)
                y += lineHeight * CGFloat(lines)
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
            y += 10

            // 用药与打卡(P1-8:导出必须覆盖全部模型,否则与「export all your data」承诺不符)。
            draw(String(localized: "用药"), headAttrs, lineHeight: 20)
            if medications.isEmpty {
                draw("—", bodyAttrs, lineHeight: 16)
            } else {
                for m in medications.sorted(by: { $0.createdAt < $1.createdAt }) {
                    let slots = m.proScheduleEnabled ? m.slots.map { slot in
                        String(format: "%02d:%02d", slot.hour, slot.minute) + " " + slot.weekdaysLabel
                    }.joined(separator: "; ") : ""
                    draw("\(m.name) \(m.emoji)" + (slots.isEmpty ? "" : "  \(slots)"),
                         bodyAttrs, lineHeight: 15)
                }
            }
            y += 10

            draw(String(localized: "用药打卡"), headAttrs, lineHeight: 20)
            if intakes.isEmpty {
                draw("—", bodyAttrs, lineHeight: 16)
            } else {
                let nameByID = Dictionary(medications.map { ($0.id, $0.name) },
                                          uniquingKeysWith: { a, _ in a })
                for i in intakes.sorted(by: { $0.takenAt < $1.takenAt }) {
                    let name = nameByID[i.medicationId] ?? i.medicationId.uuidString
                    draw("\(isoDay.string(from: Cal.startOfDay(i.takenAt)))    \(name)",
                         bodyAttrs, lineHeight: 15)
                }
            }
            y += 10

            draw(String(localized: "自定义症状"), headAttrs, lineHeight: 20)
            if customSymptoms.isEmpty {
                draw("—", bodyAttrs, lineHeight: 16)
            } else {
                for s in customSymptoms.sorted(by: { $0.createdAt < $1.createdAt }) {
                    draw("\(s.key)    \(s.label) \(s.emoji)", bodyAttrs, lineHeight: 15)
                }
            }
        }

        return writeData(String(localized: "Maren-健康记录.pdf"), data)
    }

    // MARK: - 工具

    /// CSV 字段转义:含逗号 / 引号 / 换行(含 \r,Excel 会当作换行)时用双引号包裹并转义内部引号。
    private static func esc(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
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
