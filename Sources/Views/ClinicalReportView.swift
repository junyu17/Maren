import SwiftUI
import SwiftData

/// Report export entitlement is evaluated at the moment the export starts.
/// Keeping this as a pure policy makes the paywall boundary testable without
/// constructing a SwiftUI view or a SwiftData container.
enum ClinicalReportAccessPolicy {
    static func effectiveOptions(
        premium: Bool,
        selectedRange: ClinicalReportEngine.DateRange,
        includeNotes: Bool
    ) -> (range: ClinicalReportEngine.DateRange, includeNotes: Bool) {
        guard premium else { return (.sixMonths, false) }
        return (selectedRange, includeNotes)
    }
}

/// 专业级临床就诊报告:日期范围选择 + 预览 + PDF 生成/分享。
/// 免费用户:固定合理默认范围(近 6 个月),无备注,可生成/分享/导出/删除。
/// Premium 用户:可自定义全部范围和备注。
struct ClinicalReportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @State private var selectedRange: ClinicalReportEngine.DateRange = .sixMonths
    @State private var includeNotes = false
    @State private var pdfURL: URL?
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var showPDFSecurityWarning = false
    @State private var showPaywall = false

    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength

    @ObservedObject private var store = Store.shared
    @ObservedObject private var dataChangeCenter = LocalDataChangeCenter.shared

    private var medications: [Medication] {
        (try? context.fetch(FetchDescriptor<Medication>())) ?? []
    }
    private var intakes: [MedicationIntake] {
        (try? context.fetch(FetchDescriptor<MedicationIntake>())) ?? []
    }
    private var manualCycle: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }
    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: manualCycle)
    }

    private var trackerRevision: UInt64 {
        dataChangeCenter.lastEvent?.revision ?? 0
    }

    var body: some View {
        let _ = trackerRevision
        ScrollView {
            VStack(spacing: 16) {
                rangeSection
                previewSection
                generateButton
            }
            .padding()
        }
        .navigationTitle(String(localized: "临床就诊报告"))
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 56, for: .scrollContent)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url], temporaryURLs: [url])
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert(String(localized: "生成失败"), isPresented: $showError) {
            Button(String(localized: "好")) {}
        } message: {
            Text(String(localized: "未能生成报告 PDF,请检查设备存储空间后重试。"))
        }
        .alert(String(localized: "生成报告前请注意"), isPresented: $showPDFSecurityWarning) {
            Button(String(localized: "继续生成")) { generateReport() }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "临床报告 PDF 不会加密,也不会设置密码。继续前请确认你会安全分享和存储这份报告。"))
        }
        .onDisappear {
            if let url = pdfURL {
                ClinicalReportEngine.cleanupTempFile(url)
                pdfURL = nil
            }
        }
    }

    // MARK: - 日期范围选择

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "报告范围"), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))

            ForEach(ClinicalReportEngine.DateRange.allCases) { range in
                let isLocked = !store.premium && range != .sixMonths
                Button {
                    if isLocked {
                        showPaywall = true
                    } else {
                        selectedRange = range
                    }
                } label: {
                    HStack {
                        Text(range.label)
                            .font(.subheadline)
                            .foregroundStyle(isLocked ? .tertiary : .primary)
                        Spacer()
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else if selectedRange == range {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(FlowLevel.medium.tint)
                                .accessibilityLabel(String(localized: "已选择"))
                        } else {
                            Circle()
                                .strokeBorder(.secondary, lineWidth: 1.5)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLocked ? String(localized: "\(range.label) · 需升级 Premium") : range.label)
                .accessibilityAddTraits(selectedRange == range && !isLocked ? .isSelected : [])
            }

            Toggle(String(localized: "包含用户备注"), isOn: $includeNotes)
                .font(.subheadline)
                .disabled(!store.premium)
                .onChange(of: includeNotes) { _, newValue in
                    if !store.premium { includeNotes = false }
                }

            if !store.premium {
                Button {
                    showPaywall = true
                } label: {
                    Text(String(localized: "升级 Premium 可自定义报告范围和包含内容。"))
                        .font(.caption2).foregroundStyle(.blue)
                }
                .accessibilityLabel(String(localized: "升级 Premium,自定义报告范围和内容"))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 预览摘要

    private var previewSection: some View {
        let filtered = filterData()
        let stats = ClinicalReportEngine.computeStats(
            periods: filtered.periods, logs: filtered.logs,
            intakes: filtered.intakes, medications: medications,
            rangeStart: selectedRange.startDate(from: Cal.startOfDay(Date())),
            rangeEnd: Cal.startOfDay(Date()))

        return VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "报告预览"), systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))

            previewRow(String(localized: "观测周期"), "\(stats.observedCycles) 个")
            if let avg = stats.avgCycleLength {
                previewRow(String(localized: "平均周期"), "\(String(format: "%.1f", avg)) 天")
            }
            if let avg = stats.avgPeriodLength {
                previewRow(String(localized: "平均经期"), "\(String(format: "%.1f", avg)) 天")
            }
            previewRow(String(localized: "每日记录"), "\(filtered.logs.count) 条")
            previewRow(String(localized: "用药打卡"), "\(filtered.intakes.count) 次")

            if stats.topTrackers.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "高频追踪项")).font(.caption).foregroundStyle(.secondary)
                    ForEach(stats.topTrackers.prefix(3), id: \.0) { key, count in
                        Text(String(localized: "  \(Symptoms.label(for: key)): \(count) 次"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Text(String(localized: "报告将生成 PDF 格式,可在就诊时分享给医生。"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    // MARK: - 生成按钮

    private var generateButton: some View {
        Button {
            showPDFSecurityWarning = true
        } label: {
            Label(String(localized: "生成并分享报告"), systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(FlowLevel.medium.tint)
        .accessibilityLabel(String(localized: "生成并分享临床就诊报告"))
    }

    private func generateReport() {
        // The page can remain open while a subscription expires.  Re-read
        // StoreKit's verified current entitlement immediately before building
        // the report so a stale view cannot export Premium-only content.
        Task { @MainActor in
            await store.refreshEntitlements()
            let options = ClinicalReportAccessPolicy.effectiveOptions(
                premium: store.premium,
                selectedRange: selectedRange,
                includeNotes: includeNotes)
            let filtered = filterData(for: options.range)
            let data = ClinicalReportEngine.ReportData(
                periodDays: filtered.periods, logs: filtered.logs,
                medications: medications, intakes: filtered.intakes,
                prediction: prediction, includeNotes: options.includeNotes,
                range: options.range)
            if let url = ClinicalReportEngine.generatePDF(from: data) {
                // Remove previous temp file before replacing
                if let oldURL = pdfURL {
                    ClinicalReportEngine.cleanupTempFile(oldURL)
                }
                pdfURL = url
                showShareSheet = true
            } else {
                showError = true
            }
        }
    }

    // MARK: - 数据过滤(排除未来日期,一致边界)

    private func filterData() -> (periods: [PeriodDay], logs: [DailyLog], intakes: [MedicationIntake]) {
        filterData(for: selectedRange)
    }

    private func filterData(for range: ClinicalReportEngine.DateRange) -> (periods: [PeriodDay], logs: [DailyLog], intakes: [MedicationIntake]) {
        let today = Cal.startOfDay(Date())
        guard let startDate = range.startDate(from: today) else {
            // "全部"范围:只过滤未来日期
            return (
                periodDays.filter { Cal.startOfDay($0.date) <= today },
                logs.filter { Cal.startOfDay($0.date) <= today },
                intakes.filter { Cal.startOfDay(DayKey.date(from: $0.dayKey)) <= today }
            )
        }
        return (
            periodDays.filter { Cal.startOfDay($0.date) >= startDate && Cal.startOfDay($0.date) <= today },
            logs.filter { Cal.startOfDay($0.date) >= startDate && Cal.startOfDay($0.date) <= today },
            intakes.filter {
                let d = Cal.startOfDay(DayKey.date(from: $0.dayKey))
                return d >= startDate && d <= today
            }
        )
    }
}

#Preview {
    NavigationStack {
        ClinicalReportView()
            .modelContainer(for: [PeriodDay.self, DailyLog.self], inMemory: true)
    }
}
