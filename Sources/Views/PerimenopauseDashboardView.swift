import SwiftUI

/// A small, neutral presentation of the bounded perimenopause trend report.
/// The view receives already-computed facts and does not read or infer data.
struct PerimenopauseDashboardView: View {
    enum TimeRange: Int, CaseIterable, Identifiable {
        case thirty = 30
        case ninety = 90

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .thirty: return String(localized: "30 days")
            case .ninety: return String(localized: "90 days")
            }
        }

        func window(from report: PerimenopauseTrendEngine.Report)
            -> PerimenopauseTrendEngine.Window {
            switch self {
            case .thirty: return report.thirtyDay
            case .ninety: return report.ninetyDay
            }
        }
    }

    typealias WindowSelection = TimeRange

    let report: PerimenopauseTrendEngine.Report

    @State private var selectedRange: TimeRange

    init(report: PerimenopauseTrendEngine.Report,
         initialRange: TimeRange = .thirty) {
        self.report = report
        _selectedRange = State(initialValue: initialRange)
    }

    init(output: PerimenopauseTrendEngine.Output,
         initialRange: TimeRange = .thirty) {
        self.init(report: output, initialRange: initialRange)
    }

    private var window: PerimenopauseTrendEngine.Window {
        selectedRange.window(from: report)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rangePicker
                coverageCard

                if window.isDataSparse {
                    sparseCard
                }

                symptomCard
                cycleCard
                averagesCard
                disclaimer
            }
            .padding()
        }
        .navigationTitle(String(localized: "Perimenopause summary"))
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Time range"))
                .font(.subheadline.weight(.semibold))

            Picker(String(localized: "Time range"), selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel(String(localized: "Time range"))
        }
    }

    private var coverageCard: some View {
        sectionCard(title: String(localized: "Record coverage"), systemImage: "calendar") {
            metricRow(
                label: String(localized: "Recent"),
                value: coverageText(days: window.coverageDays)
            )
            metricRow(
                label: String(localized: "Previous"),
                value: coverageText(days: window.previousCoverageDays)
            )
        }
    }

    private var sparseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Limited record coverage"), systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))

            Text(sparseMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var sparseMessage: String {
        if window.coverageDays == 0 && window.previousCoverageDays == 0 {
            return String(localized: "No entries were recorded in these two time ranges.")
        }
        return String(localized: "Some direction comparisons need at least 3 recorded days in each time range.")
    }

    private var symptomCard: some View {
        sectionCard(title: String(localized: "Recorded symptom days"), systemImage: "list.bullet") {
            if meaningfulTrends.isEmpty {
                Text(String(localized: "No listed symptom entries in this time range."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            } else {
                ForEach(meaningfulTrends) { trend in
                    symptomRow(trend)
                    if trend.id != meaningfulTrends.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var meaningfulTrends: [PerimenopauseTrendEngine.SymptomTrend] {
        window.symptomTrends.filter { trend in
            trend.recentCount > 0 || trend.previousCount > 0 ||
                trend.direction == .rising || trend.direction == .falling
        }
    }

    private func symptomRow(_ trend: PerimenopauseTrendEngine.SymptomTrend) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(symptomLabel(for: trend.key))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text(countText(for: trend))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(trend.direction.label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "\(symptomLabel(for: trend.key)), \(countText(for: trend)), \(trend.direction.label)")
        )
    }

    private var cycleCard: some View {
        sectionCard(title: String(localized: "Cycle length facts"), systemImage: "arrow.left.and.right") {
            if let minimum = window.cycleLength.minimum,
               let maximum = window.cycleLength.maximum {
                metricRow(
                    label: String(localized: "Minimum–maximum"),
                    value: String(localized: "\(minimum)–\(maximum) days")
                )
                if let range = window.cycleLength.range {
                    metricRow(
                        label: String(localized: "Range"),
                        value: String(localized: "\(range) days")
                    )
                }
            } else {
                Text(String(localized: "Not enough recorded period starts for a cycle-length range."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var averagesCard: some View {
        if window.sleep.recentAverage != nil || window.sleep.previousAverage != nil ||
            window.mood.recentAverage != nil || window.mood.previousAverage != nil {
            sectionCard(title: String(localized: "Recorded averages"), systemImage: "chart.bar") {
                if window.sleep.recentAverage != nil || window.sleep.previousAverage != nil {
                    averageRow(
                        label: String(localized: "Sleep"),
                        average: window.sleep,
                        suffix: String(localized: "hours")
                    )
                }
                if window.mood.recentAverage != nil || window.mood.previousAverage != nil {
                    averageRow(
                        label: String(localized: "Mood"),
                        average: window.mood,
                        suffix: String(localized: "out of 5")
                    )
                }
            }
        }
    }

    private var disclaimer: some View {
        Text(String(localized: "This summary describes recorded entries only. It is not medical advice or a diagnosis."))
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityLabel(String(localized: "This summary describes recorded entries only. It is not medical advice or a diagnosis."))
    }

    private func countText(for trend: PerimenopauseTrendEngine.SymptomTrend) -> String {
        let recent = "\(trend.recentCount) / \(window.coverageDays)"
        let previous = "\(trend.previousCount) / \(window.previousCoverageDays)"
        return String(localized: "Recent \(recent) recorded days; previous \(previous) recorded days")
    }

    private func coverageText(days: Int) -> String {
        String(localized: "\(days) of \(window.days) days")
    }

    private func symptomLabel(for key: String) -> String {
        if key == "sleepInterrupted" {
            return String(localized: "Sleep interrupted")
        }
        return Symptoms.label(for: key)
    }

    private func averageRow(label: String,
                            average: PerimenopauseTrendEngine.AverageComparison,
                            suffix: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.body)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(averageText(average.recentAverage, suffix: suffix))
                Text(averageText(average.previousAverage, suffix: suffix))
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func averageText(_ value: Double?, suffix: String) -> String {
        guard let value else {
            return String(localized: "Not enough data")
        }
        let formatted = value.formatted(.number.precision(.fractionLength(0...1)))
        return "\(formatted) \(suffix)"
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func sectionCard<Content: View>(title: String,
                                            systemImage: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
