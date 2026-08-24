import SwiftUI

/// 「最近完成的周期有什么变化」—— 展示 CycleComparisonEngine 的结果。
/// 在 Trends 中作为 Premium 卡片展示;点击进入详细页面。
struct CycleComparisonCard: View {
    let logs: [DailyLog]
    let prediction: CyclePredictor.Prediction
    @ObservedObject private var store = Store.shared
    @State private var showDetail = false
    @State private var showPaywall = false

    var body: some View {
        if store.premium {
            let result = CycleComparisonEngine.compare(prediction: prediction, logs: logs)
            if result.hasEnoughData {
                Button { showDetail = true } label: {
                    cardContent(result)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showDetail) {
                    NavigationStack {
                        CycleComparisonDetailView(result: result)
                    }
                }
            } else {
                emptyCard(result.message)
            }
        } else {
            lockedCard
        }
    }

    private func cardContent(_ result: CycleComparisonEngine.ComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(String(localized: "最近完成周期变化"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            // 取前 3 个指标做摘要
            ForEach(result.metrics.prefix(3)) { metric in
                HStack(alignment: .top, spacing: 8) {
                    changeIcon(metric.change)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label).font(.caption).foregroundStyle(.secondary)
                        Text("\(metric.current) → \(metric.baseline)")
                            .font(.subheadline).lineLimit(1)
                    }
                }
            }

            if result.sampleSize > 0 {
                Text(String(format: String(localized: "基于 %lld 个历史周期对比。"), result.sampleSize))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func emptyCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "最近完成周期变化"), systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "最近完成周期变化"), systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "升级 Premium,查看最近完成周期与历史的详细对比分析。"))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(localized: "包括周期长度、经期天数、心情、睡眠、体重和追踪项的变化趋势。"))
                .font(.caption2).foregroundStyle(.tertiary)
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

    @ViewBuilder
    private func changeIcon(_ direction: CycleComparisonEngine.Metric.ChangeDirection) -> some View {
        switch direction {
        case .shorter, .lower:
            Image(systemName: "arrow.down")
                .font(.caption).foregroundStyle(.blue)
        case .longer, .higher:
            Image(systemName: "arrow.up")
                .font(.caption).foregroundStyle(.orange)
        case .unchanged:
            Image(systemName: "minus")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 详细页面

struct CycleComparisonDetailView: View {
    let result: CycleComparisonEngine.ComparisonResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 头部
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(FlowLevel.medium.tint)
                    Text(String(localized: "最近完成周期变化详情"))
                        .font(.title3.weight(.semibold))
                    Text(String(format: String(localized: "对比最近完成周期与近 %lld 个历史周期。"), result.sampleSize))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()

                // 各指标
                ForEach(result.metrics) { metric in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(metric.label).font(.subheadline.weight(.semibold))
                            Spacer()
                            changeBadge(metric.change)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "最近完成周期")).font(.caption).foregroundStyle(.secondary)
                                Text(metric.current).font(.headline)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(localized: "近期平均")).font(.caption).foregroundStyle(.secondary)
                                Text(metric.baseline).font(.headline)
                            }
                        }
                        Text(metric.note)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }

                // 免责声明
                Text(String(localized: "以上对比仅供参考,不构成医学建议。如有疑虑请咨询医生。"))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding()
            }
            .padding()
        }
        .navigationTitle(String(localized: "最近完成周期变化"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "完成")) { dismiss() }
            }
        }
    }

    private func changeBadge(_ direction: CycleComparisonEngine.Metric.ChangeDirection) -> some View {
        let (text, color): (String, Color)
        switch direction {
        case .shorter:  text = String(localized: "↓ 短"); color = .blue
        case .longer:   text = String(localized: "↑ 长"); color = .orange
        case .lower:    text = String(localized: "↓ 低"); color = .blue
        case .higher:   text = String(localized: "↑ 高"); color = .orange
        case .unchanged: text = String(localized: "— 持平"); color = .secondary
        }
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
