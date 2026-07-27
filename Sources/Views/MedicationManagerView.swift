import SwiftUI
import SwiftData

/// 层级 2 · 用药 / 补剂管理。增删改 + 每日提醒。
struct MedicationManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.createdAt) private var meds: [Medication]
    @State private var editing: Medication?
    @State private var showAdd = false

    var body: some View {
        List {
            if meds.isEmpty {
                Text("还没有添加任何用药或补剂。点右上角「＋」加一个,比如二甲双胍、肌醇、维生素 D。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(meds) { med in
                Button { editing = med } label: {
                    HStack {
                        Text(med.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name).foregroundStyle(.primary)
                            if med.reminderEnabled {
                                Text(String(localized: "每天 \(timeText(med.reminderHour, med.reminderMinute)) 提醒"))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("未开启提醒").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .navigationTitle("用药与补剂")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加用药")
            }
        }
        .sheet(isPresented: $showAdd) {
            MedicationEditor(med: nil) { save($0) }
        }
        .sheet(item: $editing) { med in
            MedicationEditor(med: med) { save($0) }
        }
    }

    private func timeText(_ h: Int, _ m: Int) -> String {
        var c = DateComponents(); c.hour = h; c.minute = m
        let d = Cal.current.date(from: c) ?? Date()
        let f = DateFormatter(); f.locale = Locale.current; f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }

    private func save(_ draft: MedicationEditor.Draft) {
        let med: Medication
        if let existing = draft.existing {
            med = existing
            med.name = draft.name
            med.emoji = draft.emoji
            med.reminderEnabled = draft.reminderEnabled
            med.reminderHour = draft.hour
            med.reminderMinute = draft.minute
        } else {
            med = Medication(name: draft.name, emoji: draft.emoji,
                             reminderEnabled: draft.reminderEnabled,
                             reminderHour: draft.hour, reminderMinute: draft.minute)
            context.insert(med)
        }
        try? context.save()
        NotificationManager.shared.scheduleMedicationReminder(
            id: med.notificationId, name: med.name,
            enabled: med.reminderEnabled, hour: med.reminderHour, minute: med.reminderMinute)
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            let med = meds[i]
            NotificationManager.shared.cancelMedicationReminder(id: med.notificationId)
            context.delete(med)
        }
        try? context.save()
    }
}

/// 新建 / 编辑一个药。
struct MedicationEditor: View {
    struct Draft {
        var existing: Medication?
        var name: String
        var emoji: String
        var reminderEnabled: Bool
        var hour: Int
        var minute: Int
    }

    @Environment(\.dismiss) private var dismiss
    let med: Medication?
    let onSave: (Draft) -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var reminderEnabled: Bool
    @State private var time: Date

    private let choices = ["💊", "🟡", "🔵", "🧴", "💉", "🌿", "🩹", "☀️"]

    init(med: Medication?, onSave: @escaping (Draft) -> Void) {
        self.med = med
        self.onSave = onSave
        _name = State(initialValue: med?.name ?? "")
        _emoji = State(initialValue: med?.emoji ?? "💊")
        _reminderEnabled = State(initialValue: med?.reminderEnabled ?? false)
        var c = DateComponents(); c.hour = med?.reminderHour ?? 9; c.minute = med?.reminderMinute ?? 0
        _time = State(initialValue: Cal.current.date(from: c) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如:二甲双胍、肌醇、维生素 D", text: $name)
                }
                Section("图标") {
                    HStack {
                        ForEach(choices, id: \.self) { e in
                            Text(e).font(.title2)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(emoji == e ? FlowLevel.spotting.tint.opacity(0.3) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { emoji = e }
                        }
                    }
                }
                Section {
                    Toggle("每日提醒", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("提醒在本机生成,不经过服务器。")
                }
            }
            .navigationTitle(med == nil ? String(localized: "添加用药") : String(localized: "编辑用药"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let c = Cal.current.dateComponents([.hour, .minute], from: time)
                        onSave(Draft(existing: med,
                                     name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                     emoji: emoji, reminderEnabled: reminderEnabled,
                                     hour: c.hour ?? 9, minute: c.minute ?? 0))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
