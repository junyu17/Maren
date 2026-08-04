import SwiftUI
import SwiftData

/// 层级 2 · 用药 / 补剂管理。增删改 + 每日提醒(免费单次 / Pro 多时段按周几)。
struct MedicationManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medication.createdAt) private var meds: [Medication]
    @State private var editing: Medication?
    @State private var showAdd = false
    @State private var showSlotsCapped = false
    @ObservedObject private var store = Store.shared

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
                            Text(summary(med)).font(.caption).foregroundStyle(.secondary)
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
        .alert("提醒已达系统上限", isPresented: $showSlotsCapped) {
            Button("好") {}
        } message: {
            Text("iOS 最多同时安排 64 条本地提醒。本次的部分提醒时段因超限未能排上,建议减少时段数量或选择更少的周几。")
        }
    }

    private func summary(_ med: Medication) -> String {
        if med.proScheduleEnabled && store.premium && !med.slots.isEmpty {
            return String(localized: "\(med.slots.count) 个提醒时段")
        }
        if med.reminderEnabled {
            return String(localized: "每天 \(timeText(med.reminderHour, med.reminderMinute)) 提醒")
        }
        return String(localized: "未开启提醒")
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
            // 先撤掉旧排期(单次 + 旧多时段),再改字段重排,避免残留。
            NotificationManager.shared.cancelAllMedicationReminders(notificationId: med.notificationId)
            med.name = draft.name
            med.emoji = draft.emoji
        } else {
            med = Medication(name: draft.name, emoji: draft.emoji)
            context.insert(med)
        }
        let usePro = draft.proScheduleEnabled && store.premium && !draft.slots.isEmpty
        med.proScheduleEnabled = usePro
        if usePro {
            med.setSlots(draft.slots)
            med.reminderEnabled = true
        } else {
            med.setSlots([])
            med.reminderEnabled = draft.reminderEnabled
            med.reminderHour = draft.hour
            med.reminderMinute = draft.minute
        }
        try? context.save()
        // 重排:Pro 走多时段,否则走单次。
        if usePro {
            // 系统对 pending 本地通知有 64 条硬上限,多药叠加会超限导致静默丢弃;
            // 返回 false 时提示用户减少时段/周几。
            Task {
                let ok = await NotificationManager.shared.scheduleMedicationSlots(
                    notificationId: med.notificationId, name: med.name, slots: med.slots)
                if !ok { showSlotsCapped = true }
            }
        } else if med.reminderEnabled {
            NotificationManager.shared.scheduleMedicationReminder(
                id: med.notificationId, name: med.name,
                enabled: true, hour: med.reminderHour, minute: med.reminderMinute)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            let med = meds[i]
            NotificationManager.shared.cancelAllMedicationReminders(notificationId: med.notificationId)
            // Medication 与 MedicationIntake 以 UUID 关联(SwiftData 无级联),
            // 必须手动清掉该药的全部打卡记录,否则孤儿数据永久残留并随 CloudKit 同步。
            let medId = med.id
            let intakes = (try? context.fetch(
                FetchDescriptor<MedicationIntake>(
                    predicate: #Predicate { $0.medicationId == medId }))) ?? []
            intakes.forEach { context.delete($0) }
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
        var proScheduleEnabled: Bool
        var slots: [ReminderSlot]
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Store.shared
    let med: Medication?
    let onSave: (Draft) -> Void

    @State private var name: String
    @State private var emoji: String
    @State private var reminderEnabled: Bool
    @State private var time: Date
    @State private var proScheduleEnabled: Bool
    @State private var slots: [ReminderSlot]

    private let choices = ["💊", "🟡", "🔵", "🧴", "💉", "🌿", "🩹", "☀️"]

    init(med: Medication?, onSave: @escaping (Draft) -> Void) {
        self.med = med
        self.onSave = onSave
        _name = State(initialValue: med?.name ?? "")
        _emoji = State(initialValue: med?.emoji ?? "💊")
        _reminderEnabled = State(initialValue: med?.reminderEnabled ?? false)
        var c = DateComponents(); c.hour = med?.reminderHour ?? 9; c.minute = med?.reminderMinute ?? 0
        _time = State(initialValue: Cal.current.date(from: c) ?? Date())
        _proScheduleEnabled = State(initialValue: med?.proScheduleEnabled ?? false)
        _slots = State(initialValue: med?.slots ?? [])
    }

    /// Pro 模式生效需同时:开关开 + 已升级 + 至少一个时段。
    private var usePro: Bool { proScheduleEnabled && store.premium }

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
                    if store.premium {
                        Toggle("高级排程(多时段 / 按周几)", isOn: $proScheduleEnabled)
                    }
                    if usePro {
                        slotEditor
                    } else {
                        Toggle("每日提醒", isOn: $reminderEnabled)
                        if reminderEnabled {
                            DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                } footer: {
                    if usePro {
                        Text("可设多个时间点,并选择只在某些周几提醒。提醒在本机生成,不经过服务器。")
                    } else {
                        Text("提醒在本机生成,不经过服务器。")
                    }
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
                                     hour: c.hour ?? 9, minute: c.minute ?? 0,
                                     proScheduleEnabled: proScheduleEnabled,
                                     slots: slots))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// Pro 多时段编辑器:每个时段一个时间 + 周几选择;可增删,上限 `maxSlots`。
    @ViewBuilder
    private var slotEditor: some View {
        ForEach($slots) { $slot in
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("时间", selection: Binding(
                    get: { dateFromTime(slot.hour, slot.minute) },
                    set: {
                        let c = Cal.current.dateComponents([.hour, .minute], from: $0)
                        slot.hour = c.hour ?? 9; slot.minute = c.minute ?? 0
                    }),
                    displayedComponents: .hourAndMinute)
                WeekdayPicker(weekdays: $slot.weekdays)
            }
            .padding(.vertical, 2)
        }
        .onDelete { offsets in slots.remove(atOffsets: offsets) }
        if slots.count < MedicationSlotsPolicy.maxSlots {
            Button {
                slots.append(ReminderSlot())
            } label: {
                Label("添加时段", systemImage: "plus")
            }
        } else {
            Text("已达 \(MedicationSlotsPolicy.maxSlots) 个时段上限。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dateFromTime(_ h: Int, _ m: Int) -> Date {
        var c = DateComponents(); c.hour = h; c.minute = m
        return Cal.current.date(from: c) ?? Date()
    }
}

/// 周几选择器:7 个可切换的按钮(Sun…Sat,用系统本地化短符号)。
struct WeekdayPicker: View {
    @Binding var weekdays: [Int]
    private let symbols = Cal.current.shortWeekdaySymbols // [Sun, Mon, ...] 下标 0-6;weekday 1=Sunday

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { w in
                let idx = w - 1
                let on = weekdays.contains(w)
                Button {
                    if on { weekdays.removeAll { $0 == w } }
                    else { weekdays.append(w); weekdays.sort() }
                } label: {
                    Text(symbols.indices.contains(idx) ? symbols[idx] : "\(w)")
                        .font(.caption.weight(.medium))
                        .frame(width: 34, height: 30)
                        .foregroundStyle(on ? .white : .primary)
                        .background(on ? FlowLevel.medium.tint : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbols.indices.contains(idx) ? symbols[idx] : "\(w)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
            }
        }
    }
}
