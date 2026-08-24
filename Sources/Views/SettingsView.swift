import SwiftUI
import SwiftData
import WidgetKit
import AppIntents

/// 设置:提醒通知(F8)+ 隐私说明(强化「本地优先」卖点)。
struct SettingsView: View {
    @StateObject private var notifs = NotificationManager.shared
    @Environment(\.modelContext) private var context
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query private var allLogs: [DailyLog]

    @State private var showDeleteConfirm = false
    @State private var healthSyncEnabled = HealthKitBridge.syncEnabled
    @State private var healthConnecting = false
    @State private var healthSelectedTypes: Set<HealthKitBridge.SyncType> = HealthKitBridge.selectedTypes
    @State private var showHealthAlert = false
    @State private var healthAlertTitle = ""
    @State private var healthAlertMessage = ""
    @State private var showPCOS = false
    @ObservedObject private var store = Store.shared
    @State private var showPaywall = false
    @State private var showRestoreAlert = false
    @State private var restoreMsg = ""
    @State private var showSampleExperience = false
    @State private var showBackupManager = false
    @AppStorage("lock.enabled") private var lockEnabled = false
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.rose.rawValue
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue
    @AppStorage(AppTextSizePreference.storageKey) private var textSizeRaw = AppTextSizePreference.standard.rawValue
    @AppStorage(NotificationManager.hideSensitiveKey) private var hideSensitiveNotifs = false
    @AppStorage(LifeStage.userDefaultsKey) private var lifeStageRaw = LifeStage.defaultValue.rawValue

    // 提醒偏好放在 View 层(@AppStorage 会驱动界面刷新)。
    @AppStorage("notif.dailyEnabled") private var dailyEnabled: Bool = false
    @AppStorage("notif.dailyHour") private var dailyHour: Int = 21
    @AppStorage("notif.periodEnabled") private var periodEnabled: Bool = false
    // Pro 高级提醒偏好(免费层忽略;UI 仅 Premium 可见)。
    @AppStorage(ProReminderSettings.Keys.periodAdvanceDays) private var periodAdvanceDays: Int = 2
    @AppStorage(ProReminderSettings.Keys.pmsEnabled) private var pmsEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.smartEnabled) private var smartEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.pmsLeadDays) private var pmsLeadDays: Int = 4

    // 手动周期设置
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength

    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: ManualCycle(
            enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength))
    }

    private var healthTypeSummary: String {
        HealthKitBridge.SyncType.localizedTitleList(for: HealthKitBridge.SyncType.allCases)
    }

    private var lifeStageSelection: Binding<LifeStage> {
        Binding(
            get: { LifeStage(rawValue: lifeStageRaw) ?? .cycleTracking },
            set: { lifeStageRaw = $0.rawValue }
        )
    }

    private func healthTypeBinding(_ type: HealthKitBridge.SyncType) -> Binding<Bool> {
        Binding(
            get: { healthSelectedTypes.contains(type) },
            set: { enabled in
                if enabled {
                    healthSelectedTypes.insert(type)
                } else {
                    healthSelectedTypes.remove(type)
                }
            }
        )
    }

    /// 连接 Apple 健康:请求所选类型 → 导入 → 本地保存 → 写回本地手动记录。
    @MainActor
    private func connectHealth() async {
        guard !healthSelectedTypes.isEmpty else {
            presentHealthAlert(
                title: String(localized: "请选择要同步的类型"),
                message: String(localized: "至少选择一种 Apple 健康类型后再继续。")
            )
            return
        }

        healthConnecting = true
        defer { healthConnecting = false }
        let selected = healthSelectedTypes
        HealthKitBridge.selectedTypes = selected

        do {
            try await HealthKitBridge.requestAuthorization(for: selected)
            let payload = try await HealthKitBridge.fetchRecentImports()
            mergeHealthPayload(payload)
            try context.save()
        } catch {
            context.rollback()
            presentHealthAlert(
                title: String(localized: "无法完成 Apple 健康同步"),
                message: "\(String(localized: "未能完成所选类型的请求或读取,本机数据未改动。Apple 健康可能不会向 Maren 暴露读权限是否被拒绝,请在「健康」App 中检查。"))\n\(error.localizedDescription)"
            )
            return
        }

        // 只有本地保存成功后才开启自动同步,并以刚落库的数据做写回。
        HealthKitBridge.syncEnabled = true
        healthSyncEnabled = true
        let actual: (periodDays: [PeriodDay], logs: [DailyLog])
        do {
            actual = try fetchActualData()
            WidgetSync.refresh(periodDays: actual.periodDays, logs: actual.logs)
            UserContentDeletion.rescheduleReminders(
                notificationManager: notifs,
                periodDays: actual.periodDays,
                logs: actual.logs,
                dailyEnabled: dailyEnabled,
                dailyHour: dailyHour,
                periodEnabled: periodEnabled,
                periodAdvanceDays: periodAdvanceDays,
                smartEnabled: smartEnabled,
                pmsEnabled: pmsEnabled,
                storePremium: store.premium,
                manualCycle: ManualCycle.current
            )
            let affectedKeys = Set(actual.periodDays.map(\.dayKey))
                .union(actual.logs.map(\.dayKey))
            LocalDataChangeCenter.shared.post(
                kind: .healthImported,
                affectedDayKeys: affectedKeys
            )
        } catch {
            presentHealthAlert(
                title: String(localized: "本机数据已保存,但刷新失败"),
                message: error.localizedDescription
            )
            return
        }

        do {
            let periodsToExport = selected.contains(.menstrualFlow) ? actual.periodDays : []
            try await HealthKitBridge.exportAll(periodDays: periodsToExport, logs: actual.logs)
        } catch {
            presentHealthAlert(
                title: String(localized: "Apple Health 写回失败"),
                message: "\(String(localized: "本机数据已保存,Apple 健康同步已启用,但未能写回所选的手动记录。请稍后重试。"))\n\(error.localizedDescription)"
            )
        }

    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.premium {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            Text("Maren Premium 已激活")
                            Spacer()
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").foregroundStyle(FlowLevel.medium.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("升级 Maren Premium").font(.subheadline.weight(.semibold))
                                    Text("解锁个性化洞察、高级图表等。").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Button("恢复购买") {
                        Task {
                            await store.restore()
                            restoreMsg = store.premium
                                ? String(localized: "已恢复你的 Premium 权益。")
                                : String(localized: "没有找到可恢复的购买。")
                            showRestoreAlert = true
                        }
                    }
                } header: {
                    Text("Maren Premium")
                } footer: {
                    Text("购买由 Apple 处理,我们不接触你的支付信息,也不接触任何健康数据。")
                }

                Section {
                    Toggle("按我自己的经验设置", isOn: $manualEnabled)
                    if manualEnabled {
                        Stepper(value: $manualCycleLength, in: ManualCycle.cycleRange) {
                            HStack {
                                Text("周期长度")
                                Spacer()
                                Text("\(manualCycleLength) 天").foregroundStyle(.secondary)
                            }
                        }
                        Stepper(value: $manualPeriodLength, in: ManualCycle.periodRange) {
                            HStack {
                                Text("经期天数")
                                Spacer()
                                Text("\(manualPeriodLength) 天").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("我的周期")
                } footer: {
                    Text(manualEnabled
                         ? "预测将按你填的周期推算,只要记录过 1 次经期就能用。关掉后回到自动学习你的真实记录。"
                         : "开启后可自己填周期长度和经期天数;适合周期不规律,或刚开始记录、还没攒够两个周期的时候。")
                }
                .onChange(of: manualEnabled) { _, _ in reschedule() }
                .onChange(of: manualCycleLength) { _, _ in reschedule() }
                .onChange(of: manualPeriodLength) { _, _ in reschedule() }

                Section {
                    Picker(String(localized: "记录视图"), selection: lifeStageSelection) {
                        ForEach(LifeStage.allCases) { stage in
                            Text(stage.label).tag(stage)
                        }
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text(String(localized: "记录视图"))
                } footer: {
                    Text(String(localized: "这是你主动选择的记录视图,仅保存在本机;不会根据记录自动判断。"))
                }

                Section {
                    Picker(String(localized: "显示模式"), selection: $appearanceRaw) {
                        ForEach(AppAppearanceMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .accessibilityLabel(String(localized: "显示模式"))

                    Picker(String(localized: "文字大小"), selection: $textSizeRaw) {
                        ForEach(AppTextSizePreference.allCases, id: \.rawValue) { pref in
                            Text(pref.label).tag(pref.rawValue)
                        }
                    }
                    .accessibilityLabel(String(localized: "文字大小"))
                } header: {
                    Text("外观")
                } footer: {
                    Text("显示模式和文字大小仅影响 Maren,不影响系统设置。")
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(AppTheme.allCases) { t in
                            let locked = !store.premium && t != .rose
                            Button {
                                if locked { showPaywall = true } else {
                                    themeRaw = t.rawValue
                                    WidgetSync.refresh(periodDays: periodDays, logs: allLogs)
                                }
                            } label: {
                                Circle()
                                    .fill(t.accent)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if themeRaw == t.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        } else if locked {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay {
                                        if locked { Circle().stroke(.gray.opacity(0.4), lineWidth: 1) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t.label)
                            .accessibilityAddTraits(themeRaw == t.rawValue ? [.isButton, .isSelected] : .isButton)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("主题")
                } footer: {
                    if store.premium {
                        Text("5 套配色随心换。")
                    } else {
                        Text("默认玫瑰色。升级 Premium 解锁全部 5 套配色。")
                    }
                }

                Section {
                    NavigationLink {
                        MedicationManagerView()
                    } label: {
                        Label("用药与补剂", systemImage: "pills")
                    }
                    NavigationLink {
                        CustomSymptomManagerView()
                    } label: {
                        Label("自定义追踪项", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        ContraceptionManagerView { profile in
                            Task { @MainActor in
                                if profile.method.supportsDailyReminder && profile.reminderEnabled {
                                    await notifs.requestAuthorization()
                                }
                                notifs.schedule(profile: profile)
                            }
                        }
                    } label: {
                        Label(String(localized: "避孕记录"), systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        EducationLibraryView()
                    } label: {
                        Label(String(localized: "知识库"), systemImage: "books.vertical")
                    }
                    NavigationLink {
                        LocalSearchView()
                    } label: {
                        Label(String(localized: "全局搜索"), systemImage: "magnifyingglass")
                    }
                    NavigationLink {
                        UserContentHistoryView()
                    } label: {
                        Label(String(localized: "记录与内容管理"), systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        showPCOS = true
                    } label: {
                        Label("关于 PCOS", systemImage: "heart.text.square")
                    }
                    Button {
                        showSampleExperience = true
                    } label: {
                        Label("样本体验", systemImage: "sparkles.rectangle.stack")
                    }
                } header: {
                    Text("追踪与提醒")
                } footer: {
                    Text("样本体验:浏览示例数据,了解 Maren 的各项功能。不影响你的任何真实记录。")
                }

                Section {
                    Button {
                        showBackupManager = true
                    } label: {
                        Label("手动加密备份", systemImage: "lock.doc")
                    }
                } header: {
                    Text("数据备份")
                } footer: {
                    Text("使用你设置的密码加密全部本机记录。密码无法恢复;备份文件由你选择保存位置。")
                }

                // MARK: - 快速记录
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("快速记录", systemImage: "bolt.fill")
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "无需打开 App 即可记录经期和心情:"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Label(String(localized: "中型交互小组件:长按主屏幕 → ＋ → Maren → 中型"), systemImage: "square.grid.2x2.fill")
                                .font(.caption).foregroundStyle(.primary)
                            Label(String(localized: "两个 Maren 系统快捷指令:\"记录经期\"与\"记录心情\""), systemImage: "shortcuts")
                                .font(.caption).foregroundStyle(.primary)
                            Label(String(localized: "将任一快捷指令分配给 iPhone 操作按钮(设置 → 操作按钮)"), systemImage: "iphone.gen3.radiowaves.left.and.right")
                                .font(.caption).foregroundStyle(.primary)
                        }
                        Text(String(localized: "点击/按下后,条目先入队列;下次打开 Maren 时自动保存到日历。"))
                            .font(.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        ShortcutsLink()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(String(localized: "Open Shortcuts app to manage Maren shortcuts"))
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("快速记录")
                } footer: {
                    Text("所有快速记录均在本地排队,打开 Maren 时落库;不联网、不外传。")
                }

                Section {
                    if notifs.authorized {
                        Label("通知已开启", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if notifs.denied {
                        // 已被拒绝时系统不会再弹窗,直接给一条能走通的路:跳系统设置。
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("去系统设置开启通知", systemImage: "gear")
                        }
                    } else {
                        Button {
                            Task {
                                await notifs.requestAuthorization()
                                reschedule()
                            }
                        } label: {
                            Label("开启通知权限", systemImage: "bell.badge")
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("提醒都在你的设备本地生成,不经过任何服务器。")
                }

                Section {
                    Toggle("锁屏隐藏提醒内容", isOn: $hideSensitiveNotifs)
                        .onChange(of: hideSensitiveNotifs) { _, newValue in
                            NotificationManager.hideSensitiveContent = newValue
                            reschedule()  // 用新偏好重排,让已排期的通知立即生效
                        }
                } footer: {
                    Text("开启后,经期 / 关怀类提醒在锁屏上只显示「打开 Maren 查看提醒」,不显示经期、黄体期等敏感信息。")
                }

                Section {
                    Toggle("每日记录提醒", isOn: $dailyEnabled)
                        .onChange(of: dailyEnabled) { _, _ in reschedule() }
                    if dailyEnabled {
                        Picker("提醒时间", selection: $dailyHour) {
                            ForEach(6...23, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .onChange(of: dailyHour) { _, _ in reschedule() }
                    }
                }
                .disabled(!notifs.authorized)

                Section {
                    Toggle("经期临近提醒", isOn: $periodEnabled)
                        .onChange(of: periodEnabled) { _, _ in reschedule() }
                    if periodEnabled && store.premium {
                        Stepper(value: $periodAdvanceDays, in: ProReminderSettings.advanceRange) {
                            HStack {
                                Text("提前提醒天数")
                                Spacer()
                                Text("\(periodAdvanceDays) 天").foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: periodAdvanceDays) { _, _ in reschedule() }
                    }
                } footer: {
                    if periodEnabled && store.premium {
                        Text(String(localized: "在预测经期前 \(periodAdvanceDays) 天提醒你。"))
                    } else {
                        Text("在预测经期前 2 天提醒你。升级 Premium 可自定义 1–5 天。")
                    }
                }
                .disabled(!notifs.authorized)

                if store.premium {
                    Section {
                        Toggle("PMS / 黄体期关怀提醒", isOn: $pmsEnabled)
                            .onChange(of: pmsEnabled) { _, _ in reschedule() }
                        if pmsEnabled {
                            Stepper(value: $pmsLeadDays, in: 1...7) {
                                HStack {
                                    Text("PMS 提前几天")
                                    Spacer()
                                    Text("\(pmsLeadDays) 天").foregroundStyle(.secondary)
                                }
                            }
                            .onChange(of: pmsLeadDays) { _, _ in reschedule() }
                        }
                        Toggle("按周期阶段的智能提醒", isOn: $smartEnabled)
                            .onChange(of: smartEnabled) { _, _ in reschedule() }
                        if smartEnabled,
                           let preview = SmartReminderEngine.preview(prediction: prediction, logs: allLogs) {
                            Text(preview)
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } header: {
                        Text("Premium · 高级提醒")
                    } footer: {
                        Text("PMS:经期前几天给你一条「对自己好点」的提醒。智能提醒:进入黄体期时,根据你自己的记录提醒你(如「焦虑常在黄体期升高」)。")
                    }
                    .disabled(!notifs.authorized)
                } else {
                    Section {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.badge.fill").foregroundStyle(FlowLevel.medium.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("高级提醒").font(.subheadline.weight(.semibold))
                                    Text("多时段用药、经期提前天数自定义、PMS 关怀、按阶段智能提醒。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text("Premium · 高级提醒")
                    }
                }

                if HealthKitBridge.isAvailable {
                    Section {
                        ForEach(HealthKitBridge.SyncType.allCases) { type in
                            Toggle(isOn: healthTypeBinding(type)) {
                                HStack(spacing: 8) {
                                    Text(type.title)
                                    if !type.isWritable {
                                        Text(String(localized: "只读"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if healthSyncEnabled {
                            Label("Apple 健康同步已启用", systemImage: "heart.fill")
                                .foregroundStyle(.pink)
                            Button("重新请求并同步") {
                                Task { await connectHealth() }
                            }
                            .disabled(healthConnecting || healthSelectedTypes.isEmpty)
                            Button("停止自动同步") {
                                healthSyncEnabled = false
                                HealthKitBridge.syncEnabled = false
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await connectHealth() }
                            } label: {
                                Label(healthConnecting ? String(localized: "请求中…") : String(localized: "请求所选类型并同步"),
                                      systemImage: "heart.text.square")
                            }
                            .disabled(healthConnecting || healthSelectedTypes.isEmpty)
                        }
                    } header: {
                        Text("Apple 健康")
                    } footer: {
                        Text("支持类型:\(healthTypeSummary)。睡眠、步数和锻炼时间为只读;每个选中的类型都会在请求时一并申请。Apple 健康不会向 Maren 暴露读权限是否被拒绝,请在「健康」App 中管理权限。数据只在本机与 Apple 健康之间流转,不经过开发者服务器。停止自动同步只会停止后续自动读写,不会替你撤销 Apple 健康权限或删除数据。")
                    }
                }

                Section {
                    Toggle(isOn: $lockEnabled) {
                        Label("Face ID / 密码锁", systemImage: "faceid")
                    }
                    HStack {
                        Image(systemName: "lock.shield.fill").foregroundStyle(FlowLevel.medium.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("你的数据永远属于你").font(.subheadline.weight(.semibold))
                            Text("Maren 本地记录只存在这台设备上;使用 Apple 健康或配对 Apple Watch 时,相关数据由 Apple 功能按你的选择处理。我们的服务器永不接触,也绝不用于广告。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("隐私")
                } footer: {
                    Text("开启后,每次打开 Maren 都需要 Face ID、Touch ID 或设备密码。")
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除所有数据", systemImage: "trash")
                    }
                } footer: {
                    Text("永久删除本机上的全部经期、每日记录、自定义追踪项、用药与打卡历史,无法撤销。删除前建议先在「日历」页导出一份备份。")
                }
            }
            .confirmationDialog("确定要删除所有数据吗?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("删除全部记录", role: .destructive) {
                    Task { await deleteAllData() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(String(localized: "这会永久清空 \(periodDays.count) 条经期记录、\(allLogs.count) 条每日记录、全部自定义追踪项及其历史、用药定义与打卡历史,取消 Maren 的本机提醒,同时清除设置中的记录视图/周期参数、Widget 与 Apple Watch 快照和待处理快速记录。Maren 不会删除 Apple 健康中来自其他来源的数据;由 Maren 写入的样本会在本机删除后另行尝试清理。此操作无法恢复。"))
            }
            .navigationTitle("设置")
            // 给底部留出空间,避免最后一行被浮动标签栏遮住。
            .contentMargins(.bottom, 56, for: .scrollContent)
            .sheet(isPresented: $showPCOS) { PCOSInfoView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showSampleExperience) { SampleExperienceView() }
            .sheet(isPresented: $showBackupManager) { BackupManagerView() }
            .alert("恢复购买", isPresented: $showRestoreAlert) {
                Button("好") {}
            } message: { Text(restoreMsg) }
            .alert(healthAlertTitle, isPresented: $showHealthAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text(healthAlertMessage)
            }
            .onAppear {
                notifs.refreshAuthorization()
                healthSyncEnabled = HealthKitBridge.syncEnabled
                healthSelectedTypes = HealthKitBridge.selectedTypes
            }
        }
    }

    private func reschedule() {
        notifs.scheduleDailyReminder(enabled: dailyEnabled, hour: dailyHour)
        let advance = store.premium ? periodAdvanceDays : 2
        notifs.schedulePeriodReminder(enabled: periodEnabled, advanceDays: advance, nextPeriodStart: prediction.nextPeriodStart)
        // Pro 高级提醒:免费层强制以 false 传入,确保不残留旧排期。
        notifs.schedulePMSReminder(enabled: store.premium && pmsEnabled, nextPeriodStart: prediction.nextPeriodStart)
        notifs.scheduleSmartReminders(enabled: store.premium && smartEnabled, prediction: prediction, logs: allLogs)

        // Manual cycle settings are not SwiftData rows, so refresh the
        // derived Widget/Watch snapshot explicitly after every change. The
        // analysis screens observe the same @AppStorage keys and recompute in
        // the same render pass.
        do {
            let actual = try fetchActualData()
            WidgetSync.refresh(periodDays: actual.periodDays, logs: actual.logs)
        } catch {
            presentHealthAlert(
                title: String(localized: "周期设置已保存,但刷新失败"),
                message: "\(String(localized: "提醒设置已经更新,但未能刷新 Widget 和 Apple Watch。请重新打开 Maren。"))\n\(error.localizedDescription)"
            )
        }
    }

    private func mergeHealthPayload(_ payload: HealthKitBridge.ImportPayload) {
        var periodsByKey = Dictionary(uniqueKeysWithValues: periodDays.map { ($0.dayKey, $0) })
        for imported in payload.periods {
            if let existing = periodsByKey[imported.dayKey] {
                // 手动记录优先;只有原本来自 Health 的记录才允许被新的导入更新。
                guard existing.importedFromHealth else { continue }
                existing.flow = imported.flow
                existing.updatedAt = Date()
            } else {
                let importedDay = PeriodDay(date: DayKey.date(from: imported.dayKey), flow: imported.flow)
                importedDay.importedFromHealth = true
                context.insert(importedDay)
                periodsByKey[imported.dayKey] = importedDay
            }
        }

        var logsByKey = Dictionary(uniqueKeysWithValues: allLogs.map { ($0.dayKey, $0) })
        for imported in payload.daily {
            let hasActualValue = imported.sleepHours != nil
                || imported.weight != nil
                || imported.basalBodyTemperatureCelsius != nil
                || imported.spotting != nil
                || imported.steps != nil
                || imported.exerciseMinutes != nil
            guard hasActualValue else { continue }

            if let existing = logsByKey[imported.dayKey] {
                var markers = Set(existing.healthImportedFields)
                var importedFields = Set(markers.compactMap(HealthKitPlanners.FieldKey.init(rawValue:)))
                var didUpdate = false

                if let value = imported.sleepHours,
                   HealthKitPlanners.shouldImportField(
                       localValueIsRecorded: existing.sleepHours != nil,
                       importedFields: importedFields,
                       field: .sleep
                   ) {
                    existing.sleepHours = value
                    markers.insert(HealthKitPlanners.FieldKey.sleep.rawValue)
                    importedFields.insert(.sleep)
                    didUpdate = true
                }
                if let value = imported.weight,
                   HealthKitPlanners.shouldImportField(
                       localValueIsRecorded: existing.weight != nil,
                       importedFields: importedFields,
                       field: .weight
                   ) {
                    existing.weight = value
                    markers.insert(HealthKitPlanners.FieldKey.weight.rawValue)
                    importedFields.insert(.weight)
                    didUpdate = true
                }
                if let value = imported.basalBodyTemperatureCelsius,
                   HealthKitPlanners.shouldImportField(
                       localValueIsRecorded: existing.basalBodyTemperatureCelsius != nil,
                       importedFields: importedFields,
                       field: .basalBodyTemperature
                   ) {
                    existing.basalBodyTemperatureCelsius = value
                    markers.insert(HealthKitPlanners.FieldKey.basalBodyTemperature.rawValue)
                    importedFields.insert(.basalBodyTemperature)
                    didUpdate = true
                }
                if let value = imported.spotting,
                   HealthKitPlanners.shouldImportField(
                       localValueIsRecorded: existing.spotting != nil,
                       importedFields: importedFields,
                       field: .spotting
                   ) {
                    existing.spotting = value
                    markers.insert(HealthKitPlanners.FieldKey.spotting.rawValue)
                    importedFields.insert(.spotting)
                    didUpdate = true
                }
                if let value = imported.steps,
                   HealthKitPlanners.shouldImportField(
                       localValueIsRecorded: existing.steps != nil,
                       importedFields: importedFields,
                       field: .steps
                   ) {
                    existing.steps = value
                    markers.insert(HealthKitPlanners.FieldKey.steps.rawValue)
                    importedFields.insert(.steps)
                    didUpdate = true
                }
                if let value = imported.exerciseMinutes,
                   HealthKitPlanners.shouldImportField(
                       localValueIsRecorded: existing.exerciseMinutes != nil,
                       importedFields: importedFields,
                       field: .exercise
                   ) {
                    existing.exerciseMinutes = value
                    markers.insert(HealthKitPlanners.FieldKey.exercise.rawValue)
                    importedFields.insert(.exercise)
                    didUpdate = true
                }

                if didUpdate {
                    existing.healthImportedFields = markers.sorted()
                    existing.updatedAt = Date()
                }
            } else {
                let importedLog = DailyLog(
                    date: DayKey.date(from: imported.dayKey),
                    sleepHours: imported.sleepHours,
                    weight: imported.weight,
                    steps: imported.steps,
                    exerciseMinutes: imported.exerciseMinutes,
                    basalBodyTemperatureCelsius: imported.basalBodyTemperatureCelsius,
                    spotting: imported.spotting
                )
                var markers = Set<String>()
                if imported.sleepHours != nil {
                    markers.insert(HealthKitPlanners.FieldKey.sleep.rawValue)
                }
                if imported.weight != nil {
                    markers.insert(HealthKitPlanners.FieldKey.weight.rawValue)
                }
                if imported.basalBodyTemperatureCelsius != nil {
                    markers.insert(HealthKitPlanners.FieldKey.basalBodyTemperature.rawValue)
                }
                if imported.spotting != nil {
                    markers.insert(HealthKitPlanners.FieldKey.spotting.rawValue)
                }
                if imported.steps != nil {
                    markers.insert(HealthKitPlanners.FieldKey.steps.rawValue)
                }
                if imported.exerciseMinutes != nil {
                    markers.insert(HealthKitPlanners.FieldKey.exercise.rawValue)
                }
                importedLog.healthImportedFields = markers.sorted()
                context.insert(importedLog)
                logsByKey[imported.dayKey] = importedLog
            }
        }
    }

    private func fetchActualData() throws -> (periodDays: [PeriodDay], logs: [DailyLog]) {
        let actualPeriodDays = try context.fetch(
            FetchDescriptor<PeriodDay>(sortBy: [SortDescriptor(\PeriodDay.dayKey)])
        )
        let actualLogs = try context.fetch(
            FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\DailyLog.dayKey)])
        )
        return (actualPeriodDays, actualLogs)
    }

    private func presentHealthAlert(title: String, message: String) {
        healthAlertTitle = title
        healthAlertMessage = message
        showHealthAlert = true
    }

    /// 一键清空本机全部健康数据。「你的数据永远属于你」也包含「随时能全部带走或抹掉」。
    /// 必须删掉全部五个模型,否则用药历史/自定义症状会残留,违反隐私承诺。
    private func deleteAllData() async {
        let medicationNotificationIds: [String]
        do {
            let periods = try context.fetch(FetchDescriptor<PeriodDay>())
            let logs = try context.fetch(FetchDescriptor<DailyLog>())
            let meds = try context.fetch(FetchDescriptor<Medication>())
            let intakes = try context.fetch(FetchDescriptor<MedicationIntake>())
            let customSymptoms = try context.fetch(FetchDescriptor<CustomSymptom>())
            medicationNotificationIds = meds.map(\.notificationId)

            for period in periods { context.delete(period) }
            for log in logs { context.delete(log) }
            for medication in meds { context.delete(medication) }
            for intake in intakes { context.delete(intake) }
            for customSymptom in customSymptoms { context.delete(customSymptom) }
            try context.save()
        } catch {
            context.rollback()
            presentHealthAlert(
                title: String(localized: "删除失败"),
                message: "\(String(localized: "本机数据没有删除,原有记录未改动。"))\n\(error.localizedDescription)"
            )
            return
        }

        // Reset local preferences only after the model deletion has been
        // durably saved. The notification is cancelled independently so an
        // old contraception reminder cannot survive the data wipe.
        ContraceptionSettings.reset()
        LifeStage.save(.defaultValue)
        lifeStageRaw = LifeStage.defaultValue.rawValue
        UserDefaults.standard.removeObject(forKey: "education.bookmarks")
        UserDefaults.standard.removeObject(forKey: "education.dailyStoryHistory")
        notifs.cancelContraceptionDailyReminder()

        // The five local models are now durably deleted.  Persist a fresh
        // reset epoch/cutoff before any derived refresh, clear the iPhone
        // queue, cancel our own outstanding WC user-info transfers, and send
        // the epoch to the Watch so it can clear its private outbox/recent
        // cache/App Group queue.  The receiver-side cutoff remains the final
        // compatibility barrier for older Watch builds.
        let watchReset = PhoneConnectivity.shared.resetWatchState()
        if !watchReset.cleanupSucceeded {
            presentHealthAlert(
                title: String(localized: "本机数据已删除"),
                message: String(localized: "快速记录的清理将在下次打开 Maren 时重试。已删除的本机记录不会恢复。")
            )
        }

        // Disable automatic Health imports immediately after local deletion,
        // before attempting the best-effort HealthKit sample cleanup.  This
        // prevents a later background sync from resurrecting deleted records.
        HealthKitBridge.syncEnabled = false
        healthSyncEnabled = false

        // 本地保存成功后,再撤掉已排期的本地通知。
        for notificationId in medicationNotificationIds {
            NotificationManager.shared.cancelAllMedicationReminders(notificationId: notificationId)
        }
        notifs.cancelAllAppNotifications()
        // 自定义症状快照也要刷新,否则导出/洞察仍用旧显示名。
        CustomSymptomStore.refresh(context)
        // 数据没了,已排期的提醒也必须撤掉,否则会基于旧预测继续弹。
        notifs.schedulePeriodReminder(enabled: periodEnabled, advanceDays: 2, nextPeriodStart: nil)
        notifs.schedulePMSReminder(enabled: false, nextPeriodStart: nil)
        notifs.scheduleSmartReminders(enabled: false, prediction: .empty, logs: [])
        // 手动周期设置也算「数据」:不重置的话,删除后 widget/趋势仍会基于
        // 手动周期参数显示预测,与「删除所有数据」语义不符。
        UserDefaults.standard.set(false, forKey: ManualCycle.Keys.enabled)
        UserDefaults.standard.removeObject(forKey: ManualCycle.Keys.cycleLength)
        UserDefaults.standard.removeObject(forKey: ManualCycle.Keys.periodLength)
        // 关键:把 widget 快照覆写为占位(不残留任何健康信息),并重推手表。
        // 只 reloadAllTimelines 不够 —— timeline 仍会从 App Group 旧快照读出已删除的数据。
        WidgetSnapshotStore.write(.placeholder)
        WidgetCenter.shared.reloadAllTimelines()
        PhoneConnectivity.shared.push(.placeholder)

        // Local deletion is already complete; update active screens before
        // the best-effort HealthKit cleanup potentially takes time.
        LocalDataChangeCenter.shared.post(kind: .storeReset)

        // 本机数据已成功删除后,才清理本 app 写入的 HealthKit 样本。
        if HealthKitBridge.isAvailable {
            do {
                let result = try await HealthKitBridge.deleteAllMarenSamples()
                if !result.isComplete {
                    presentHealthAlert(
                        title: String(localized: "本机数据已删除,Apple Health 部分清理"),
                        message: result.userFacingIssueDescription
                    )
                }
            } catch {
                presentHealthAlert(
                    title: String(localized: "本机数据已删除,但 Apple Health 清理失败"),
                    message: "\(String(localized: "本机记录已经删除,但未能删除 Apple Health 中由 Maren 写入的样本。你可以在稍后重试,其他来源的 Health 数据不会被删除。"))\n\(error.localizedDescription)"
                )
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        var comps = DateComponents(); comps.hour = h; comps.minute = 0
        let date = Cal.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
