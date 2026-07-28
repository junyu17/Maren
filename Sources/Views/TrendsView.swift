import SwiftUI
import SwiftData
import Charts

/// F7:趋势图表 + 情绪/症状×周期关联卡。全部基于本地数据,离线计算。
struct TrendsView: View {
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @ObservedObject private var store = Store.shared
    @State private var showPaywall = false

    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: ManualCycle.current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    insightsCard
                    cycleHistoryCard
                    cycleLengthCard
                    moodTrendCard
                    weightCard
                    symptomCard
                }
                .padding()
            }
            .navigationTitle("趋势")
            // 给底部留出空间,避免最后一张图表卡片被浮动标签栏遮住。
            .contentMargins(.bottom, 56, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    // MARK: - 关联洞察卡(层级 1)

    @ViewBuilder
    private var insightsCard: some View {
        // 个性化洞察是 Maren Premium 首批解锁功能。未升级时展示锁定卡,点击升级。
        if store.premium {
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
                                    .foregroundStyle(FlowLevel.medium.tint)
                                    .frame(width: 22)
                                Text(insight.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("均由你的记录在本机计算,不联网、不外传。")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            card(title: String(localized: "洞察"), systemImage: "sparkles") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("升级 Maren Premium,让 Maren 在本机发现属于你的规律:心情与周期的关联、最常出现的症状、周期稳定度等。")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        showPaywall = true
                    } label: {
                        Label("升级解锁", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FlowLevel.medium.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 历史周期列表(层级 1)

    @ViewBuilder
    private var cycleHistoryCard: some View {
        // 只展示已结束的周期(有长度的),最近的排前面。
        let completed = prediction.cycles.filter { $0.length != nil }.reversed().map { $0 }
        card(title: String(localized: "历史周期"), systemImage: "clock.arrow.circlepath") {
            if completed.isEmpty {
                Text("记满 2 个周期后,这里会列出每个周期的长度。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let lengths = completed.compactMap { $0.length }
                VStack(alignment: .leading, spacing: 10) {
                    if let lo = lengths.min(), let hi = lengths.max(), let avg = prediction.averageCycleLength {
                        Text(lo == hi
                             ? String(localized: "平均 \(Int(avg.rounded())) 天")
                             : String(localized: "平均 \(Int(avg.rounded())) 天,在 \(lo)–\(hi) 天之间波动"))
                            .font(.subheadline.weight(.medium))
                    }
                    ForEach(completed) { c in
                        HStack {
                            Text(Cal.shortDateFormatter.string(from: c.start))
                                .font(.subheadline)
                            Spacer()
                            Text(c.length.map { String(localized: "\($0) 天") } ?? "—")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(FlowLevel.medium.tint)
                        }
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 周期长度图

    @ViewBuilder
    private var cycleLengthCard: some View {
        let lengths = prediction.cycleLengths
        card(title: String(localized: "周期长度"), systemImage: "arrow.left.and.right") {
            if lengths.count >= 2 {
                // x 轴用「第几个周期」的分类值,避免连续数轴出现 0 / 小数刻度。
                Chart(Array(lengths.enumerated()), id: \.offset) { i, len in
                    BarMark(
                        x: .value(String(localized: "周期"), "\(i + 1)"),
                        y: .value(String(localized: "天数"), len)
                    )
                    .foregroundStyle(FlowLevel.medium.tint)
                    .annotation(position: .top) {
                        Text("\(len)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: 0...(max((lengths.max() ?? 30) + 6, 36)))
                .chartXAxis { AxisMarks { AxisValueLabel() } }
                .frame(height: 160)
                Text("按记录先后顺序,纵轴为天数。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                emptyHint(String(localized: "记录满 2 个周期后显示。"))
            }
        }
    }

    // MARK: - 心情趋势图(近 30 天)

    @ViewBuilder
    private var moodTrendCard: some View {
        if store.premium {
            let points = recentMoodPoints()
            card(title: String(localized: "近 30 天心情"), systemImage: "face.smiling") {
                if points.count >= 2 {
                    Chart(points, id: \.date) { p in
                        LineMark(x: .value(String(localized: "日期"), p.date), y: .value(String(localized: "心情"), p.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(FlowLevel.medium.tint)
                        PointMark(x: .value(String(localized: "日期"), p.date), y: .value(String(localized: "心情"), p.value))
                            .foregroundStyle(FlowLevel.medium.tint)
                    }
                    .chartYScale(domain: 1...5)
                    .frame(height: 150)
                } else {
                    emptyHint(String(localized: "多记几天心情后显示。"))
                }
            }
        } else {
            lockedCard(title: String(localized: "近 30 天心情"), systemImage: "face.smiling",
                       teaser: String(localized: "升级 Pro,查看近 30 天心情走势。"))
        }
    }

    private func recentMoodPoints() -> [(date: Date, value: Int)] {
        let cutoff = Cal.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return logs
            .filter { $0.date >= Cal.startOfDay(cutoff) }
            .compactMap { log in log.mood.map { (log.date, $0.rawValue) } }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - 体重趋势图(层级 2 · PCOS)

    @ViewBuilder
    private var weightCard: some View {
        if store.premium {
            let points = logs.compactMap { log in log.weight.map { (log.date, $0) } }
                .sorted { $0.0 < $1.0 }
            // 只在有人真的记过体重时才显示这张卡,避免打扰不关心体重的用户。
            if points.count >= 2 {
                card(title: String(localized: "体重趋势"), systemImage: "scalemass") {
                    Chart(points, id: \.0) { p in
                        LineMark(x: .value(String(localized: "日期"), p.0),
                                 y: .value(String(localized: "体重"), p.1))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(FlowLevel.medium.tint)
                        PointMark(x: .value(String(localized: "日期"), p.0),
                                  y: .value(String(localized: "体重"), p.1))
                            .foregroundStyle(FlowLevel.medium.tint)
                    }
                    .frame(height: 150)
                }
            }
        } else {
            lockedCard(title: String(localized: "体重趋势"), systemImage: "scalemass",
                       teaser: String(localized: "升级 Pro,查看体重曲线(PCOS 相关追踪)。"))
        }
    }

    // MARK: - 症状频次图

    @ViewBuilder
    private var symptomCard: some View {
        if store.premium {
            let freq = symptomFrequency()
            card(title: String(localized: "症状频次"), systemImage: "list.bullet") {
                if !freq.isEmpty {
                    // 留出 1 格空白,让次数标注不被裁掉;刻度按整数走,避免出现 0.5 次。
                    let maxCount = freq.map(\.value).max() ?? 1
                    Chart(freq, id: \.key) { item in
                        BarMark(
                            x: .value(String(localized: "次数"), item.value),
                            y: .value(String(localized: "症状"), Symptoms.label(for: item.key))
                        )
                        .foregroundStyle(FlowLevel.light.tint)
                        .annotation(position: .trailing) {
                            Text("\(item.value)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .chartXScale(domain: 0...(maxCount + 1))
                    .chartXAxis { AxisMarks(values: .stride(by: 1)) }
                    .frame(height: CGFloat(freq.count) * 34 + 20)
                } else {
                    emptyHint(String(localized: "还没有症状记录。"))
                }
            }
        } else {
            lockedCard(title: String(localized: "症状频次"), systemImage: "list.bullet",
                       teaser: String(localized: "升级 Pro,查看症状出现频次。"))
        }
    }

    private func symptomFrequency() -> [(key: String, value: Int)] {
        var counts: [String: Int] = [:]
        for log in logs { for s in log.symptoms { counts[s, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    // MARK: - 复用卡片容器

    @ViewBuilder
    private func card<Content: View>(title: String, systemImage: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    /// Pro 锁定卡:未升级时替代表格,提示升级并跳付费墙。
    private func lockedCard(title: String, systemImage: String, teaser: String) -> some View {
        card(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 10) {
                Text(teaser)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showPaywall = true
                } label: {
                    Label("升级解锁", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(FlowLevel.medium.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
