import SwiftUI

struct TodayStatusCard: View {
    let output: TodayStatusEngine.Output
    let phase: CyclePhase
    let date: Date

    init(output: TodayStatusEngine.Output, phase: CyclePhase = .unknown, date: Date = Date()) {
        self.output = output
        self.phase = phase
        self.date = date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MarenDesign.spacingM) {
            // Hero row: date + phase pill
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: MarenDesign.spacingXS) {
                    Text(todayDateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(output.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                if phase != .unknown {
                    phasePill(phase)
                }
            }

            if output.isDataSparse {
                // Compact sparse prompt — single line, no nested card
                HStack(spacing: MarenDesign.spacingS) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppTheme.current.accent)
                    Text(String(localized: "记录心情、睡眠或症状，开始今天的打卡"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MarenDesign.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MarenDesign.accentTint(opacity: 0.08),
                    in: RoundedRectangle(cornerRadius: MarenDesign.radiusS)
                )
            } else {
                VStack(alignment: .leading, spacing: MarenDesign.spacingS) {
                    ForEach(output.observations.prefix(3), id: \.self) { observation in
                        HStack(alignment: .top, spacing: MarenDesign.spacingS) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(FlowLevel.medium.tint)
                                .padding(.top, 6)
                            Text(observation)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(observation)
                    }
                }
            }
        }
        .padding(MarenDesign.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MarenDesign.surface,
            in: RoundedRectangle(cornerRadius: MarenDesign.radiusL)
        )
        .shadow(color: .black.opacity(MarenDesign.shadowOpacity),
                radius: MarenDesign.shadowRadius, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(output.title)
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEEE")
        return formatter.string(from: date)
    }

    private func phasePill(_ p: CyclePhase) -> some View {
        HStack(spacing: 4) {
            Circle().fill(p.legendFill).frame(width: 6, height: 6)
            Text(p.label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, MarenDesign.spacingS)
        .padding(.vertical, MarenDesign.spacingXS)
        .background(p.cellFill, in: Capsule())
    }
}
