import Foundation
import SwiftUI
import SwiftData
import StoreKit

/// F3:情绪 + 症状每日记录。3 秒打卡,极简。
struct DailyLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.requestReview) private var requestReview
    /// The review strip only needs the same recent history used by
    /// `CyclePredictor`; keeping this query bounded avoids materializing a
    /// user's entire lifetime of logs whenever the 3-second check-in opens.
    @Query private var reviewLogs: [DailyLog]
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query(sort: \CustomSymptom.createdAt) private var customSymptoms: [CustomSymptom]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    private let focusedDate: Date?
    private let focusedTrackerQuery: String?
    private let focusedTrackerKey: String?
    @State private var day: Date
    /// 已经把哪一天的内容读进草稿了。用它避免重复回填,
    /// 否则每次切回本页都会用「已保存的值」覆盖掉用户还没保存的修改。
    @State private var loadedDay: Date?
    /// 用户是否手动选过日期。没选过时,跨过午夜会自动跟到新的今天。
    @State private var userPickedDate = false
    /// Exact row loaded for the selected day.  The review query is bounded,
    /// but the check-in editor must still support opening an older date.
    @State private var loadedLog: DailyLog?
    /// Medication check-ins are an exact selected-day fetch as well. This
    /// keeps older calendar dates correct without loading the intake table.
    @State private var loadedIntakes: [MedicationIntake] = []

    // 编辑中的草稿状态
    @State private var mood: Mood?
    @State private var energy: Int = 0        // 0 = 未选
    @State private var pain: Int = -1         // -1 = 未选
    @State private var symptoms: Set<String> = []
    @State private var sleepHours: Double?     // nil = 未记录
    @State private var weight: Double?         // nil = 未记录(kg)
    @State private var basalBodyTemperatureCelsius: Double? // nil = 未记录(℃)
    @State private var spotting: Bool?         // nil = 未记录,true = 有,false = 无
    @State private var note: String = ""
    @State private var savedFlash = false
    @State private var isSaving = false
    @State private var draftLoadFailed = false
    @State private var showErrorAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAddSymptom = false
    @State private var showPaywall = false
    @State private var showLibraryForScreenshot = ScreenshotRoute.current == .library
    /// `--shot trackers` 截图时滚动到的位置:睡眠一节起,下面是体重、体温和各项追踪。
    private static let screenshotTrackersAnchor = "screenshot-trackers"
    @State private var dailyStoryItem: EducationCatalog.Item?
    @AppStorage("education.bookmarks") private var bookmarksData = ""
    @AppStorage("education.dailyStoryHistory") private var dailyStoryHistoryData = ""
    @AppStorage(LifeStage.userDefaultsKey) private var lifeStageRaw = LifeStage.defaultValue.rawValue
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength
    /// 备注输入焦点。备注是 `axis: .vertical` 的多行输入,回车键只会换行、不会收键盘,
    /// 所以必须自己管焦点:键盘上给「完成」,保存时也主动收起。
    /// 键盘弹起时系统会把底部标签栏一起藏掉 —— 键盘不收,4 个标签就一直看不见。
    @FocusState private var noteFocused: Bool
    @ObservedObject private var store = Store.shared
    @ObservedObject private var dataChangeCenter = LocalDataChangeCenter.shared

    /// Snapshot of the last loaded model, used to detect dirty draft state.
    private struct DraftSnapshot: Equatable {
        var mood: Mood?
        var energy: Int
        var pain: Int
        var symptoms: Set<String>
        var sleepHours: Double?
        var weight: Double?
        var basalBodyTemperatureCelsius: Double?
        var spotting: Bool?
        var note: String
    }
    @State private var lastSnapshot: DraftSnapshot?

    /// Conflict alert state for external changes while draft is dirty.
    @State private var showConflictAlert = false

    init(focusedDate: Date? = nil,
         focusedTrackerQuery: String? = nil,
         focusedTrackerKey: String? = nil) {
        let normalizedDate = focusedDate.map(Cal.startOfDay)
        let queryRange = HistoricalDataQuery.recentDayKeyRange()
        let lowerDayKey = queryRange.lowerBound
        let upperDayKey = queryRange.upperBound
        _reviewLogs = Query(filter: #Predicate<DailyLog> { log in
            log.dayKey >= lowerDayKey && log.dayKey <= upperDayKey
        })
        self.focusedDate = normalizedDate
        self.focusedTrackerQuery = focusedTrackerQuery
        self.focusedTrackerKey = focusedTrackerKey
        _day = State(initialValue: normalizedDate ?? Cal.startOfDay(Date()))
        _userPickedDate = State(initialValue: normalizedDate != nil)
    }

    private var isDraftDirty: Bool {
        guard let snap = lastSnapshot else { return false }
        let current = DraftSnapshot(
            mood: mood, energy: energy, pain: pain,
            symptoms: symptoms, sleepHours: sleepHours,
            weight: weight, basalBodyTemperatureCelsius: basalBodyTemperatureCelsius,
            spotting: spotting, note: note
        )
        return snap != current
    }

    /// 睡眠时长显示文本,跟随地区数字格式(3.5 / 3,5)。
    private var sleepText: String {
        (sleepHours ?? 0).formatted(.number.precision(.fractionLength(0...1)))
    }
    private var weightText: String {
        (weight ?? 0).formatted(.number.precision(.fractionLength(0...1)))
    }
    private var basalBodyTemperatureText: String {
        (basalBodyTemperatureCelsius ?? 0).formatted(.number.precision(.fractionLength(2)))
    }
    private var basalBodyTemperatureDisplayText: String {
        guard basalBodyTemperatureCelsius != nil else { return String(localized: "未记录") }
        return "\(basalBodyTemperatureText) °C"
    }
    private var basalBodyTemperatureBinding: Binding<Double> {
        Binding(
            get: { basalBodyTemperatureCelsius ?? 36.5 },
            set: { basalBodyTemperatureCelsius = $0 }
        )
    }
    private var spottingText: String {
        switch spotting {
        case .some(true): return String(localized: "有")
        case .some(false): return String(localized: "无")
        case .none: return String(localized: "未记录")
        }
    }

    private var lifeStage: LifeStage {
        LifeStage(rawValue: lifeStageRaw) ?? LifeStage.defaultValue
    }

    private var manualCycle: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }

    private var bookmarkedIDs: Set<String> {
        guard !bookmarksData.isEmpty else { return [] }
        return Set(bookmarksData.split(separator: ",").map(String.init))
    }

    private var estimatedPhase: CyclePhase {
        let prediction = CyclePredictor.predict(from: periodDays, manual: manualCycle)
        return PhaseModel.phase(for: day, prediction: prediction,
                                periodDates: Set(periodDays.map { $0.date }))
    }

    private var todayStatusOutput: TodayStatusEngine.Output {
        let phase = estimatedPhase
        return TodayStatusEngine.evaluate(.init(
            date: day,
            phase: phase == .unknown ? nil : StoryPersonalizer.phaseString(from: phase),
            mood: mood?.rawValue,
            energy: energy == 0 ? nil : energy,
            pain: pain < 0 ? nil : pain,
            sleepHours: sleepHours,
            steps: todaysLog?.steps,
            exerciseMinutes: todaysLog?.exerciseMinutes,
            trackerKeys: symptoms,
            isPerimenopause: lifeStage == .perimenopause
        ))
    }

    private var dailyStoryHistory: [String: String] {
        guard let data = dailyStoryHistoryData.data(using: .utf8),
              let history = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return history
    }

    private var recentStoryIDs: [String] {
        dailyStoryHistory
            .sorted { $0.key > $1.key }
            .prefix(4)
            .map(\.value)
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
        Set(loadedIntakes.map(\.medicationId))
    }

    private var todaysLog: DailyLog? {
        let key = DayKey.from(day)
        guard loadedLog?.dayKey == key else { return nil }
        return loadedLog
    }

    /// F4:按当天所处周期阶段匹配的每日一句。
    private var todaysQuote: String {
        DailyQuote.forToday(phase: estimatedPhase, date: day)
    }

    private func refreshDailyStory() {
        let items = EducationCatalog.load()
        guard !items.isEmpty else {
            dailyStoryItem = nil
            return
        }

        let key = String(DayKey.from(day))
        let history = dailyStoryHistory
        if let existingID = history[key],
           let existingItem = items.first(where: { $0.id == existingID }) {
            dailyStoryItem = existingItem
            return
        }

        let phase = estimatedPhase
        let context = StoryPersonalizer.Context(
            items: items,
            date: day,
            trackerKeys: symptoms,
            phase: phase == .unknown ? nil : StoryPersonalizer.phaseString(from: phase),
            isPerimenopause: lifeStage == .perimenopause,
            recentIDs: recentStoryIDs
        )
        guard let selection = StoryPersonalizer.select(from: context) else {
            dailyStoryItem = nil
            return
        }

        dailyStoryItem = selection.item
        var updatedHistory = history
        updatedHistory[key] = selection.item.id
        let recentKeys = updatedHistory.keys.sorted(by: >).prefix(7)
        updatedHistory = updatedHistory.filter { recentKeys.contains($0.key) }
        if let data = try? JSONEncoder().encode(updatedHistory),
           let encoded = String(data: data, encoding: .utf8) {
            dailyStoryHistoryData = encoded
        }
    }

    private func toggleBookmark(_ id: String, currentIsBookmarked: Bool) {
        var set = bookmarkedIDs
        if currentIsBookmarked {
            set.remove(id)
        } else {
            set.insert(id)
        }
        bookmarksData = set.joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    if let focusedDate {
                        Section {
                            HStack {
                                Label(String(localized: "已定位到搜索日期"), systemImage: "scope")
                                Spacer()
                                Text(focusedDate, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        TodayStatusCard(output: todayStatusOutput, phase: estimatedPhase, date: day)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        CompactReviewEntry(periodDays: periodDays, logs: reviewLogs)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    Section {
                        Text(todaysQuote)
                            .font(.callout)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, MarenDesign.spacingS)
                            .listRowBackground(MarenDesign.accentCapsuleFill())
                    }

                    if let story = dailyStoryItem {
                        Section {
                            NavigationLink {
                                StoryReaderView(
                                    item: story,
                                    isBookmarked: bookmarkedIDs.contains(story.id),
                                    onBookmarkToggle: { currentIsBookmarked in
                                        toggleBookmark(story.id, currentIsBookmarked: currentIsBookmarked)
                                    }
                                )
                            } label: {
                                DailyStoryCard(item: story, isBookmarked: bookmarkedIDs.contains(story.id))
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                EducationLibraryView()
                            } label: {
                                Label("更多教育内容", systemImage: "books.vertical")
                            }
                        } header: {
                            Text("每日故事")
                        }
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
                        .onChange(of: day) { _, _ in
                            loadDraftIfNeeded()
                            refreshDailyStory()
                        }
                    }

                    Section("今天心情如何?") {
                        HStack {
                            ForEach(Mood.allCases) { m in
                                MoodChoiceButton(mood: m, selectedMood: $mood)
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
                    .id(Self.screenshotTrackersAnchor)

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

                    Section("基础体温") {
                        Stepper(value: basalBodyTemperatureBinding,
                                in: 33.0...43.0, step: 0.01) {
                            HStack {
                                Text("基础体温")
                                Spacer()
                                Text(basalBodyTemperatureDisplayText)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel(Text("基础体温"))
                        .accessibilityValue(Text(basalBodyTemperatureDisplayText))
                        if basalBodyTemperatureCelsius != nil {
                            Button("清除基础体温记录") { basalBodyTemperatureCelsius = nil }
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("点滴出血") {
                        Picker("点滴出血", selection: $spotting) {
                            Text("未记录").tag(Optional<Bool>.none)
                            Text("无").tag(Optional(false))
                            Text("有").tag(Optional(true))
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(Text("点滴出血"))
                        .accessibilityValue(Text(spottingText))
                        .accessibilityHint(Text("选择未记录、无或有"))
                    }

                    if let savedLog = todaysLog,
                       savedLog.steps != nil || savedLog.exerciseMinutes != nil {
                        Section {
                            if let steps = savedLog.steps {
                                LabeledContent("步数") {
                                    Text(steps.formatted(.number))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let exerciseMinutes = savedLog.exerciseMinutes {
                                LabeledContent("锻炼时间") {
                                    Text(String(localized: "\(exerciseMinutes) 分钟"))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("Apple Health")
                        } footer: {
                            Text("来自 Apple Health 的只读记录")
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
                                                             ? AppTheme.current.accent : .secondary)
                                    }
                                }
                                .accessibilityAddTraits(takenMedIds.contains(med.id) ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }

                    Section("追踪项") {
                        TrackerPickerSection(selected: $symptoms, customTags: customSymptoms.map {
                            SymptomTag(key: $0.key, label: $0.label, emoji: $0.emoji)
                        }, onAdd: { tryAddCustomSymptom() },
                        initialSearchText: focusedTrackerQuery ?? "",
                        initialFocusKey: focusedTrackerKey)
                    }

                    ReproductiveTestSection(selectedKeys: $symptoms)

                    Section("备注") {
                        TextField("想记点什么…", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($noteFocused)
                    }

                    Section {
                        if todaysLog != nil {
                            Button(role: .destructive) {
                                deleteCurrentDayRecord()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text(String(localized: "删除当天记录"))
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.red.opacity(0.1))
                            .disabled(isSaving)
                        }

                        Button {
                            save()
                        } label: {
                            HStack {
                                Spacer()
                                Text(savedFlash ? "已保存 ✓" : (isSaving ? "保存中…" : "保存今天的记录"))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(isSaving)
                        .listRowBackground(AppTheme.current.accent)
                        .foregroundStyle(.white)
                    }
                }
                .navigationTitle("每日记录")
                .navigationBarTitleDisplayMode(.inline)
                // 给底部留出空间,避免最后一行(症状/保存)被浮动标签栏遮住。
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.bottom, 48, for: .scrollContent)
                // 多行备注的回车是换行,不能用来收键盘;这里给一个明确的出口,
                // 否则键盘一直挡着「保存」按钮和底部标签栏。
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            LocalSearchView()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(Text("全局搜索"))
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { noteFocused = false }
                    }
                }
                // 往下拖动即可收键盘(拖到哪收到哪),不用非得点「完成」。
                .scrollDismissesKeyboard(.interactively)
                .sheet(isPresented: $showAddSymptom) {
                    CustomSymptomEditor { label, emoji in
                        let s = CustomSymptom(label: label, emoji: emoji)
                        context.insert(s)
                        if saveContext() {
                            CustomSymptomStore.refresh(context)
                            LocalDataChangeCenter.shared.post(kind: .customTrackerChanged)
                            symptoms.insert(s.key)   // 新建即选中
                            return true
                        }
                        return false
                    }
                }
                .sheet(isPresented: $showPaywall) { PaywallView() }
                .navigationDestination(isPresented: $showLibraryForScreenshot) {
                    EducationLibraryView()
                }
                .alert(alertTitle, isPresented: $showErrorAlert) {
                    Button("好", role: .cancel) { }
                } message: {
                    Text(alertMessage)
                }
                .alert(String(localized: "外部数据更新"), isPresented: $showConflictAlert) {
                    Button(String(localized: "重新加载外部数据")) {
                        if loadDraft(for: day) { loadedDay = day }
                    }
                    Button(String(localized: "保留我的修改"), role: .cancel) {
                        // Keep the original baseline so the draft remains dirty.
                    }
                } message: {
                    Text(String(localized: "有外部更新影响了当前日期的记录。你要重新加载还是保留未保存的修改？"))
                }
                .onAppear {
                    // 跨过午夜后自动跟到新的今天(前提是用户没有手动选过别的日期)。
                    let today = Cal.startOfDay(Date())
                    if !userPickedDate && day != today { day = today }
                    loadDraftIfNeeded()
                    sanitizeDraftAgainstCurrentTrackers()
                    refreshDailyStory()
                }
                .onReceive(dataChangeCenter.$lastEvent.compactMap { $0 }) { event in
                    handleExternalChange(event)
                }
                .onAppear {
                    guard ScreenshotRoute.current == .trackers else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        scrollProxy.scrollTo(Self.screenshotTrackersAnchor, anchor: .top)
                    }
                }
            }
        }
    }

    /// 打卡 / 取消今天的用药。
    private func toggleMed(_ med: Medication) {
        let key = DayKey.from(day)
        let previous = loadedIntakes
        if let existing = loadedIntakes.first(where: { $0.medicationId == med.id }) {
            context.delete(existing)
            loadedIntakes.removeAll { $0 === existing }
        } else {
            let intake = MedicationIntake(medicationId: med.id, dayKey: key)
            context.insert(intake)
            loadedIntakes.append(intake)
        }
        guard saveContext() else {
            loadedIntakes = previous
            return
        }
        LocalDataChangeCenter.shared.post(
            kind: .medicationIntakeChanged,
            affectedDayKeys: [key]
        )
    }

    // MARK: - 草稿加载 / 保存

    /// 只在「目标日期真的换了」时才回填,保护用户未保存的编辑。
    private func loadDraftIfNeeded() {
        guard loadedDay != day else { return }
        if loadDraft(for: day) { loadedDay = day }
    }

    @discardableResult
    private func loadDraft(for date: Date) -> Bool {
        let key = DayKey.from(date)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\DailyLog.updatedAt, order: .reverse)])
        let log: DailyLog?
        let intakesForDay: [MedicationIntake]
        do {
            log = try context.fetch(descriptor).first
            intakesForDay = try context.fetch(FetchDescriptor<MedicationIntake>(
                predicate: #Predicate { $0.dayKey == key }
            ))
        } catch {
            draftLoadFailed = true
            presentAlert(
                title: String(localized: "读取失败"),
                message: "\(String(localized: "这一天的记录暂时无法读取,未清空当前草稿。"))\n\(error.localizedDescription)"
            )
            return false
        }
        draftLoadFailed = false
        loadedLog = log
        loadedIntakes = intakesForDay
        if let log {
            mood = log.mood
            energy = log.energy
            pain = log.pain
            symptoms = Set(log.symptoms)
            sleepHours = log.sleepHours
            weight = log.weight
            basalBodyTemperatureCelsius = log.basalBodyTemperatureCelsius
            spotting = log.spotting
            note = log.note
        } else {
            mood = nil
            energy = 0
            pain = -1
            symptoms = []
            sleepHours = nil
            weight = nil
            basalBodyTemperatureCelsius = nil
            spotting = nil
            note = ""
        }
        lastSnapshot = DraftSnapshot(
            mood: mood, energy: energy, pain: pain,
            symptoms: symptoms, sleepHours: sleepHours,
            weight: weight, basalBodyTemperatureCelsius: basalBodyTemperatureCelsius,
            spotting: spotting, note: note
        )
        return true
    }

    /// A DailyLog screen may be recreated after a custom tracker was deleted.
    /// In that case there is no in-memory event to receive; reconcile the
    /// draft against the current query before allowing another save.
    private func sanitizeDraftAgainstCurrentTrackers() {
        let available = Set(customSymptoms.map(\CustomSymptom.key))
        let sanitized = LocalDataChangeCenter.sanitizeCustomTrackerKeys(
            symptoms,
            availableKeys: available
        )
        guard sanitized != symptoms else { return }
        symptoms = sanitized
        if var baseline = lastSnapshot {
            baseline.symptoms = LocalDataChangeCenter.sanitizeCustomTrackerKeys(
                baseline.symptoms,
                availableKeys: available
            )
            lastSnapshot = baseline
        }
    }

    private func handleExternalChange(_ event: LocalDataChangeCenter.Event) {
        let selectedDayKey = DayKey.from(day)
        switch DailyLogExternalChangePolicy.action(
            for: event,
            selectedDayKey: selectedDayKey,
            draftIsDirty: isDraftDirty
        ) {
        case .reset:
            clearDraft()
            loadedIntakes = []
            loadedDay = day
        case .sanitizeTrackers:
            symptoms.subtract(event.removedCustomTrackerKeys)
            if var baseline = lastSnapshot {
                baseline.symptoms.subtract(event.removedCustomTrackerKeys)
                lastSnapshot = baseline
            }
        case .conflict:
            showConflictAlert = true
        case .reload:
            if loadDraft(for: day) { loadedDay = day }
        case .ignore:
            break
        }
    }

    private func clearDraft() {
        loadedLog = nil
        mood = nil
        energy = 0
        pain = -1
        symptoms = []
        sleepHours = nil
        weight = nil
        basalBodyTemperatureCelsius = nil
        spotting = nil
        note = ""
        lastSnapshot = DraftSnapshot(
            mood: nil, energy: 0, pain: -1, symptoms: [], sleepHours: nil,
            weight: nil, basalBodyTemperatureCelsius: nil, spotting: nil, note: "")
    }

    /// 当前草稿是否有实际内容。空白记录不该落库,否则会污染趋势统计和导出。
    private var draftHasContent: Bool {
        mood != nil || energy != 0 || pain >= 0 || !symptoms.isEmpty
            || sleepHours != nil || weight != nil
            || basalBodyTemperatureCelsius != nil || spotting != nil
            || todaysLog?.steps != nil || todaysLog?.exerciseMinutes != nil
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        // 先收键盘:键盘不收,底部标签栏会一直被系统藏着,用户以为「4 个标签没了」。
        noteFocused = false
        guard !isSaving, !draftLoadFailed else { return }
        // Set this before creating the Task.  Two taps in the same run-loop
        // turn now share the same gate instead of scheduling duplicate saves.
        isSaving = true
        Task { @MainActor in
            await saveDraft()
        }
    }

    @MainActor
    private func saveDraft() async {
        savedFlash = false
        defer { isSaving = false }

        let key = Cal.startOfDay(day)
        let hasContent = draftHasContent
        guard !draftLoadFailed, hasContent || todaysLog != nil else { return }

        var savedLog: DailyLog?
        var deletedDate: Date?

        if let log = todaysLog {
            if hasContent {
                var changedHealthFields = Set<String>()
                if log.sleepHours != sleepHours {
                    changedHealthFields.insert(HealthKitPlanners.FieldKey.sleep.rawValue)
                }
                if log.weight != weight {
                    changedHealthFields.insert(HealthKitPlanners.FieldKey.weight.rawValue)
                }
                if log.basalBodyTemperatureCelsius != basalBodyTemperatureCelsius {
                    changedHealthFields.insert(HealthKitPlanners.FieldKey.basalBodyTemperature.rawValue)
                }
                if log.spotting != spotting {
                    changedHealthFields.insert(HealthKitPlanners.FieldKey.spotting.rawValue)
                }
                log.healthImportedFields.removeAll { changedHealthFields.contains($0) }
                log.mood = mood
                log.energy = energy
                log.pain = pain
                log.symptoms = Array(symptoms).sorted()
                log.sleepHours = sleepHours
                log.weight = weight
                log.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
                log.spotting = spotting
                log.note = note
                log.updatedAt = Date()
                savedLog = log
            } else {
                // 用户把这一天清空了 → 删除整条记录,而不是留一条空壳。
                context.delete(log)
                deletedDate = key
            }
        } else {
            let log = DailyLog(date: key, mood: mood, energy: energy, pain: pain,
                               sleepHours: sleepHours, weight: weight,
                               basalBodyTemperatureCelsius: basalBodyTemperatureCelsius,
                               spotting: spotting,
                               symptoms: Array(symptoms).sorted(), note: note)
            // 新建记录默认没有 HealthKit 导入标记,所有已填字段都是手动值。
            context.insert(log)
            savedLog = log
        }

        guard saveContext() else { return }
        // Only publish the model reference after the transaction commits.
        // Keeping the previous reference through a failed delete, and nil
        // through a failed insert, prevents the next retry from duplicating
        // or losing the selected day's row after `context.rollback()`.
        loadedLog = deletedDate == nil ? savedLog : nil
        loadedDay = day

        // Capture snapshot after successful save for dirty tracking.
        lastSnapshot = DraftSnapshot(
            mood: mood, energy: energy, pain: pain,
            symptoms: symptoms, sleepHours: sleepHours,
            weight: weight, basalBodyTemperatureCelsius: basalBodyTemperatureCelsius,
            spotting: spotting, note: note
        )

        // Notify other active editors after the durable save.
        let dayKey = DayKey.from(day)
        if deletedDate != nil {
            LocalDataChangeCenter.shared.post(kind: .dailyLogDeleted, affectedDayKeys: [dayKey])
        } else {
            LocalDataChangeCenter.shared.post(kind: .dailyLogChanged, affectedDayKeys: [dayKey])
        }

        // Reschedule smart reminders with current data
        rescheduleSmartReminders()

        do {
            let actualPeriodDays = try context.fetch(
                FetchDescriptor<PeriodDay>(sortBy: [SortDescriptor(\PeriodDay.dayKey)])
            )
            let actualLogs = try context.fetch(
                FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\DailyLog.dayKey)])
            )
            WidgetSync.refresh(periodDays: actualPeriodDays, logs: actualLogs)
        } catch {
            presentAlert(
                title: String(localized: "已保存,但小组件刷新失败"),
                message: "\(String(localized: "记录已保存,但未能刷新小组件。"))\n\(error.localizedDescription)"
            )
        }

        withAnimation { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { savedFlash = false }
        }

        // 记一次价值时刻:用户刚成功记录了一天。删除不算。
        // 等"已保存"的闪烁走完再开口,免得盖住保存反馈。
        if deletedDate == nil, ReviewPrompter.recordValueMoment() {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                requestReview()
            }
        }

        guard HealthKitBridge.syncEnabled else { return }
        do {
            if let savedLog {
                try await HealthKitBridge.syncDailyLog(savedLog)
            } else if let deletedDate {
                try await HealthKitBridge.deleteDailySamples(deletedDate)
            }
        } catch {
            let message: String
            if savedLog != nil {
                message = "\(String(localized: "记录已保存,但未能同步到 Apple Health。"))\n\(error.localizedDescription)"
            } else {
                message = "\(String(localized: "记录已删除,但未能从 Apple Health 删除对应样本。"))\n\(error.localizedDescription)"
            }
            presentAlert(title: String(localized: "Apple Health 同步失败"), message: message)
        }
    }

    @discardableResult
    private func saveContext() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            presentAlert(
                title: String(localized: "保存失败"),
                message: "\(String(localized: "这次记录没有保存,原有数据未改动。"))\n\(error.localizedDescription)"
            )
            return false
        }
    }

    private func deleteCurrentDayRecord() {
        guard !isSaving, let log = todaysLog else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            let defaults = UserDefaults.standard
            do {
                try await UserContentDeletion.deleteDailyLog(
                    log,
                    context: context,
                    notificationManager: NotificationManager.shared,
                    dailyEnabled: defaults.bool(forKey: "notif.dailyEnabled"),
                    dailyHour: defaults.object(forKey: "notif.dailyHour") as? Int ?? 21,
                    periodEnabled: defaults.bool(forKey: "notif.periodEnabled"),
                    periodAdvanceDays: defaults.object(forKey: ProReminderSettings.Keys.periodAdvanceDays) as? Int ?? 2,
                    smartEnabled: defaults.bool(forKey: ProReminderSettings.Keys.smartEnabled),
                    pmsEnabled: defaults.bool(forKey: ProReminderSettings.Keys.pmsEnabled),
                    storePremium: store.premium,
                    manualCycle: manualCycle
                )
                clearDraft()
                loadedDay = day
            } catch let deletionError as DeletionError {
                clearDraft()
                loadedDay = day
                switch deletionError {
                case .healthKitSyncFailed(let underlying):
                    presentAlert(
                        title: String(localized: "本机记录已删除"),
                        message: "\(String(localized: "未能从 Apple Health 删除由 Maren 写入的对应样本。"))\n\(underlying.localizedDescription)")
                case .derivedRefreshFailed(let underlying):
                    presentAlert(
                        title: String(localized: "本机记录已删除"),
                        message: "\(String(localized: "本机记录已经删除,但未能刷新提醒或小组件。请重新打开此页面。"))\n\(underlying.localizedDescription)")
                }
            } catch {
                presentAlert(
                    title: String(localized: "删除失败"),
                    message: "\(String(localized: "当天记录没有删除。"))\n\(error.localizedDescription)")
            }
        }
    }

    private func rescheduleSmartReminders() {
        do {
            let actualPeriods = try context.fetch(FetchDescriptor<PeriodDay>())
            let actualLogs = try context.fetch(FetchDescriptor<DailyLog>())
            let prediction = CyclePredictor.predict(from: actualPeriods, manual: manualCycle)
            NotificationManager.shared.scheduleSmartReminders(
                enabled: store.premium && UserDefaults.standard.bool(forKey: ProReminderSettings.Keys.smartEnabled),
                prediction: prediction,
                logs: actualLogs
            )
        } catch {
            presentAlert(
                title: String(localized: "已保存,但提醒刷新失败"),
                message: error.localizedDescription
            )
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showErrorAlert = true
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


// MARK: - 分类追踪项选择器(106 项)

private struct TrackerPickerSection: View {
    @Binding var selected: Set<String>
    var customTags: [SymptomTag] = []
    var onAdd: (() -> Void)? = nil
    let initialSearchText: String
    let initialFocusKey: String?

    @State private var searchText = ""
    /// 分类默认折叠;搜索命中时自动展开对应分类。
    @State private var expandedCategories: Set<TrackerCategory> = []

    init(selected: Binding<Set<String>>,
         customTags: [SymptomTag] = [],
         onAdd: (() -> Void)? = nil,
         initialSearchText: String = "",
         initialFocusKey: String? = nil) {
        self._selected = selected
        self.customTags = customTags
        self.onAdd = onAdd
        self.initialSearchText = initialSearchText
        self.initialFocusKey = initialFocusKey
        _searchText = State(initialValue: initialSearchText)
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchDocuments: [LocalSearchEngine.Document] {
        TrackerCatalog.allEntries.map { entry in
            LocalSearchEngine.Document(
                id: "tracker:\(entry.key)",
                kind: .tracker,
                title: Symptoms.label(for: entry.key),
                subtitle: entry.category.label,
                keywords: [entry.key, entry.category.rawValue]
            )
        } + customTags.map { tag in
            LocalSearchEngine.Document(
                id: "customTracker:\(tag.key)",
                kind: .customTracker,
                title: tag.label,
                subtitle: String(localized: "自定义追踪项"),
                keywords: [tag.key, tag.emoji]
            )
        }
    }

    private var searchResults: [LocalSearchEngine.Result] {
        guard !query.isEmpty else { return [] }
        return LocalSearchEngine.search(searchDocuments, query: query)
    }

    private var searchRanks: [String: Int] {
        Dictionary(uniqueKeysWithValues: searchResults.map { result in
            let key = result.document.id.replacingOccurrences(of: "tracker:", with: "")
                .replacingOccurrences(of: "customTracker:", with: "")
            return (key, result.score)
        })
    }

    /// 搜索命中各分类的 key 集合,用于搜索时自动展开。
    private var searchHitKeys: [TrackerCategory: Set<String>] {
        guard !query.isEmpty else { return [:] }
        var result: [TrackerCategory: Set<String>] = [:]
        for match in searchResults where match.document.kind == .tracker {
            guard let category = TrackerCatalog.categoryByKey[match.document.id.replacingOccurrences(of: "tracker:", with: "")]
            else { continue }
            result[category, default: []].insert(
                match.document.id.replacingOccurrences(of: "tracker:", with: "")
            )
        }
        return result
    }

    private var filteredCustomTags: [SymptomTag] {
        guard !query.isEmpty else { return customTags }
        let matchingKeys = Set(searchResults
            .filter { $0.document.kind == .customTracker }
            .map { $0.document.id.replacingOccurrences(of: "customTracker:", with: "") })
        return customTags
            .filter { matchingKeys.contains($0.key) }
            .sorted { searchRanks[$0.key, default: 0] > searchRanks[$1.key, default: 0] }
    }

    private var filteredCategories: [(TrackerCategory, [SymptomTag])] {
        TrackerCatalog.allCategories.compactMap { cat in
            let all = Symptoms.tags(for: cat)
            let tags: [SymptomTag]
            if query.isEmpty {
                tags = all
            } else {
                let hits = searchHitKeys[cat] ?? []
                tags = all
                    .filter { hits.contains($0.key) }
                    .sorted { searchRanks[$0.key, default: 0] > searchRanks[$1.key, default: 0] }
            }
            return tags.isEmpty ? nil : (cat, tags)
        }
    }

    private var selectedTags: [SymptomTag] {
        let all = (Symptoms.allTags + customTags)
        return selected.compactMap { key in all.first { $0.key == key } }
            .sorted { $0.label < $1.label }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 搜索栏
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "搜索追踪项…"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("清除搜索"))
                }
            }
            .padding(MarenDesign.spacingM)
            .background(MarenDesign.elevatedSurface, in: RoundedRectangle(cornerRadius: MarenDesign.radiusS))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("搜索追踪项"))

            if !initialSearchText.isEmpty && searchText == initialSearchText {
                Label(String(localized: "已定位到追踪项"), systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(AppTheme.current.accent)
                    .accessibilityAddTraits(.isHeader)
            }

            // 已选追踪项
            if !selectedTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "已选 \(selectedTags.count) 项"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(selectedTags) { tag in
                            selectedChip(tag)
                        }
                    }
                }
            }

            // 各分类
            ForEach(filteredCategories, id: \.0) { cat, tags in
                let catVisual = TrackerCatalog.visual(forCategory: cat)
                let selectedInCat = tags.filter { selected.contains($0.key) }.count
                DisclosureGroup(isExpanded: Binding(
                    get: {
                        if !query.isEmpty { return true }
                        return expandedCategories.contains(cat)
                    },
                    set: { if $0 { expandedCategories.insert(cat) } else { expandedCategories.remove(cat) } }
                )) {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(tags) { tag in
                            chip(tag)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: catVisual.symbol)
                            .font(.caption)
                            .foregroundStyle(catVisual.color)
                        Text(cat.label)
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 2)
                        Text("\(selectedInCat)/\(tags.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MarenDesign.accentCapsuleFill(opacity: 0.12), in: Capsule())
                    }
                }
                .padding(.top, 4)
            }

            if !filteredCustomTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "自定义追踪项"))
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 2)
                        Text("\(filteredCustomTags.filter { selected.contains($0.key) }.count)/\(filteredCustomTags.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(filteredCustomTags) { tag in
                            chip(tag)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if !query.isEmpty && filteredCategories.isEmpty && filteredCustomTags.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "没有找到匹配的追踪项"), systemImage: "magnifyingglass")
                } description: {
                    Text(String(localized: "尝试调整搜索词或筛选条件。"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // 添加自定义追踪项
            if let onAdd {
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("自定义").font(.footnote).lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(MarenDesign.elevatedSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .foregroundStyle(.secondary))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("添加自定义追踪项"))
            }
        }
    }

    private func selectedChip(_ tag: SymptomTag) -> some View {
        let isCustom = customTags.contains(where: { $0.key == tag.key })
        let visual = isCustom ? nil : TrackerCatalog.visual(for: tag.key)
        return Button {
            selected.remove(tag.key)
        } label: {
            HStack(spacing: 4) {
                if isCustom {
                    Text(tag.emoji)
                } else if let v = visual {
                    Image(systemName: v.symbol)
                        .font(.footnote)
                        .foregroundStyle(v.color)
                }
                Text(tag.label).font(.footnote).lineLimit(1).fixedSize()
                Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(AppTheme.current.accent.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(AppTheme.current.accent, lineWidth: 1.5))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(tag.label), 已选中, 点按取消选择"))
        .accessibilityAddTraits([.isButton, .isSelected])
    }

    private func chip(_ tag: SymptomTag) -> some View {
        let isOn = selected.contains(tag.key)
        let isCustom = customTags.contains(where: { $0.key == tag.key })
        let visual = isCustom ? nil : TrackerCatalog.visual(for: tag.key)
        return Button {
            if isOn { selected.remove(tag.key) } else { selected.insert(tag.key) }
        } label: {
            HStack(spacing: 4) {
                if isCustom {
                    Text(tag.emoji)
                } else if let v = visual {
                    Image(systemName: v.symbol)
                        .font(.footnote)
                        .foregroundStyle(v.color)
                }
                Text(tag.label)
                    .font(.footnote)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                isOn ? AppTheme.current.accent.opacity(0.18)
                     : Color(.tertiarySystemFill),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    isOn || (initialFocusKey == tag.key && searchText == initialSearchText)
                        ? AppTheme.current.accent
                        : .clear,
                    lineWidth: initialFocusKey == tag.key && searchText == initialSearchText ? 2.5 : 1.5
                )
            )
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tag.label))
        .accessibilityValue(
            initialFocusKey == tag.key && searchText == initialSearchText
                ? Text(String(localized: "已定位到追踪项"))
                : Text(tag.label)
        )
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

private struct MoodChoiceButton: View {
    let mood: Mood
    @Binding var selectedMood: Mood?

    var body: some View {
        Button {
            selectedMood = selectedMood == mood ? nil : mood
        } label: {
            VStack(spacing: 4) {
                Text(mood.emoji)
                    .font(.system(size: 30))
                    .opacity(selectedMood == nil || selectedMood == mood ? 1 : 0.35)
                Text(mood.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(mood.label))
        .accessibilityAddTraits(selectedMood == mood ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    DailyLogView()
        .modelContainer(for: [PeriodDay.self, DailyLog.self], inMemory: true)
}
