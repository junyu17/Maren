import SwiftUI
import Charts

/// 用户可浏览的只读样本数据体验。所有数据来自 SampleData 内存结构,不触碰 SwiftData。
/// 从「设置」或「引导」进入,退出后不留任何痕迹。
/// 所有辅助结构体(SPeriodDay, SDailyLog 等)都是 struct(值类型),不入 SwiftData。
/// PeriodDay 作为 CyclePredictor 入参时仅在内存中临时构造,从不 insert 到 modelContext。
struct SampleExperienceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Store.shared

    @State private var visibleMonth: Date = Cal.startOfDay(Date())

    private var prediction: CyclePredictor.Prediction { SampleData.prediction }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    banner
                    calendarCard
                    predictionCard
                    insightsCard
                    moodTrendCard
                    weightCard
                    bodySignalsCard
                    medicationCard
                }
                .padding()
            }
            .navigationTitle(String(localized: "样本体验"))
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 56, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "退出")) { dismiss() }
                        .accessibilityLabel(String(localized: "退出样本体验"))
                }
            }
        }
    }

    // MARK: - 顶部横幅

    private var banner: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.largeTitle)
                .foregroundStyle(FlowLevel.medium.tint)
                .accessibilityHidden(true)
            Text(String(localized: "以下是示例数据,帮助你了解 Maren 的功能。"))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(String(localized: "所有数据均为模拟,不会影响你的真实记录。"))
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(FlowLevel.spotting.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 日历概览(最近一个月)

    private var calendarCard: some View {
        let grid = Cal.monthGrid(for: visibleMonth)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let periodSet = Set(SampleData.periodDays.map { Cal.startOfDay($0.date) })

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(String(localized: "日历概览"), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation { visibleMonth = Cal.addMonths(-1, to: visibleMonth) }
                } label: {
                    Image(systemName: "chevron.left").font(.caption)
                }
                .accessibilityLabel(String(localized: "上一个月"))
                Text(Cal.monthTitleFormatter.string(from: visibleMonth))
                    .font(.subheadline).frame(minWidth: 100)
                Button {
                    withAnimation { visibleMonth = Cal.addMonths(1, to: visibleMonth) }
                } label: {
                    Image(systemName: "chevron.right").font(.caption)
                }
                .accessibilityLabel(String(localized: "下一个月"))
            }

            HStack {
                ForEach(Array(Cal.orderedWeekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<grid.leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }
                ForEach(grid.days, id: \.self) { day in
                    let isPeriod = periodSet.contains(Cal.startOfDay(day))
                    let dayNum = "\(Cal.current.component(.day, from: day))"
                    ZStack {
                        if isPeriod {
                            Circle().fill(FlowLevel.medium.tint)
                        }
                        Text(dayNum)
                            .font(.caption)
                            .foregroundStyle(isPeriod ? .white : .primary)
                    }
                    .frame(height: 36)
                    .accessibilityLabel(isPeriod
                        ? String(localized: "\(dayNum)日,经期")
                        : String(localized: "\(dayNum)日"))
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(FlowLevel.medium.tint).frame(width: 8, height: 8)
                    Text(String(localized: "经期")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 预测卡片

    private var predictionCard: some View {
        let p = prediction
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").foregroundStyle(FlowLevel.medium.tint)
                    .accessibilityHidden(true)
                Text(String(localized: "周期预测")).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(localized: "把握度 \(p.confidence.label)"))
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }

            if let avg = p.averageCycleLength {
                Text(String(localized: "平均 \(Int(avg.rounded())) 天,已观测 \(p.observedCycleCount) 个周期"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let pLen = p.averagePeriodLength {
                Text(String(localized: "平均经期 \(String(format: "%.1f", pLen)) 天"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Text(String(localized: "以上均为示例数据的统计结果,仅供参考。"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlowLevel.spotting.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 洞察卡(使用示例数据的 InsightEngine)

    private var insightsCard: some View {
        let insights = InsightEngine.generate(
            periodDays: SampleData.virtualPeriodDays,
            logs: [], // 样本 DailyLog 是 struct,不是 SwiftData 对象,这里用空;洞察仍可展示周期统计部分
            prediction: prediction)

        return card(title: String(localized: "洞察"), systemImage: "sparkles") {
            if insights.isEmpty {
                // 样本数据的 insight 可能因为 logs 类型不匹配而为空,手动展示几条示例
                VStack(alignment: .leading, spacing: 10) {
                    SampleInsightRow(icon: "waveform.path.ecg",
                                     text: String(localized: "你的周期很规律,稳定在 30 天左右。"))
                    SampleInsightRow(icon: "face.smiling",
                                     text: String(localized: "你的心情在经期通常偏低,在排卵期相对更好。"))
                    SampleInsightRow(icon: "bolt",
                                     text: String(localized: "你的能量在黄体期通常较低。"))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: insight.icon)
                                .font(.subheadline)
                                .foregroundStyle(FlowLevel.medium.tint)
                                .frame(width: 22)
                            Text(insight.text).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text(String(localized: "以上均为示例数据的洞察,仅供参考,不构成医学建议。"))
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 心情趋势(模拟近 30 天)

    private var moodTrendCard: some View {
        let cutoff = Cal.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let points = SampleData.dailyLogs
            .filter { $0.date >= Cal.startOfDay(cutoff) && $0.mood != nil }
            .compactMap { log -> (date: Date, value: Int)? in
                guard let m = log.mood else { return nil }
                return (log.date, m.rawValue)
            }
            .sorted { $0.date < $1.date }

        return card(title: String(localized: "近 30 天心情"), systemImage: "face.smiling") {
            if points.count >= 2 {
                Chart(points, id: \.date) { p in
                    LineMark(x: .value(String(localized: "日期"), p.date),
                             y: .value(String(localized: "心情"), p.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(FlowLevel.medium.tint)
                    PointMark(x: .value(String(localized: "日期"), p.date),
                              y: .value(String(localized: "心情"), p.value))
                        .foregroundStyle(FlowLevel.medium.tint)
                }
                .chartYScale(domain: 1...5)
                .frame(height: 150)
            } else {
                Text(String(localized: "示例数据不足。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 体重趋势

    private var weightCard: some View {
        let points = SampleData.dailyLogs
            .compactMap { log -> (date: Date, value: Double)? in
                log.weight.map { (log.date, $0) }
            }
            .sorted { $0.date < $1.date }

        return card(title: String(localized: "体重趋势"), systemImage: "scalemass") {
            if points.count >= 2 {
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
            } else {
                Text(String(localized: "示例数据不足。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 基础体温与点滴出血

    private var bodySignalsCard: some View {
        let points = SampleData.dailyLogs
            .compactMap { log -> (date: Date, value: Double)? in
                log.basalBodyTemperatureCelsius.map { (log.date, $0) }
            }
            .sorted { $0.date < $1.date }
        let spottingRecordedDays = SampleData.dailyLogs.filter { $0.spotting != nil }.count
        let spottingDays = SampleData.dailyLogs.filter { $0.spotting == true }.count

        return card(title: String(localized: "身体信号"), systemImage: "thermometer.medium") {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "基础体温趋势"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if points.count >= 2 {
                    Chart(points, id: \.date) { point in
                        LineMark(
                            x: .value(String(localized: "日期"), point.date),
                            y: .value(String(localized: "基础体温"), point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(FlowLevel.medium.tint)
                        PointMark(
                            x: .value(String(localized: "日期"), point.date),
                            y: .value(String(localized: "基础体温"), point.value)
                        )
                        .foregroundStyle(FlowLevel.medium.tint)
                    }
                    .chartYScale(domain: 36.0...37.0)
                    .frame(height: 150)
                } else {
                    Text(String(localized: "示例数据不足。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label(String(localized: "点滴出血"), systemImage: "drop.fill")
                    Spacer()
                    Text(String(localized: "\(spottingDays) 天有记录 / \(spottingRecordedDays) 天已记录"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "示例数据仅用于展示记录方式,不代表健康结论。"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 用药打卡

    private var medicationCard: some View {
        card(title: String(localized: "用药打卡"), systemImage: "pills") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(SampleData.medications, id: \.name) { med in
                    let count = SampleData.intakes.filter { $0.medicationName == med.name }.count
                    HStack {
                        Text(med.emoji)
                        Text(med.name).font(.subheadline)
                        Spacer()
                        Text(String(localized: "\(count) / 14 天"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(String(localized: "近 14 天的用药打卡记录。"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 复用容器

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
}

// MARK: - 洞察行

private struct SampleInsightRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(FlowLevel.medium.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    SampleExperienceView()
}
