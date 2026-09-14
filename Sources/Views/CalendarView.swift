import SwiftUI
import SwiftData

/// F1:经期 / 周期日历追踪。月视图,点某天可标记经期与流量。
struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @State private var visibleMonth: Date
    @State private var selectedDay: Date?
    @State private var exportURLs: [URL]?
    @State private var showExportFailed = false
    @State private var exportFailureMessage = ""
    @State private var showExportSecurityWarning = false
    @State private var showPeriodAlert = false
    @State private var periodAlertTitle = ""
    @State private var periodAlertMessage = ""
    @State private var showPhaseInfo = false
    @State private var showClinicalReport = false

    /// 跟随用户地区的星期简写与起始日(中国=周一开头,美国=周日开头)。
    private var weekdaySymbols: [String] { Cal.orderedWeekdaySymbols }

    /// 日期 -> 该天的经期记录,便于 O(1) 查询。
    private var periodByDay: [Date: PeriodDay] {
        Dictionary(periodDays.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // 手动周期设置(开启后优先于统计学习);放这里是为了改动后界面立刻重算。
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength
    @AppStorage("notif.periodEnabled") private var periodReminderEnabled = false

    init(focusedDate: Date? = nil) {
        let normalizedDate = focusedDate.map(Cal.startOfDay)
        _selectedDay = State(initialValue: normalizedDate)
        if let normalizedDate {
            let components = Cal.current.dateComponents([.year, .month], from: normalizedDate)
            _visibleMonth = State(initialValue: Cal.current.date(from: components) ?? normalizedDate)
        } else {
            _visibleMonth = State(initialValue: Cal.startOfDay(Date()))
        }
    }

    private var manual: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }

    /// F2:自适应预测(每次数据变化自动重算)。
    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: manual)
    }

    /// 预测经期区间内、且尚未被实际记录的日子(用于日历上的虚线标记)。
    private func isPredicted(_ day: Date, _ p: CyclePredictor.Prediction) -> Bool {
        guard let start = p.nextRangeStart, let end = p.nextRangeEnd else { return false }
        return day >= start && day <= end && periodByDay[day] == nil
    }

    private var periodDatesSet: Set<Date> { Set(periodDays.map { $0.date }) }

    var body: some View {
        // 每次刷新只算一次预测和一次日期集合,再传给各个子视图。
        // 之前 isPredicted / phase 各自读一次 `prediction`,等于每个日历格重算两遍,
        // 一屏 31 格就是 60+ 次全量计算。
        let p = prediction
        let periodDates = periodDatesSet

        return NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayRow
                    monthGrid(p, periodDates)
                    legend
                    phaseDisclaimer
                    predictionCard(p)
                    summaryCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .marenReadableWidth()
            }
            .navigationTitle("Maren")
            .navigationBarTitleDisplayMode(.inline)
            // 给底部留出空间,避免最后一张卡片被浮动标签栏遮住。
            .contentMargins(.bottom, 56, for: .scrollContent)
            .onAppear { WidgetSync.refresh(periodDays: periodDays, logs: logs) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LocalSearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("全局搜索"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showExportSecurityWarning = true
                        } label: {
                            Label(String(localized: "导出原始数据"), systemImage: "square.and.arrow.up")
                        }
                        .disabled(periodDays.isEmpty && logs.isEmpty)

                        Button {
                            showClinicalReport = true
                        } label: {
                            Label(String(localized: "临床就诊报告"), systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("导出数据")
                }
            }
            .sheet(item: Binding(
                get: { exportURLs.map { ExportBox(urls: $0) } },
                set: { exportURLs = $0?.urls }
            )) { box in
                ShareSheet(items: box.urls, temporaryURLs: box.urls)
            }
            .sheet(isPresented: $showPhaseInfo) {
                PhaseInfoView()
            }
            .sheet(isPresented: $showClinicalReport) {
                NavigationStack {
                    ClinicalReportView()
                }
            }
            .sheet(item: Binding(
                get: { selectedDay.map { DayBox(date: $0) } },
                set: { selectedDay = $0?.date }
            )) { box in
                PeriodDayEditor(date: box.date, existing: periodByDay[box.date]) { flow in
                    upsertPeriod(on: box.date, flow: flow)
                } onClear: {
                    clearPeriod(on: box.date)
                }
                .presentationDetents([.height(320)])
            }
            .alert("导出失败", isPresented: $showExportFailed) {
                Button("好") {}
            } message: {
                Text(exportFailureMessage)
            }
            .alert(String(localized: "导出前请注意"), isPresented: $showExportSecurityWarning) {
                Button(String(localized: "继续导出")) { generateRawExport() }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "原始 CSV/PDF 导出不会加密,也不会设置密码。继续前请确认你会安全分享和存储这些文件。"))
            }
            .alert(periodAlertTitle, isPresented: $showPeriodAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(periodAlertMessage)
            }
            .onDisappear {
                if let urls = exportURLs {
                    ShareSheet.cleanupTemporaryURLs(urls)
                    exportURLs = nil
                }
            }
        }
    }

    private func generateRawExport() {
        if let oldURLs = exportURLs {
            ShareSheet.cleanupTemporaryURLs(oldURLs)
            exportURLs = nil
        }

        let meds: [Medication]
        let intakes: [MedicationIntake]
        let customs: [CustomSymptom]
        do {
            meds = try context.fetch(FetchDescriptor<Medication>())
            intakes = try context.fetch(FetchDescriptor<MedicationIntake>())
            customs = try context.fetch(FetchDescriptor<CustomSymptom>())
        } catch {
            exportFailureMessage = String(localized: "无法读取本地记录,导出未开始,请重试。")
            showExportFailed = true
            return
        }

        let urls = DataExport.makeExportFiles(
            periodDays: periodDays, logs: logs,
            medications: meds, intakes: intakes, customSymptoms: customs,
            prediction: prediction)
        guard urls.count == 6 else {
            ShareSheet.cleanupTemporaryURLs(urls)
            exportFailureMessage = String(localized: "未能生成完整导出文件,请检查设备存储空间后重试。")
            showExportFailed = true
            return
        }
        exportURLs = urls
    }

    // MARK: - 子视图

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation { visibleMonth = Cal.addMonths(-1, to: visibleMonth) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(MarenDesign.accentTint(opacity: 0.8))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("上个月")
            Spacer()
            Text(Cal.monthTitleFormatter.string(from: visibleMonth))
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                withAnimation { visibleMonth = Cal.addMonths(1, to: visibleMonth) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(MarenDesign.accentTint(opacity: 0.8))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("下个月")
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    // Keep the weekday labels aligned with the 44 pt date
                    // targets below, including when Dynamic Type is large.
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private func monthGrid(_ p: CyclePredictor.Prediction,
                           _ periodDates: Set<Date>) -> some View {
        let grid = Cal.monthGrid(for: visibleMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let today = Date()
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<grid.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(minHeight: 44)
            }
            ForEach(grid.days, id: \.self) { day in
                DayCell(
                    day: day,
                    period: periodByDay[day],
                    isToday: Cal.isSameDay(day, today),
                    isPredicted: isPredicted(day, p),
                    phase: PhaseModel.phase(for: day, prediction: p, periodDates: periodDates)
                )
                .onTapGesture { selectedDay = day }
            }
        }
    }

    private var legend: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                ForEach(FlowLevel.allCases) { level in
                    HStack(spacing: 4) {
                        Circle().fill(level.tint).frame(width: 10, height: 10)
                        Text(level.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .foregroundStyle(FlowLevel.light.tint)
                        .frame(width: 12, height: 12)
                    Text("预计开始区间")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach([CyclePhase.follicular, .ovulatory, .luteal]) { ph in
                    HStack(spacing: 4) {
                        Circle().fill(ph.legendFill).frame(width: 10, height: 10)
                        Text(ph.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            // 阶段科普入口:让「多色阶段」从好看变得能看懂。
            Button {
                showPhaseInfo = true
            } label: {
                Label("了解各阶段", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.current.accent)
            }
            .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    /// 阶段图例与预测卡片之间的正式声明:明确「以上均为预测,非医学结论」。
    private var phaseDisclaimer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("以上阶段与日期为基于你的记录的统计预测,仅供参考;不构成医学建议,不可作为避孕或备孕依据。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .marenOutlineCard(cornerRadius: MarenDesign.radiusS)
    }

    /// F2 预测卡片:诚实呈现「下次经期 + 置信区间 + 规律度」,不吹精准、不涉排卵/避孕。
    @ViewBuilder
    private func predictionCard(_ p: CyclePredictor.Prediction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").foregroundStyle(FlowLevel.medium.tint)
                Text("周期预测").font(.subheadline.weight(.semibold))
                Spacer()
                if p.hasEnoughData {
                    // 手动模式不谈「把握度」——那是统计概念,手动设置没有统计依据。
                    Text(p.isManual ? String(localized: "手动设置") : String(localized: "把握度 \(p.confidence.label)"))
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(MarenDesign.elevatedSurface, in: Capsule())
                }
            }

            if p.hasEnoughData, let start = p.nextRangeStart, let end = p.nextRangeEnd {
                Text(predictionHeadline(p))
                    .font(.headline)
                Text("预计区间:\(rangeText(start, end))")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    if p.isManual {
                        // 手动模式:展示用户填的设置,不谎报「已观测 N 个周期」或规律度。
                        metric("周期长度", p.averageCycleLength.map { String(localized: "\(Int($0.rounded())) 天") } ?? "—")
                        metric("经期长度", p.averagePeriodLength.map { String(localized: "\(Int($0.rounded())) 天") } ?? "—")
                        metric("来源", String(localized: "手动"))
                    } else {
                        metric("平均周期", p.averageCycleLength.map { String(localized: "\(Int($0.rounded())) 天") } ?? "—")
                        metric("规律度", p.regularity)
                        metric("已观测", String(localized: "\(p.observedCycleCount) 个周期"))
                    }
                }
                .padding(.top, 2)
                Text(p.isManual
                     ? "按你在「设置」里填的周期推算。关掉后会改回自动学习你的真实记录。"
                     : "基于你的真实记录自适应估算,仅供参考,不代表排卵或避孕判断。")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("再记录一个完整周期,就能开始预测")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Maren 只学习你自己的真实周期,不套用「第 14 天」模板。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .marenAccentCard(cornerRadius: MarenDesign.radiusM)
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    /// 预测标题:若已过预测日仍无记录,诚实提示「可能已延后 N 天」。
    private func predictionHeadline(_ p: CyclePredictor.Prediction) -> String {
        guard let next = p.nextPeriodStart else { return String(localized: "下次经期预测中") }
        let today = Cal.startOfDay(Date())
        let days = Cal.current.dateComponents([.day], from: today, to: next).day ?? 0
        if days > 0 { return String(localized: "下次经期约在 \(days) 天后") }
        if days == 0 { return String(localized: "预计经期就在今天前后") }
        return String(localized: "可能已延后约 \(-days) 天")
    }

    private func rangeText(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private var summaryCard: some View {
        let count = periodDays.filter {
            Cal.current.isDate($0.date, equalTo: visibleMonth, toGranularity: .month)
        }.count
        return HStack {
            Image(systemName: "drop.fill").foregroundStyle(FlowLevel.medium.tint)
            Text(String(localized: "本月记录经期 \(count) 天"))
                .font(.subheadline)
            Spacer()
        }
        .marenCard(cornerRadius: MarenDesign.radiusM, shadowed: false)
    }

    // MARK: - 数据操作

    private func upsertPeriod(on date: Date, flow: FlowLevel) {
        let key = Cal.startOfDay(date)
        let dayKey = DayKey.from(key)
        let day: PeriodDay
        // Query-backed dictionaries update on the next SwiftUI transaction.
        // Fetch the key from SwiftData at mutation time so two quick taps
        // cannot both observe "missing" and insert duplicate PeriodDay rows.
        let existing: PeriodDay?
        do {
            existing = try context.fetch(
                FetchDescriptor<PeriodDay>(
                    predicate: #Predicate { $0.dayKey == dayKey },
                    sortBy: [SortDescriptor(\PeriodDay.updatedAt, order: .reverse)]
                )
            ).first
        } catch {
            presentPeriodAlert(
                title: String(localized: "保存失败"),
                message: "\(String(localized: "暂时无法读取这一天的经期记录,未写入新数据。"))\n\(error.localizedDescription)"
            )
            return
        }
        if let existing {
            existing.flow = flow
            existing.updatedAt = Date()
            existing.importedFromHealth = false
            day = existing
        } else {
            let new = PeriodDay(date: key, flow: flow)
            context.insert(new)
            day = new
        }
        guard savePeriodContext() else { return }

        do {
            let actual = try fetchActualData()
            guard let actualDay = actual.periodDays.first(where: { $0.dayKey == day.dayKey }) else {
                presentPeriodAlert(
                    title: String(localized: "已保存,但刷新失败"),
                    message: String(localized: "经期已保存,但未能读取刚保存的记录。")
                )
                return
            }
            selectedDay = nil
            refreshPeriodReminder(periodDays: actual.periodDays, logs: actual.logs)

            guard HealthKitBridge.syncEnabled,
                  HealthKitBridge.selectedTypes.contains(.menstrualFlow) else { return }

            // HealthKit stores cycle-start metadata on every sample. Updating
            // one local day can therefore also require rewriting its next
            // local day. Imported days are excluded because they are never
            // written back to HealthKit.
            let resync = periodDaysToResync(
                around: actualDay.dayKey,
                periodDays: actual.periodDays,
                deleting: false
            )
            Task { @MainActor in
                do {
                    try await syncPeriodDaysToHealth(
                        resync.targets,
                        allLocalDays: resync.allLocalDays
                    )
                } catch {
                    presentPeriodAlert(
                        title: String(localized: "Apple Health 同步失败"),
                        message: "\(String(localized: "经期已保存,但未能同步到 Apple Health。"))\n\(error.localizedDescription)"
                    )
                }
            }
        } catch {
            presentPeriodAlert(
                title: String(localized: "已保存,但刷新失败"),
                message: "\(String(localized: "经期已保存,但未能刷新提醒和小组件。"))\n\(error.localizedDescription)"
            )
        }
    }

    private func clearPeriod(on date: Date) {
        let key = Cal.startOfDay(date)
        guard let existing = periodByDay[key] else { return }
        let defaults = UserDefaults.standard
        Task { @MainActor in
            do {
                try await UserContentDeletion.deletePeriodDay(
                    existing,
                    context: context,
                    notificationManager: NotificationManager.shared,
                    dailyEnabled: defaults.bool(forKey: "notif.dailyEnabled"),
                    dailyHour: defaults.object(forKey: "notif.dailyHour") as? Int ?? 21,
                    periodEnabled: defaults.bool(forKey: "notif.periodEnabled"),
                    periodAdvanceDays: defaults.object(forKey: ProReminderSettings.Keys.periodAdvanceDays) as? Int ?? 2,
                    smartEnabled: defaults.bool(forKey: ProReminderSettings.Keys.smartEnabled),
                    pmsEnabled: defaults.bool(forKey: ProReminderSettings.Keys.pmsEnabled),
                    storePremium: Store.shared.premium,
                    manualCycle: manual
                )
                selectedDay = nil
            } catch let deletionError as DeletionError {
                selectedDay = nil
                switch deletionError {
                case .healthKitSyncFailed(let underlying):
                    presentPeriodAlert(
                        title: String(localized: "Apple Health 同步失败"),
                        message: "\(String(localized: "经期已删除,但未能完整同步 Apple Health。"))\n\(underlying.localizedDescription)"
                    )
                case .derivedRefreshFailed(let underlying):
                    presentPeriodAlert(
                        title: String(localized: "经期已删除"),
                        message: "\(String(localized: "本机记录已删除,但未能刷新提醒和小组件。"))\n\(underlying.localizedDescription)"
                    )
                }
            } catch {
                presentPeriodAlert(
                    title: String(localized: "删除失败"),
                    message: "\(String(localized: "这条经期记录没有删除,原有数据未改动。"))\n\(error.localizedDescription)"
                )
            }
        }
    }

    /// Returns the local period days whose cycle-start metadata can change
    /// after an upsert or deletion, together with the complete local list used
    /// for the continuity calculation.
    private func periodDaysToResync(
        around changedDayKey: Int,
        periodDays: [PeriodDay],
        deleting: Bool
    ) -> (targets: [PeriodDay], allLocalDays: [PeriodDay]) {
        let localDays = periodDays
            .filter { !$0.importedFromHealth }
            .sorted { $0.dayKey < $1.dayKey }

        let keys = HealthKitPlanners.periodDayKeysToResync(
            afterChanging: changedDayKey,
            existingDayKeys: localDays.map(\.dayKey),
            deleting: deleting
        )
        return (localDays.filter { keys.contains($0.dayKey) }, localDays)
    }

    /// Rewrites every requested sample while preserving and returning the
    /// first HealthKit error. A neighbor correction must still be attempted
    /// if an earlier sample fails.
    private func syncPeriodDaysToHealth(
        _ targetDays: [PeriodDay],
        allLocalDays: [PeriodDay]
    ) async throws {
        guard !targetDays.isEmpty else { return }
        let flags = HealthKitPlanners.cycleStartFlags(
            for: allLocalDays.map(\.dayKey),
            calendar: Cal.gregorian
        )
        let writes = targetDays.map { day in
            HealthKitBridge.PeriodWriteSnapshot(
                date: day.date,
                flowRaw: day.flowRaw,
                isCycleStart: flags[day.dayKey] ?? true
            )
        }
        try await HealthKitBridge.syncPeriodRevision(deleteDate: nil, writes: writes)
    }

    @discardableResult
    private func savePeriodContext() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            presentPeriodAlert(
                title: String(localized: "保存失败"),
                message: "\(String(localized: "这次经期记录没有保存,原有数据未改动。"))\n\(error.localizedDescription)"
            )
            return false
        }
    }

    private func fetchActualData() throws -> (periodDays: [PeriodDay], logs: [DailyLog]) {
        let actualPeriodDays = try context.fetch(
            FetchDescriptor<PeriodDay>(sortBy: [SortDescriptor(\PeriodDay.dayKey)])
        )
        let actualLogs = try context.fetch(
            FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\DailyLog.dayKey)])
        )
        return (actualPeriodDays, actualLogs)
    }

    private func presentPeriodAlert(title: String, message: String) {
        periodAlertTitle = title
        periodAlertMessage = message
        showPeriodAlert = true
    }

    /// 经期数据一变,预测就变,已排期的提醒必须跟着重排。
    /// 否则提醒会停留在旧预测上(一次性触发后就再也不响)。
    private func refreshPeriodReminder(periodDays: [PeriodDay], logs: [DailyLog]) {
        let p = CyclePredictor.predict(from: periodDays, manual: manual)
        let next = p.nextPeriodStart
        let advance = Store.shared.premium ? ProReminderSettings.periodAdvanceDays : 2
        NotificationManager.shared.schedulePeriodReminder(enabled: periodReminderEnabled, advanceDays: advance, nextPeriodStart: next)
        // Pro 高级提醒跟随预测一起重排;免费层传 false 不残留。
        NotificationManager.shared.schedulePMSReminder(enabled: Store.shared.premium && ProReminderSettings.pmsEnabled, nextPeriodStart: next)
        NotificationManager.shared.scheduleSmartReminders(enabled: Store.shared.premium && ProReminderSettings.smartEnabled, prediction: p, logs: logs)
        WidgetSync.refresh(periodDays: periodDays, logs: logs)
    }
}

/// 让 Date 能用于 .sheet(item:)。
private struct DayBox: Identifiable {
    let date: Date
    var id: Date { date }
}

/// 让导出文件 URL 数组能用于 .sheet(item:)。
private struct ExportBox: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.lastPathComponent).joined() }
}

// MARK: - 单个日期格子

private struct DayCell: View {
    let day: Date
    let period: PeriodDay?
    let isToday: Bool
    let isPredicted: Bool
    let phase: CyclePhase

    private var dayNumber: String {
        "\(Cal.current.component(.day, from: day))"
    }

    /// 供 VoiceOver 朗读的完整描述:日期 + 是否今天 + 经期/预测 + 所处阶段。
    private var accessibilityDescription: String {
        var parts: [String] = [Cal.fullDateFormatter.string(from: day)]
        if isToday { parts.append(String(localized: "今天")) }
        if let period {
            parts.append(String(localized: "已记录经期,流量\(period.flow.label)"))
        } else if isPredicted {
            parts.append(String(localized: "预计开始区间"))
        }
        if phase != .unknown && period == nil {
            parts.append(phase.label)
        }
        return parts.joined(separator: ",")
    }

    /// 非经期日用浅色阶段背景;经期日本身用实心流量色,不叠加。
    private var showsPhaseTint: Bool {
        period == nil && !isPredicted && phase != .unknown && phase != .menstrual
    }

    var body: some View {
        ZStack {
            // 透明底层让每个格子都有可伸缩的尺寸;没有圆形的日子(只有数字)
            // 否则会退回 44pt 最小高度,比着色日矮一截。
            Color.clear
            if showsPhaseTint {
                Circle().fill(phase.cellFill)
            }
            if let period {
                Circle().fill(period.flow.tint)
            } else if isPredicted {
                // 预测经期:浅色虚线圈,与实际记录(实心)明显区分。
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .foregroundStyle(FlowLevel.light.tint)
            } else if isToday {
                Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
            Text(dayNumber)
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(period?.flow.foreground ?? (isPredicted ? FlowLevel.medium.tint : .primary))
                .fontWeight(isToday ? .bold : .regular)
        }
        // 只给 minHeight 时,着色日的实心 Circle 会撑满整列:iPad 上列宽约 130pt,
        // 这些日子变成直径 137pt 的大圆,未着色的日子却仍是 44pt,月历行高参差不齐。
        // 固定成正方形并限制边长;iPhone 的列宽本就小于上限,点按区域仍是整列。
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: MarenDesign.dayCellMaxSide)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        // 颜色是唯一的视觉编码,必须给 VoiceOver 一份等价的文字描述,
        // 否则整张日历对视障用户完全不可读。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("轻点以记录或修改这一天的经期")
    }
}

// MARK: - 标记经期的编辑面板

private struct PeriodDayEditor: View {
    let date: Date
    let existing: PeriodDay?
    let onSave: (FlowLevel) -> Void
    let onClear: () -> Void

    @State private var flow: FlowLevel

    init(date: Date, existing: PeriodDay?, onSave: @escaping (FlowLevel) -> Void, onClear: @escaping () -> Void) {
        self.date = date
        self.existing = existing
        self.onSave = onSave
        self.onClear = onClear
        _flow = State(initialValue: existing?.flow ?? .medium)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(Cal.fullDateFormatter.string(from: date))
                .font(.headline)
                .padding(.top, 8)

            Text("经期流量")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(FlowLevel.allCases) { level in
                    Button {
                        flow = level
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(level.tint)
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if flow == level {
                                        Circle().stroke(Color.primary, lineWidth: 2.5)
                                    }
                                }
                            Text(level.label).font(.caption2).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 12) {
                if existing != nil {
                    Button(role: .destructive) { onClear() } label: {
                        Text("清除").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button { onSave(flow) } label: {
                    Text(existing == nil ? "标记为经期" : "保存").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.current.accent)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding()
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: [PeriodDay.self, DailyLog.self], inMemory: true)
}
