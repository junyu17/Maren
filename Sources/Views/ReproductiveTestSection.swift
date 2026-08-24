import SwiftUI

/// Compact, neutral controls for recording same-day reproductive test entries.
/// This view only edits the supplied tracker-key set; it does not interpret it.
struct ReproductiveTestSection: View {
    @Binding var selectedKeys: Set<String>

    init(selectedKeys: Binding<Set<String>>) {
        _selectedKeys = selectedKeys
    }

    init(keys: Binding<Set<String>>) {
        _selectedKeys = keys
    }

    private var ovulationSelection: Binding<String> {
        Binding(
            get: { ReproductiveLog.ovulationTest(in: selectedKeys)?.rawValue ?? "" },
            set: { selectedKeys = ReproductiveLog.selectingOvulationTest($0, in: selectedKeys) }
        )
    }

    private var pregnancySelection: Binding<String> {
        Binding(
            get: { ReproductiveLog.pregnancyTest(in: selectedKeys)?.rawValue ?? "" },
            set: { selectedKeys = ReproductiveLog.selectingPregnancyTest($0, in: selectedKeys) }
        )
    }

    private var manualOvulation: Binding<Bool> {
        Binding(
            get: { ReproductiveLog.hasManualOvulation(in: selectedKeys) },
            set: { selectedKeys = ReproductiveLog.settingManualOvulation($0, in: selectedKeys) }
        )
    }

    var body: some View {
        Section {
            Picker("Ovulation test", selection: ovulationSelection) {
                Text("None").tag("")
                Text("Negative").tag(ReproductiveLog.OvulationTest.negative.rawValue)
                Text("Positive").tag(ReproductiveLog.OvulationTest.positive.rawValue)
                Text("Peak").tag(ReproductiveLog.OvulationTest.peak.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel("Ovulation test result")

            Toggle("Manual ovulation", isOn: manualOvulation)
                .frame(minHeight: 44)
                .accessibilityHint("Records this entry without interpreting it")

            Picker("Pregnancy test", selection: pregnancySelection) {
                Text("None").tag("")
                Text("Negative").tag(ReproductiveLog.PregnancyTest.negative.rawValue)
                Text("Positive").tag(ReproductiveLog.PregnancyTest.positive.rawValue)
                Text("Invalid").tag(ReproductiveLog.PregnancyTest.invalid.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityLabel("Pregnancy test result")
        } header: {
            Text("Reproductive tests")
        } footer: {
            Text("Logging only. This section does not interpret or predict results, diagnose conditions, or provide contraception guidance.")
        }
    }
}
