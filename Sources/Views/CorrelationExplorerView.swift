import SwiftUI
import SwiftData

/// The Trends entry point describes its source coverage, not a pairwise N.
/// Pairwise sample sizes are shown on the individual correlation cards.
enum CorrelationExplorerSummary {
    static func recordCountLabel(_ count: Int) -> String {
        String(localized: "记录天数: \(count)")
    }
}

/// 设备端相关性探索器 —— 展示 pairwise 关系的 Premium 详情页面。
struct CorrelationExplorerView: View {
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \DailyLog.dayKey) private var logs: [DailyLog]
    @Query private var medications: [Medication]
    @Query private var intakes: [MedicationIntake]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataChangeCenter = LocalDataChangeCenter.shared

    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength

    private var manualCycle: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }

    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: manualCycle)
    }

    private var correlations: [CorrelationEngine.Correlation] {
        CorrelationEngine.analyze(input: CorrelationEngine.AnalysisInput(
            periodDays: periodDays, logs: logs, prediction: prediction,
            medications: medications, intakes: intakes))
    }

    private var trackerRevision: UInt64 {
        dataChangeCenter.lastEvent?.revision ?? 0
    }

    var body: some View {
        let _ = trackerRevision
        ScrollView {
            VStack(spacing: 16) {
                header
                ForEach(correlations) { correlation in
                    correlationCard(correlation)
                }
                disclaimer
            }
            .padding()
        }
        .navigationTitle(String(localized: "相关性探索"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "完成")) { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.largeTitle)
                .foregroundStyle(FlowLevel.medium.tint)
            Text(String(localized: "探索你的数据中的关联模式"))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(String(localized: "以下分析基于你自己的记录,在设备端本地计算。所有结论均为观察性描述,不构成因果关系或医学建议。"))
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(FlowLevel.spotting.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func correlationCard(_ correlation: CorrelationEngine.Correlation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(correlation.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                sampleBadge(correlation)
            }

            Text(correlation.description)
                .font(.caption).foregroundStyle(.secondary)

            if correlation.sufficientData {
                ForEach(correlation.observations) { obs in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(obs.label).font(.subheadline)
                            Spacer()
                            Text(obs.value)
                                .font(.caption).foregroundStyle(FlowLevel.medium.tint)
                        }
                        Text(obs.detail)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if obs.id != correlation.observations.last?.id {
                        Divider()
                    }
                }
            } else {
                Text(String(localized: "数据不足,需要更多记录才能分析此关联。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sampleBadge(_ correlation: CorrelationEngine.Correlation) -> some View {
        Text(String(localized: "N = \(correlation.sampleSize)"))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(String(localized: "以上分析仅为基于个人记录的观察性统计,不构成因果关系、诊断依据或治疗建议。相关性不等于因果性,如有健康疑虑请咨询专业医疗人员。"))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Trends 中的相关性探索 Premium 卡片入口。
struct CorrelationExplorerCard: View {
    let logs: [DailyLog]
    @ObservedObject private var store = Store.shared
    @State private var showDetail = false
    @State private var showPaywall = false

    var body: some View {
        if store.premium {
            Button { showDetail = true } label: {
                cardContent
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                NavigationStack {
                    CorrelationExplorerView()
                }
            }
        } else {
            lockedCard
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(String(localized: "相关性探索"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            let summary = quickSummary
            if summary.isEmpty {
                Text(String(localized: "记录更多数据后,这里会展示你的数据中的关联模式。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(summary, id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(CorrelationExplorerSummary.recordCountLabel(logs.count))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var quickSummary: [String] {
        guard logs.count >= 5 else { return [] }
        var items: [String] = []
        let moods = logs.compactMap { $0.mood }
        let sleeps = logs.compactMap { $0.sleepHours }
        if moods.count >= 3 && sleeps.count >= 3 {
            items.append(String(localized: "睡眠与心情:正在分析"))
        }
        return items
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "相关性探索"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "升级 Premium,探索你的数据中睡眠、心情、周期阶段、用药打卡之间的关联模式。"))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showPaywall = true } label: {
                Label(String(localized: "升级解锁"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(FlowLevel.medium.tint)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }
}

#Preview {
    NavigationStack {
        CorrelationExplorerView()
            .modelContainer(for: [PeriodDay.self, DailyLog.self], inMemory: true)
    }
}
