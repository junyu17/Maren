import SwiftUI

/// 层级 1 · 阶段科普面板。展示四个周期阶段各自在发生什么,帮用户看懂日历上的多色标注。
/// 明确非医疗建议。
struct PhaseInfoView: View {
    @Environment(\.dismiss) private var dismiss

    /// 展示顺序:按周期自然顺序。
    private let phases: [CyclePhase] = [.menstrual, .follicular, .ovulatory, .luteal]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("每个人的身体节律不同,以下只是常见的大致规律,帮助你理解日历上的阶段颜色。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(phases) { phase in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(phase.legendFill)
                                    .frame(width: 14, height: 14)
                                Text(phase.label)
                                    .font(.headline)
                            }
                            Text(PhaseInfo.body(for: phase))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
                        Text("以上为一般性健康科普,基于你记录的阶段为估算,不构成医学建议或诊断,也不可作为避孕或备孕的依据。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("了解周期阶段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
