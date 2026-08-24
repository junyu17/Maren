import SwiftUI
import SwiftData

// MARK: - 统一 回顾 Section (for TrendsView)

/// Unified review section shown in TrendsView after overview metrics.
/// Contains compact weekly + completed-cycle cards with live @Query.
struct ReviewSectionView: View {
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @ObservedObject private var store = Store.shared

    private var isPremium: Bool { store.premium }

    var body: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingM) {
            Label(String(localized: "回顾"), systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))

            // Weekly review compact card
            NavigationLink {
                WeeklyReviewDetailView(anchorDayKey: DayKey.today)
            } label: {
                weeklyCompactCard
            }
            .buttonStyle(.plain)

            // Completed cycle compact card
            if let cycle = latestCompletedCycle {
                NavigationLink {
                    CompletedCycleDetailView(cycleStartDayKey: cycle.startDayKey)
                } label: {
                    completedCycleCompactCard(cycle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(MarenDesign.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private var weeklyReview: MarenReviewEngine.WeeklyReviewResult {
        MarenReviewEngine.weeklyReview(
            anchorDayKey: DayKey.today,
            periodDays: periodDays,
            logs: logs)
    }

    private var latestCompletedCycle: MarenReviewEngine.CompletedCycleResult? {
        MarenReviewEngine.completedCycleSummary(
            periodDays: periodDays,
            logs: logs)
    }

    private var reviewDisclaimer: String {
        String(localized: "回顾数据基于你本机记录,为统计趋势洞察,不构成医学建议。")
    }

    private var weeklyCompactCard: some View {
        let review = weeklyReview
        return VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            HStack {
                Label(String(localized: "本周回顾"), systemImage: "calendar.badge.clock")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            // Date range
            Text("\(DayKey.date(from: review.currentWindow.startDayKey), style: .date) — \(DayKey.date(from: review.currentWindow.endDayKey), style: .date)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Recorded-day coverage (free + premium)
            Text(String(format: String(localized: "已记录 %lld 天"), review.currentWindow.recordedDayKeys.count))
                .font(.footnote).foregroundStyle(.secondary)
            if review.periodDayCount > 0 {
                Text(String(format: String(localized: "经期 %lld 天"), review.periodDayCount))
                    .font(.footnote).foregroundStyle(.secondary)
            }

            // Premium-only detailed metrics
            if isPremium {
                switch review.reviewStatus {
                case .empty:
                    Text(String(localized: "本周暂无记录。"))
                        .font(.footnote).foregroundStyle(.secondary)
                case .limited:
                    limitedWeeklyContent()
                case .ready:
                    readyWeeklyContent(review)
                }
            }

            Text(reviewDisclaimer)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func limitedWeeklyContent() -> some View {
        Text(String(localized: "继续记录几天,即可查看详细趋势。"))
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func readyWeeklyContent(_ review: MarenReviewEngine.WeeklyReviewResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: MarenDesign.spacingM) {
                if let mood = review.averages.mood {
                    metricSummary(label: String(localized: "心情"), value: String(format: "%.1f", mood))
                }
                if let energy = review.averages.energy {
                    metricSummary(label: String(localized: "能量"), value: String(format: "%.1f", energy))
                }
                if let sleep = review.averages.sleep {
                    metricSummary(label: String(localized: "睡眠"), value: String(format: "%.1fh", sleep))
                }
            }
            if let comp = review.comparison {
                comparisonSummary(comp)
            }
            if !review.topTrackers.isEmpty {
                trackerSummary(review.topTrackers)
            }
        }
    }

    private func metricSummary(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func comparisonSummary(_ comp: MarenReviewEngine.ReviewComparison) -> some View {
        HStack(spacing: MarenDesign.spacingS) {
            if let mood = comp.moodDelta {
                comparisonPill(label: String(localized: "心情"), delta: mood, similar: comp.moodSimilar, unit: "")
            }
            if let energy = comp.energyDelta {
                comparisonPill(label: String(localized: "能量"), delta: energy, similar: comp.energySimilar, unit: "")
            }
            if let sleep = comp.sleepDelta {
                comparisonPill(label: String(localized: "睡眠"), delta: sleep, similar: comp.sleepSimilar, unit: "h")
            }
        }
    }

    private func comparisonPill(label: String, delta: Double, similar: Bool, unit: String) -> some View {
        let sign = delta >= 0 ? "+" : ""
        let text = "\(sign)\(String(format: "%.1f", delta))\(unit)"
        return VStack(spacing: 2) {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(similar ? Color.secondary : (delta > 0 ? Color.orange : Color.blue))
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func trackerSummary(_ trackers: [MarenReviewEngine.TrackerRanking]) -> some View {
        HStack(spacing: MarenDesign.spacingXS) {
            ForEach(trackers.prefix(3)) { t in
                Text(Symptoms.label(for: t.key))
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(AppTheme.current.accent.opacity(0.12), in: Capsule())
            }
            if trackers.count > 3 {
                Text("+\(trackers.count - 3)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func completedCycleCompactCard(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            HStack {
                Label(String(localized: "最近完成周期"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            // Cycle boundary
            HStack {
                Text("\(DayKey.date(from: cycle.startDayKey), style: .date)")
                    .font(.caption)
                Text("→")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(DayKey.date(from: cycle.endDayKey), style: .date)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            // Cycle length + period-day count (free + premium)
            Text(String(format: String(localized: "%lld 天 · 经期 %lld 天"), cycle.cycleLength, cycle.periodDays))
                .font(.footnote).foregroundStyle(.secondary)

            // Premium-only detailed metrics
            if isPremium, let mood = cycle.averages.mood {
                HStack(spacing: MarenDesign.spacingM) {
                    metricSummary(label: String(localized: "心情"), value: String(format: "%.1f", mood))
                    if let energy = cycle.averages.energy {
                        metricSummary(label: String(localized: "能量"), value: String(format: "%.1f", energy))
                    }
                    if let sleep = cycle.averages.sleep {
                        metricSummary(label: String(localized: "睡眠"), value: String(format: "%.1fh", sleep))
                    }
                }
            }

            // Neutral possible-recording-gap warning (free + premium)
            if cycle.gapOver120 {
                Text(String(localized: "此周期超过 120 天,可能存在记录间隔。"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(reviewDisclaimer)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Weekly Review Detail

struct WeeklyReviewDetailView: View {
    let anchorDayKey: Int

    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @ObservedObject private var store = Store.shared
    @State private var showPaywall = false

    private var review: MarenReviewEngine.WeeklyReviewResult {
        MarenReviewEngine.weeklyReview(
            anchorDayKey: anchorDayKey,
            periodDays: periodDays,
            logs: logs)
    }

    private var accessPolicy: MarenReviewEngine.AccessPolicy {
        MarenReviewEngine.accessPolicy(isPremium: store.premium)
    }

    private var reviewDisclaimer: String {
        String(localized: "回顾数据基于你本机记录,为统计趋势洞察,不构成医学建议。")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MarenDesign.spacingL) {
                // Header
                VStack(spacing: MarenDesign.spacingS) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.largeTitle)
                        .foregroundStyle(AppTheme.current.accent)
                    Text(String(localized: "本周回顾"))
                        .font(.title3.weight(.semibold))
                    Text("\(DayKey.date(from: review.currentWindow.startDayKey), style: .date) — \(DayKey.date(from: review.currentWindow.endDayKey), style: .date)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()

                // Coverage
                coverageCard

                // Period day count
                if accessPolicy.contains(.periodDayCount) {
                    periodDayCard
                }

                // Averages (premium) or locked preview CTA for every free state
                if accessPolicy.contains(.averages) {
                    averagesCard
                } else {
                    lockedPreviewCard
                }

                // Comparison
                if accessPolicy.contains(.comparisons), let comp = review.comparison {
                    comparisonCard(comp)
                }

                // Top trackers
                if accessPolicy.contains(.topTrackers), !review.topTrackers.isEmpty {
                    trackersCard
                }

                // Disclaimer
                Text(reviewDisclaimer)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding()
            }
            .padding()
        }
        .navigationTitle(String(localized: "本周回顾"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var coverageCard: some View {
        let totalDays = Cal.current.dateComponents([.day],
            from: DayKey.date(from: review.currentWindow.startDayKey),
            to: DayKey.date(from: review.currentWindow.endDayKey)).day ?? 6
        return VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "记录覆盖"), systemImage: "chart.pie")
                .font(.subheadline.weight(.medium))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: String(localized: "%lld / %lld 天"), review.currentWindow.recordedDayKeys.count, totalDays + 1))
                        .font(.headline)
                    Text(String(localized: "有记录的天数"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if review.periodDayCount > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(review.periodDayCount)")
                            .font(.headline)
                        Text(String(localized: "经期天数"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private var periodDayCard: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "经期记录"), systemImage: "drop.fill")
                .font(.subheadline.weight(.medium))
            Text(String(format: String(localized: "本周共 %lld 天经期记录。"), review.periodDayCount))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private var averagesCard: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "本周均值"), systemImage: "chart.bar")
                .font(.subheadline.weight(.medium))

            if review.reviewStatus == .empty {
                Text(String(localized: "暂无足够记录计算均值。"))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: MarenDesign.spacingS) {
                    if let mood = review.averages.mood {
                        averageRow(label: String(localized: "心情"), value: String(format: "%.1f / 5", mood))
                    } else {
                        missingMetricRow(label: String(localized: "心情"), reason: String(localized: "不足 3 天记录"))
                    }
                    if let energy = review.averages.energy {
                        averageRow(label: String(localized: "能量"), value: String(format: "%.1f / 5", energy))
                    } else {
                        missingMetricRow(label: String(localized: "能量"), reason: String(localized: "不足 3 天记录"))
                    }
                    if let sleep = review.averages.sleep {
                        averageRow(label: String(localized: "睡眠"), value: String(format: "%.1f 小时", sleep))
                    } else {
                        missingMetricRow(label: String(localized: "睡眠"), reason: String(localized: "不足 3 天记录"))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func averageRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    private func missingMetricRow(label: String, reason: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(reason).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var lockedPreviewCard: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.current.accent)
                Text(String(localized: "升级查看本周详细均值与对比"))
                    .font(.subheadline.weight(.medium))
            }
            Button { showPaywall = true } label: {
                Label(String(localized: "升级解锁"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.current.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func comparisonCard(_ comp: MarenReviewEngine.ReviewComparison) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "与上一周对比"), systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))

            if let mood = comp.moodDelta {
                comparisonRow(label: String(localized: "心情"), delta: mood, similar: comp.moodSimilar, unit: "")
            }
            if let energy = comp.energyDelta {
                comparisonRow(label: String(localized: "能量"), delta: energy, similar: comp.energySimilar, unit: "")
            }
            if let sleep = comp.sleepDelta {
                comparisonRow(label: String(localized: "睡眠"), delta: sleep, similar: comp.sleepSimilar, unit: "h")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func comparisonRow(label: String, delta: Double, similar: Bool, unit: String) -> some View {
        let sign = delta >= 0 ? "+" : ""
        let text = similar
            ? String(localized: "基本一致")
            : "\(sign)\(String(format: "%.1f", delta))\(unit)"
        return HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(similar ? Color.secondary : (delta > 0 ? Color.orange : Color.blue))
        }
    }

    private var trackersCard: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "最常记录的追踪项"), systemImage: "list.bullet")
                .font(.subheadline.weight(.medium))
            ForEach(review.topTrackers) { tracker in
                HStack {
                    Text(Symptoms.label(for: tracker.key))
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: String(localized: "%lld 天"), tracker.dayCount))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }
}

// MARK: - Completed Cycle Detail

struct CompletedCycleDetailView: View {
    let cycleStartDayKey: Int

    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]

    @ObservedObject private var store = Store.shared
    @State private var showPaywall = false

    private var cycle: MarenReviewEngine.CompletedCycleResult? {
        MarenReviewEngine.completedCycleSummary(
            periodDays: periodDays,
            logs: logs,
            cycleStartDayKey: cycleStartDayKey)
    }

    private var accessPolicy: MarenReviewEngine.AccessPolicy {
        MarenReviewEngine.accessPolicy(isPremium: store.premium)
    }

    private var reviewDisclaimer: String {
        String(localized: "回顾数据基于你本机记录,为统计趋势洞察,不构成医学建议。")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: MarenDesign.spacingL) {
                if let cycle = cycle {
                    // Header
                    VStack(spacing: MarenDesign.spacingS) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.largeTitle)
                            .foregroundStyle(AppTheme.current.accent)
                        Text(String(localized: "完成周期回顾"))
                            .font(.title3.weight(.semibold))
                        HStack {
                            Text("\(DayKey.date(from: cycle.startDayKey), style: .date)")
                            Text("→")
                                .foregroundStyle(.secondary)
                            Text("\(DayKey.date(from: cycle.endDayKey), style: .date)")
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding()

                    // Cycle facts
                    cycleFactsCard(cycle)

                    // Coverage
                    coverageCard(cycle)

                    // Averages (premium) or locked preview CTA for every free state
                    if accessPolicy.contains(.averages) {
                        averagesCard(cycle)
                    } else {
                        lockedPreviewCard
                    }

                    // Top trackers
                    if accessPolicy.contains(.topTrackers), !cycle.topTrackers.isEmpty {
                        trackersCard(cycle)
                    }

                    if cycle.gapOver120 {
                        gapWarningCard
                    }

                    // Historical cycle comparison (premium only, suppressed on gap)
                    if accessPolicy.contains(.cycleHistory), !cycle.gapOver120 {
                        cycleHistoryCard(cycle)
                    }

                    Text(reviewDisclaimer)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding()
                } else {
                    Text(String(localized: "没有找到完成的周期。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle(String(localized: "完成周期回顾"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func cycleFactsCard(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "周期概况"), systemImage: "info.circle")
                .font(.subheadline.weight(.medium))
            HStack(spacing: MarenDesign.spacingL) {
                factRow(label: String(localized: "周期长度"), value: String(format: String(localized: "%lld 天"), cycle.cycleLength))
                factRow(label: String(localized: "经期天数"), value: String(format: String(localized: "%lld 天"), cycle.periodDays))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func factRow(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func coverageCard(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "记录覆盖"), systemImage: "chart.pie")
                .font(.subheadline.weight(.medium))
            Text(String(format: String(localized: "周期内有 %lld 天记录(共 %lld 天)。"), cycle.recordedLogDays, cycle.cycleLength))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func cycleHistoryCard(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        let all = MarenReviewEngine.allCompletedCycles(periodDays: periodDays, logs: logs)
        let previous = all.last { $0.startDayKey < cycle.startDayKey }
        return VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "与上一周期对比"), systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.medium))
            if let prev = previous {
                HStack(spacing: MarenDesign.spacingL) {
                    factRow(label: String(localized: "上一周期长度"), value: String(format: String(localized: "%lld 天"), prev.cycleLength))
                    factRow(label: String(localized: "上一经期天数"), value: String(format: String(localized: "%lld 天"), prev.periodDays))
                }
                if prev.cycleLength != cycle.cycleLength {
                    let delta = cycle.cycleLength - prev.cycleLength
                    let sign = delta > 0 ? "+" : ""
                    Text(String(format: String(localized: "周期长度变化 %@%lld 天"), sign, delta))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "暂无更早的完成周期可供对比。"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func averagesCard(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "周期均值"), systemImage: "chart.bar")
                .font(.subheadline.weight(.medium))

            if cycle.reviewStatus == .empty {
                Text(String(localized: "暂无足够记录计算均值。"))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: MarenDesign.spacingS) {
                    if let mood = cycle.averages.mood {
                        averageRow(label: String(localized: "心情"), value: String(format: "%.1f / 5", mood))
                    } else {
                        missingMetricRow(label: String(localized: "心情"), reason: String(localized: "不足 3 天记录"))
                    }
                    if let energy = cycle.averages.energy {
                        averageRow(label: String(localized: "能量"), value: String(format: "%.1f / 5", energy))
                    } else {
                        missingMetricRow(label: String(localized: "能量"), reason: String(localized: "不足 3 天记录"))
                    }
                    if let sleep = cycle.averages.sleep {
                        averageRow(label: String(localized: "睡眠"), value: String(format: "%.1f 小时", sleep))
                    } else {
                        missingMetricRow(label: String(localized: "睡眠"), reason: String(localized: "不足 3 天记录"))
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func averageRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    private func missingMetricRow(label: String, reason: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(reason).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var lockedPreviewCard: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.current.accent)
                Text(String(localized: "升级查看周期详细均值与追踪项"))
                    .font(.subheadline.weight(.medium))
            }
            Button { showPaywall = true } label: {
                Label(String(localized: "升级解锁"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.current.accent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private func trackersCard(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "最常记录的追踪项"), systemImage: "list.bullet")
                .font(.subheadline.weight(.medium))
            ForEach(cycle.topTrackers) { tracker in
                HStack {
                    Text(Symptoms.label(for: tracker.key))
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: String(localized: "%lld 天"), tracker.dayCount))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }

    private var gapWarningCard: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
            Label(String(localized: "可能的记录间隔"), systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))
            Text(String(localized: "此周期超过 120 天,中间可能存在未记录的间隔。数据仅供参考。"))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusM))
    }
}

// MARK: - Compact Review Entry (for DailyLogView)

/// Compact one-line review entry for the Today tab.
/// Shows either a completed-cycle update or weekly summary.
struct CompactReviewEntry: View {
    let periodDays: [PeriodDay]
    let logs: [DailyLog]

    @ObservedObject private var store = Store.shared

    private var isPremium: Bool { store.premium }

    private var latestCompletedCycle: MarenReviewEngine.CompletedCycleResult? {
        MarenReviewEngine.completedCycleSummary(
            periodDays: periodDays,
            logs: logs)
    }

    private var weeklyReview: MarenReviewEngine.WeeklyReviewResult {
        MarenReviewEngine.weeklyReview(
            anchorDayKey: DayKey.today,
            periodDays: periodDays,
            logs: logs)
    }

    var body: some View {
        if let cycle = latestCompletedCycle, wasUpdatedRecently(cycle) {
            NavigationLink {
                CompletedCycleDetailView(cycleStartDayKey: cycle.startDayKey)
            } label: {
                completedCycleLine(cycle)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                WeeklyReviewDetailView(anchorDayKey: DayKey.today)
            } label: {
                weeklyLine
            }
            .buttonStyle(.plain)
        }
    }

    private func wasUpdatedRecently(_ cycle: MarenReviewEngine.CompletedCycleResult) -> Bool {
        // "Updated recently" = the next period start (endDayKey, exclusive boundary)
        // began within the last 7 calendar days.
        let endExclusive = DayKey.date(from: cycle.endDayKey)
        let today = Cal.startOfDay(Date())
        let daysSinceEnd = MarenReviewEngine.calendarDaysBetween(endExclusive, today)
        return daysSinceEnd >= 0 && daysSinceEnd <= 7
    }

    private func completedCycleLine(_ cycle: MarenReviewEngine.CompletedCycleResult) -> some View {
        HStack(spacing: MarenDesign.spacingS) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(AppTheme.current.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "完成周期"))
                    .font(.caption.weight(.medium))
                Text("\(cycle.cycleLength) 天 · \(DayKey.date(from: cycle.startDayKey), style: .date)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, MarenDesign.spacingM)
        .padding(.vertical, MarenDesign.spacingS)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusS))
    }

    private var weeklyLine: some View {
        HStack(spacing: MarenDesign.spacingS) {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption)
                .foregroundStyle(AppTheme.current.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "本周回顾"))
                    .font(.caption.weight(.medium))
                switch weeklyReview.reviewStatus {
                case .empty:
                    Text(String(localized: "暂无记录"))
                        .font(.caption2).foregroundStyle(.secondary)
                case .limited:
                    Text(String(format: String(localized: "已记录 %lld 天"), weeklyReview.currentWindow.recordedDayKeys.count))
                        .font(.caption2).foregroundStyle(.secondary)
                case .ready:
                    if isPremium {
                        Text(weeklyReadySummary)
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(String(format: String(localized: "已记录 %lld 天"), weeklyReview.currentWindow.recordedDayKeys.count))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, MarenDesign.spacingM)
        .padding(.vertical, MarenDesign.spacingS)
        .background(MarenDesign.surface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusS))
    }

    private var weeklyReadySummary: String {
        let parts: [String] = [
            weeklyReview.averages.mood.map { String(format: String(localized: "心情 %.1f"), $0) },
            weeklyReview.averages.energy.map { String(format: String(localized: "能量 %.1f"), $0) },
            weeklyReview.averages.sleep.map { String(format: String(localized: "睡眠 %.1fh"), $0) },
        ].compactMap { $0 }
        return parts.joined(separator: String(localized: " · "))
    }
}
