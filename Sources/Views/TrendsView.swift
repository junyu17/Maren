import SwiftUI
import SwiftData
import Charts

/// F7:趋势图表 + 情绪/症状×周期关联卡。全部基于本地数据,离线计算。
struct TrendsView: View {
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @ObservedObject private var store = Store.shared
    @ObservedObject private var dataChangeCenter = LocalDataChangeCenter.shared
    @State private var showPaywall = false
    @AppStorage(LifeStage.userDefaultsKey) private var lifeStageRaw = LifeStage.defaultValue.rawValue
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength

    private var manualCycle: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }

    private var trackerRevision: UInt64 {
        dataChangeCenter.lastEvent?.revision ?? 0
    }

    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: manualCycle)
    }

    var body: some View {
        let _ = trackerRevision
        NavigationStack {
            ScrollView {
                VStack(spacing: MarenDesign.spacingL) {
                    overviewMetrics
                    ReviewSectionView()
                    perimenopauseCard
                    cycleRhythmSection
                    if store.premium {
                        insightsCard
                        moodTrendCard
                        weightCard
                        symptomCard
                        cycleComparisonCard
                        correlationCard
                    } else {
                        premiumPreviewCard
                    }
                }
                .padding()
            }
            .navigationTitle("趋势")
            // 给底部留出空间,避免最后一张图表卡片被浮动标签栏遮住。
            .contentMargins(.bottom, 56, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LocalSearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("全局搜索"))
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    // MARK: - Overview Metrics

    private var overviewMetrics: some View {
        HStack(spacing: MarenDesign.spacingS) {
            metricPill(
                icon: "clock.arrow.circlepath",
                value: Text(prediction.averageCycleLength.map { String(localized: "\(Int($0.rounded())) 天") } ?? "—"),
                label: String(localized: "平均周期")
            )
            metricPill(
                icon: "calendar",
                value: Text(prediction.observedCycleCount > 0 ? String(localized: "\(prediction.observedCycleCount) 个周期") : "—"),
                label: String(localized: "已记录")
            )
            metricPill(
                icon: "waveform.path.ecg",
                value: Text(prediction.regularity),
                label: String(localized: "规律度")
            )
        }
        .padding(MarenDesign.spacingM)
        .frame(maxWidth: .infinity)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func metricPill(icon: String, value: some View, label: String) -> some View {
        VStack(spacing: MarenDesign.spacingXS) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.current.accent)
            value
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cycle Rhythm Section

    private var cycleRhythmSection: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingM) {
            Label(String(localized: "周期节律"), systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
            cycleHistoryCompact
            cycleLengthChart
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private var cycleHistoryCompact: some View {
        let completed = prediction.cycles.filter { $0.length != nil }.reversed().map { $0 }
        return Group {
            if completed.isEmpty {
                emptyHint(String(localized: "记满 2 个周期后,这里会展示每个周期的长度。"))
            } else {
                VStack(alignment: .leading, spacing: MarenDesign.spacingXS) {
                    ForEach(completed) { c in
                        HStack {
                            Text(Cal.shortDateFormatter.string(from: c.start))
                                .font(.caption)
                            Spacer()
                            Text(c.length.map { String(localized: "\($0) 天") } ?? "—")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.current.accent)
                        }
                        .accessibilityElement(children: .combine)
                        if c.id != completed.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var cycleLengthChart: some View {
        let lengths = prediction.cycleLengths
        return Group {
            if lengths.count >= 2 {
                Chart(Array(lengths.enumerated()), id: \.offset) { i, len in
                    AreaMark(
                        x: .value(String(localized: "周期"), "\(i + 1)"),
                        yStart: .value(String(localized: "基线"), 0),
                        yEnd: .value(String(localized: "天数"), len)
                    )
                    .foregroundStyle(AppTheme.current.accent.opacity(0.10))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value(String(localized: "周期"), "\(i + 1)"),
                        y: .value(String(localized: "天数"), len)
                    )
                    .foregroundStyle(AppTheme.current.accent)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value(String(localized: "周期"), "\(i + 1)"),
                        y: .value(String(localized: "天数"), len)
                    )
                    .foregroundStyle(AppTheme.current.accent)
                    .symbolSize(40)
                }
                .chartYScale(domain: 0...(max((lengths.max() ?? 30) + 6, 36)))
                .chartXAxis { AxisMarks { AxisValueLabel() } }
                .frame(height: 160)
                Text(String(localized: "按记录先后顺序,纵轴为天数。"))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                emptyHint(String(localized: "记录满 2 个周期后显示周期长度趋势。"))
            }
        }
    }

    // MARK: - Perimenopause record summary

    @ViewBuilder
    private var perimenopauseCard: some View {
        if LifeStage(rawValue: lifeStageRaw) == .perimenopause {
            NavigationLink {
                PerimenopauseDashboardView(report: perimenopauseReport)
            } label: {
                card(title: String(localized: "Perimenopause record summary"),
                     systemImage: "chart.line.uptrend.xyaxis") {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "View neutral 30- and 90-day facts from your entries."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(String(localized: "Counts, coverage, cycle ranges, and available averages."))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Open perimenopause record summary"))
        }
    }

    private var perimenopauseReport: PerimenopauseTrendEngine.Report {
        let calendar = Cal.current
        let dailyRecords = logs.map { log in
            PerimenopauseTrendEngine.DailyRecord(
                dayKey: log.dayKey,
                symptomKeys: Set(log.symptoms),
                mood: Mood(rawValue: log.moodRaw).map { Double($0.rawValue) },
                sleepHours: log.sleepHours
            )
        }

        return PerimenopauseTrendEngine.evaluate(
            PerimenopauseTrendEngine.Input(
                dailyRecords: dailyRecords,
                periodStartDayKeys: perimenopausePeriodStartDayKeys,
                asOf: Date(),
                calendar: calendar
            )
        )
    }

    /// Reduces bleeding-day records to the first day of each contiguous run.
    /// A run is based only on adjacent local calendar days, so a multi-day
    /// period is not mistaken for several cycle starts.
    private var perimenopausePeriodStartDayKeys: [Int] {
        let calendar = Cal.current
        let uniqueDays = Array(Set(periodDays.map(\.dayKey))).sorted()
        var starts: [Int] = []
        var previousDate: Date?

        for dayKey in uniqueDays {
            let date = DayKey.date(from: dayKey)
            let isContiguous = previousDate.map {
                calendar.dateComponents([.day], from: $0, to: date).day == 1
            } ?? false
            if !isContiguous {
                starts.append(dayKey)
            }
            previousDate = date
        }

        return starts
    }

    // MARK: - Premium Insights

    @ViewBuilder
    private var insightsCard: some View {
        let insights = InsightEngine.generate(periodDays: periodDays, logs: logs, prediction: prediction)
        card(title: String(localized: "洞察"), systemImage: "sparkles") {
            if insights.isEmpty {
                Text("多记几天,这里会出现属于你的洞察。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: insight.icon)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.current.accent)
                                .frame(width: 22)
                            Text(insight.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("均由你的记录在本机计算,不联网、不外传。")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("以上统计与洞察仅供参考,不构成医学建议。")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Mood Trend (Premium)

    @ViewBuilder
    private var moodTrendCard: some View {
        let points = recentMoodPoints()
        card(title: String(localized: "近 30 天心情"), systemImage: "face.smiling") {
            if points.count >= 2 {
                Chart(points, id: \.date) { p in
                    LineMark(x: .value(String(localized: "日期"), p.date), y: .value(String(localized: "心情"), p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppTheme.current.accent)
                    PointMark(x: .value(String(localized: "日期"), p.date), y: .value(String(localized: "心情"), p.value))
                        .foregroundStyle(AppTheme.current.accent)
                }
                .chartYScale(domain: 1...5)
                .frame(height: 150)
            } else {
                emptyHint(String(localized: "多记几天心情后显示。"))
            }
        }
    }

    private func recentMoodPoints() -> [(date: Date, value: Int)] {
        let cutoff = Cal.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return logs
            .filter { $0.date >= Cal.startOfDay(cutoff) }
            .compactMap { log in log.mood.map { (log.date, $0.rawValue) } }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - Weight Trend (Premium · PCOS)

    @ViewBuilder
    private var weightCard: some View {
        let points = logs.compactMap { log in log.weight.map { (log.date, $0) } }
            .sorted { $0.0 < $1.0 }
        // 只在有人真的记过体重时才显示这张卡,避免打扰不关心体重的用户。
        if points.count >= 2 {
            card(title: String(localized: "体重趋势"), systemImage: "scalemass") {
                Chart(points, id: \.0) { p in
                    LineMark(x: .value(String(localized: "日期"), p.0),
                             y: .value(String(localized: "体重"), p.1))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppTheme.current.accent)
                    PointMark(x: .value(String(localized: "日期"), p.0),
                              y: .value(String(localized: "体重"), p.1))
                        .foregroundStyle(AppTheme.current.accent)
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Tracker Frequency (Premium)

    @ViewBuilder
    private var symptomCard: some View {
        let freq = symptomFrequency()
        card(title: String(localized: "追踪项频次"), systemImage: "list.bullet") {
            if !freq.isEmpty {
                // 留出 1 格空白,让次数标注不被裁掉;刻度按整数走,避免出现 0.5 次。
                let maxCount = freq.map(\.value).max() ?? 1
                Chart(freq, id: \.key) { item in
                    BarMark(
                        x: .value(String(localized: "次数"), item.value),
                        y: .value(String(localized: "追踪项"), Symptoms.label(for: item.key))
                    )
                    .foregroundStyle(AppTheme.current.accent)
                    .annotation(position: .trailing) {
                        Text("\(item.value)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: 0...(maxCount + 1))
                .chartXAxis { AxisMarks(values: .stride(by: 1)) }
                .frame(height: CGFloat(freq.count) * 34 + 20)
            } else {
                emptyHint(String(localized: "还没有追踪项记录。"))
            }
        }
    }

    private func symptomFrequency() -> [(key: String, value: Int)] {
        var counts: [String: Int] = [:]
        for log in logs { for s in log.symptoms { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    // MARK: - Cycle Comparison (Premium)

    @ViewBuilder
    private var cycleComparisonCard: some View {
        CycleComparisonCard(logs: logs, prediction: prediction)
    }

    // MARK: - Correlation Explorer (Premium)

    @ViewBuilder
    private var correlationCard: some View {
        CorrelationExplorerCard(logs: logs)
    }

    // MARK: - Consolidated Premium Preview (Free)

    @ViewBuilder
    private var premiumPreviewCard: some View {
        card(title: String(localized: "Maren Premium"), systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: MarenDesign.spacingM) {
                Text(String(localized: "升级后解锁更多洞察与趋势分析,全部在本机完成、不联网。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
                    previewRow(icon: "sparkles", text: String(localized: "个性化洞察 — 心情×阶段关联、规律度分析"))
                    previewRow(icon: "face.smiling", text: String(localized: "近 30 天心情走势"))
                    previewRow(icon: "list.bullet", text: String(localized: "追踪项频次统计"))
                    previewRow(icon: "arrow.triangle.2.circlepath", text: String(localized: "最近完成周期变化对比"))
                    previewRow(icon: "point.3.connected.trianglepath.dotted", text: String(localized: "相关性探索 — 睡眠、心情、周期阶段关联"))
                }

                Button {
                    showPaywall = true
                } label: {
                    Label(String(localized: "升级解锁"), systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.current.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func previewRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: MarenDesign.spacingS) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.current.accent)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Card Container

    @ViewBuilder
    private func card<Content: View>(title: String, systemImage: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingM) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(MarenDesign.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}
