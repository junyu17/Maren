import SwiftUI

/// Local form for recording a contraception method and an optional daily
/// reminder preference. Notification scheduling belongs to the save callback.
struct ContraceptionManagerView: View {
    @State private var draft: ContraceptionSettings
    @State private var saveState: SaveState?

    private let defaults: UserDefaults
    private let onSave: (ContraceptionSettings) -> Void

    private enum SaveState {
        case success
        case failure

        var message: String {
            switch self {
            case .success: return String(localized: "Saved on this device.")
            case .failure: return String(localized: "Could not save this record. Try again.")
            }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        onSave: @escaping (ContraceptionSettings) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.onSave = onSave
        _draft = State(initialValue: ContraceptionSettings.load(from: defaults))
    }

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: $draft.method) {
                    ForEach(ContraceptionSettings.Method.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityLabel("Recorded method")
            } header: {
                Text("Record")
            } footer: {
                Text("Only the selected method and reminder preference are recorded locally. No effectiveness, missed-dose, diagnosis, or medical advice is provided here.")
            }

            if draft.method != .none {
                Section {
                    Toggle("Start date (optional)", isOn: hasStartDate)
                        .frame(minHeight: 44)
                    if draft.startDayKey != nil {
                        DatePicker("Start date", selection: startDate, displayedComponents: .date)
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Optional details")
                }

                if draft.method.supportsDailyReminder {
                    Section {
                        Toggle("Daily reminder", isOn: $draft.reminderEnabled)
                            .frame(minHeight: 44)
                        if draft.reminderEnabled {
                            DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
                                .frame(minHeight: 44)
                        }
                    } header: {
                        Text("Reminder")
                    } footer: {
                        Text("Reminder notifications are scheduled locally on this device. Notification permission is requested only when you enable reminders.")
                    }
                }

                Section {
                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityHint("Optional personal note, up to \(ContraceptionSettings.maxNoteLength) characters")
                        .onChange(of: draft.note) { _, note in
                            if note.count > ContraceptionSettings.maxNoteLength {
                                draft.note = String(note.prefix(ContraceptionSettings.maxNoteLength))
                            }
                        }
                } header: {
                    Text("Note")
                }
            }

            Section {
                if let saveState {
                    Text(saveState.message)
                        .foregroundStyle(saveState == .success ? Color.secondary : Color.red)
                        .accessibilityLabel(saveState.message)
                }

                Button("Save") {
                    save()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Save contraception record")
                .accessibilityHint("Saves this record locally on this device.")
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("Contraception record")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.method) { _, method in
            if method == .none {
                draft.startDayKey = nil
                draft.reminderEnabled = false
                draft.note = ""
            } else if !method.supportsDailyReminder {
                draft.reminderEnabled = false
            }
            saveState = nil
        }
    }

    private var hasStartDate: Binding<Bool> {
        Binding(
            get: { draft.startDayKey != nil },
            set: { enabled in
                draft.startDayKey = enabled ? (draft.startDayKey ?? DayKey.today) : nil
                saveState = nil
            }
        )
    }

    private var startDate: Binding<Date> {
        Binding(
            get: {
                guard let dayKey = draft.startDayKey else { return Cal.startOfDay(Date()) }
                return DayKey.date(from: dayKey)
            },
            set: {
                draft.startDayKey = DayKey.from($0)
                saveState = nil
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = draft.reminderHour
                components.minute = draft.reminderMinute
                return Cal.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Cal.current.dateComponents([.hour, .minute], from: date)
                draft.reminderHour = components.hour ?? draft.reminderHour
                draft.reminderMinute = components.minute ?? draft.reminderMinute
                saveState = nil
            }
        )
    }

    private func save() {
        var value = draft.normalized
        value.updatedAt = Date()
        guard value.save(to: defaults) else {
            saveState = .failure
            return
        }

        draft = value
        saveState = .success
        onSave(value)
    }
}
