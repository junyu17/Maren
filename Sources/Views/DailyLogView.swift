import SwiftUI
import SwiftData

/// F3:情绪 + 症状每日记录。3 秒打卡,极简。
struct DailyLogView: View {
    @Environment(\.modelContext) private var context
    @Query private var logs: [DailyLog]
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \CustomSymptom.createdAt) private var customSymptoms: [CustomSymptom]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query private var intakes: [MedicationIntake]

    @State private var day: Date = Cal.startOfDay(Date())
    /// 已经把哪一天的内容读进草稿了。用它避免重复回填,
    /// 否则每次切回本页都会用「已保存的值」覆盖掉用户还没保存的修改。
    @State private var loadedDay: Date?
    /// 用户是否手动选过日期。没选过时,跨过午夜会自动跟到新的今天。
    @State private var userPickedDate = false

    // 编辑中的草稿状态
    @State private var mood: Mood?
    @State private var energy: Int = 0        // 0 = 未选
    @State private var pain: Int = -1         // -1 = 未选
    @State private var symptoms: Set<String> = []
    @State private var sleepHours: Double?     // nil = 未记录
    @State private var weight: Double?         // nil = 未记录(kg)
    @State private var note: String = ""
    @State private var savedFlash = false
    @State private var showAddSymptom = false
    @State private var showPaywall = false
    @ObservedObject private var store = Store.shared

    /// 睡眠时长显示文本,跟随地区数字格式(3.5 / 3,5)。
    private var sleepText: String {
        (sleepHours ?? 0).formatted(.number.precision(.fractionLength(0...1)))
    }
    private var weightText: String {
        (weight ?? 0).formatted(.number.precision(.fractionLength(0...1)))
    }

    /// 添加自定义症状:免费层达 3 个上限时弹付费墙,Pro 无限。
    private func tryAddCustomSymptom() {
        if !store.premium && customSymptoms.count >= CustomSymptom.freeLimit {
            showPaywall = true
        } else {
            showAddSymptom = true
        }
    }

    /// 只在「今天」这一天显示用药打卡(过去的日子不补吃药)。
    private var todaysMeds: [Medication] {
        Cal.isSameDay(day, Date()) ? medications : []
    }
    private var takenMedIds: Set<UUID> {
        let key = DayKey.from(day)
        return Set(intakes.filter { $0.dayKey == key }.map { $0.medicationId })
    }

    private var todaysLog: DailyLog? {
        logs.first { Cal.isSameDay($0.date, day) }
    }

    /// F4:按当天所处周期阶段匹配的每日一句。
    private var todaysQuote: String {
        let prediction = CyclePredictor.predict(from: periodDays, manual: ManualCycle.current)
        let phase = PhaseModel.phase(for: day, prediction: prediction,
                                     periodDates: Set(periodDays.map { $0.date }))
        return DailyQuote.forToday(phase: phase, date: day)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(todaysQuote)
                        .font(.callout)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .listRowBackground(FlowLevel.spotting.tint.opacity(0.14))
                }

                Section {
                    // 用自定义 Binding:只有「用户真的动了日期选择器」才算手动选日期,
                    // 程序自动跟到今天时不会被误判。
                    DatePicker("日期", selection: Binding(
                        get: { day },
                        set: { newValue in
                            userPickedDate = true
                            day = Cal.startOfDay(newValue)
                        }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: day) { _, _ in loadDraftIfNeeded() }
                }

                Section("今天心情如何?") {
                    HStack {
                        ForEach(Mood.allCases) { m in
                            Button {
                                mood = (mood == m) ? nil : m
                            } label: {
                                VStack(spacing: 4) {
                                    Text(m.emoji)
                                        .font(.system(size: 30))
                                        .opacity(mood == nil || mood == m ? 1 : 0.35)
                                    Text(m.label).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel(Text(m.label))
                            .accessibilityAddTraits(mood == m ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("能量") {
                    RatingRow(value: $energy, range: 1...5, symbol: "bolt.fill",
                              tint: .orange, unsetValue: 0, title: "能量")
                }

                Section("疼痛") {
                    // 5 格,与心情、能量三行统一;未选=不亮(-1)。
                    RatingRow(value: $pain, range: 1...5, symbol: "waveform.path.ecg",
                              tint: .red, unsetValue: -1, title: "疼痛")
                }

                Section("睡眠") {
                    Stepper(value: Binding(get: { sleepHours ?? 7 },
                                           set: { sleepHours = $0 }),
                            in: 0...14, step: 0.5) {
                        HStack {
                            Text("睡眠时长")
                            Spacer()
                            Text(sleepHours == nil
                                 ? String(localized: "未记录")
                                 : String(localized: "\(sleepText) 小时"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if sleepHours != nil {
                        Button("清除睡眠记录") { sleepHours = nil }
                            .foregroundStyle(.secondary)
                    }
                }

                Section("体重") {
                    Stepper(value: Binding(get: { weight ?? 60 },
                                           set: { weight = $0 }),
                            in: 30...200, step: 0.1) {
                        HStack {
                            Text("体重")
                            Spacer()
                            Text(weight == nil
                                 ? String(localized: "未记录")
                                 : String(localized: "\(weightText) 公斤"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if weight != nil {
                        Button("清除体重记录") { weight = nil }
                            .foregroundStyle(.secondary)
                    }
                }

                if !todaysMeds.isEmpty {
                    Section("今日用药") {
                        ForEach(todaysMeds) { med in
                            Button {
                                toggleMed(med)
                            } label: {
                                HStack {
                                    Text(med.emoji)
                                    Text(med.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: takenMedIds.contains(med.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(takenMedIds.contains(med.id)
                                                         ? FlowLevel.medium.tint : .secondary)
                                }
                            }
                            .accessibilityAddTraits(takenMedIds.contains(med.id) ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                Section("症状") {
                    ChipGrid(selected: $symptoms, customTags: customSymptoms.map {
                        SymptomTag(key: $0.key, label: $0.label, emoji: $0.emoji)
                    }, onAdd: { tryAddCustomSymptom() })
                }

                Section("备注") {
                    TextField("想记点什么…", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            Text(savedFlash ? "已保存 ✓" : "保存今天的记录")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color(red: 0.82, green: 0.36, blue: 0.42))
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("每日记录")
            .navigationBarTitleDisplayMode(.inline)
            // 给底部留出空间,避免最后一行(症状/保存)被浮动标签栏遮住。
            .contentMargins(.bottom, 48, for: .scrollContent)
            .sheet(isPresented: $showAddSymptom) {
                CustomSymptomEditor { label, emoji in
                    let s = CustomSymptom(label: label, emoji: emoji)
                    context.insert(s)
                    try? context.save()
                    CustomSymptomStore.refresh(context)
                    symptoms.insert(s.key)   // 新建即选中
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear {
                // 跨过午夜后自动跟到新的今天(前提是用户没有手动选过别的日期)。
                let today = Cal.startOfDay(Date())
                if !userPickedDate && day != today { day = today }
                loadDraftIfNeeded()
            }
        }
    }

    /// 打卡 / 取消今天的用药。
    private func toggleMed(_ med: Medication) {
        let key = DayKey.from(day)
        if let existing = intakes.first(where: { $0.medicationId == med.id && $0.dayKey == key }) {
            context.delete(existing)
        } else {
            context.insert(MedicationIntake(medicationId: med.id, dayKey: key))
        }
        try? context.save()
    }

    // MARK: - 草稿加载 / 保存

    /// 只在「目标日期真的换了」时才回填,保护用户未保存的编辑。
    private func loadDraftIfNeeded() {
        guard loadedDay != day else { return }
        loadDraft(for: day)
        loadedDay = day
    }

    private func loadDraft(for date: Date) {
        if let log = logs.first(where: { Cal.isSameDay($0.date, date) }) {
            mood = log.mood
            energy = log.energy
            pain = log.pain
            symptoms = Set(log.symptoms)
            sleepHours = log.sleepHours
            weight = log.weight
            note = log.note
        } else {
            mood = nil
            energy = 0
            pain = -1
            symptoms = []
            sleepHours = nil
            weight = nil
            note = ""
        }
    }

    /// 当前草稿是否有实际内容。空白记录不该落库,否则会污染趋势统计和导出。
    private var draftHasContent: Bool {
        mood != nil || energy != 0 || pain >= 0 || !symptoms.isEmpty
            || sleepHours != nil || weight != nil
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let key = Cal.startOfDay(day)
        if let log = todaysLog {
            if draftHasContent {
                log.mood = mood
                log.energy = energy
                log.pain = pain
                log.symptoms = Array(symptoms).sorted()
                log.sleepHours = sleepHours
                log.weight = weight
                log.note = note
                log.updatedAt = Date()
            } else {
                // 用户把这一天清空了 → 删除整条记录,而不是留一条空壳。
                context.delete(log)
            }
        } else if draftHasContent {
            let log = DailyLog(date: key, mood: mood, energy: energy, pain: pain,
                               sleepHours: sleepHours, weight: weight,
                               symptoms: Array(symptoms).sorted(), note: note)
            context.insert(log)
        }
        try? context.save()
        loadedDay = day
        WidgetSync.refresh(periodDays: periodDays, logs: logs)
        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { savedFlash = false }
        }
    }
}

// MARK: - 1...5 / 0...5 点选评分

private struct RatingRow: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let symbol: String
    let tint: Color
    let unsetValue: Int
    /// 用于 VoiceOver 播报,例如「能量」。
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(range), id: \.self) { i in
                Button {
                    value = (value == i) ? unsetValue : i
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(value != unsetValue && i <= value ? tint : Color.secondary.opacity(0.35))
                        // 最小 44pt 命中区域,符合 Apple 触控目标规范。
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(i)"))
                .accessibilityAddTraits(value == i ? [.isButton, .isSelected] : .isButton)
            }
        }
        // 整行对 VoiceOver 播报一个可调节的值,比逐个图标更好用。
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(value == unsetValue
                            ? Text("未选择")
                            : Text("\(value) / \(range.upperBound)"))
    }
}

// MARK: - 症状多选芯片

private struct ChipGrid: View {
    @Binding var selected: Set<String>
    var customTags: [SymptomTag] = []
    var onAdd: (() -> Void)? = nil

    /// 内置 + 自定义,按标签长度升序:短的在前、长的自然落到每行右侧与末尾,视觉更整齐。
    /// (长度随语言变化,所以在运行时排序,中英文都成立。)
    private var orderedTags: [SymptomTag] {
        (Symptoms.all + customTags).sorted {
            ($0.label.count, $0.key) < ($1.label.count, $1.key)
        }
    }

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            if let onAdd {
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("自定义").font(.footnote).lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .foregroundStyle(.secondary))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加自定义症状")
            }
            ForEach(orderedTags) { tag in
                let isOn = selected.contains(tag.key)
                Button {
                    if isOn { selected.remove(tag.key) } else { selected.insert(tag.key) }
                } label: {
                    HStack(spacing: 4) {
                        Text(tag.emoji)
                        Text(tag.label)
                            .font(.footnote)
                            .lineLimit(1)          // 绝不换行
                            .fixedSize()           // 绝不压缩/截断,按完整文字取宽
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)          // 触控目标不小于 44pt
                    .background(
                        isOn ? Color(red: 0.82, green: 0.36, blue: 0.42).opacity(0.18)
                             : Color(.tertiarySystemFill),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            isOn ? Color(red: 0.82, green: 0.36, blue: 0.42) : .clear,
                            lineWidth: 1.5
                        )
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                // 选中与否目前只靠描边/底色区分,必须补上语义状态。
                .accessibilityLabel(Text(tag.label))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DailyLogView()
        .modelContainer(for: [PeriodDay.self, DailyLog.self], inMemory: true)
}
