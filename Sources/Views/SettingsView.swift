import SwiftUI
import SwiftData
import WidgetKit

/// 设置:提醒通知(F8)+ 隐私说明(强化「本地优先」卖点)。
struct SettingsView: View {
    @StateObject private var notifs = NotificationManager.shared
    @Environment(\.modelContext) private var context
    @Query(sort: \PeriodDay.dayKey) private var periodDays: [PeriodDay]
    @Query private var allLogs: [DailyLog]

    @State private var showDeleteConfirm = false
    @State private var showPCOS = false
    @ObservedObject private var store = Store.shared
    @State private var showPaywall = false
    @State private var showRestoreAlert = false
    @State private var restoreMsg = ""
    @AppStorage("lock.enabled") private var lockEnabled = false
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.rose.rawValue

    // 提醒偏好放在 View 层(@AppStorage 会驱动界面刷新)。
    @AppStorage("notif.dailyEnabled") private var dailyEnabled: Bool = false
    @AppStorage("notif.dailyHour") private var dailyHour: Int = 21
    @AppStorage("notif.periodEnabled") private var periodEnabled: Bool = false
    // Pro 高级提醒偏好(免费层忽略;UI 仅 Premium 可见)。
    @AppStorage(ProReminderSettings.Keys.periodAdvanceDays) private var periodAdvanceDays: Int = 2
    @AppStorage(ProReminderSettings.Keys.pmsEnabled) private var pmsEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.smartEnabled) private var smartEnabled: Bool = false

    // 手动周期设置
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength

    private var prediction: CyclePredictor.Prediction {
        CyclePredictor.predict(from: periodDays, manual: ManualCycle(
            enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength))
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
                    HStack(spacing: 14) {
                        ForEach(AppTheme.allCases) { t in
                            Button {
                                themeRaw = t.rawValue
                            } label: {
                                Circle()
                                    .fill(t.accent)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if themeRaw == t.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
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
                    Button {
                        showPCOS = true
                    } label: {
                        Label("关于 PCOS", systemImage: "heart.text.square")
                    }
                } header: {
                    Text("追踪与提醒")
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
                        Text("在预测经期前 \(periodAdvanceDays) 天提醒你。")
                    } else {
                        Text("在预测经期前 2 天提醒你。升级 Pro 可自定义 1–5 天。")
                    }
                }
                .disabled(!notifs.authorized)

                if store.premium {
                    Section {
                        Toggle("PMS / 黄体期关怀提醒", isOn: $pmsEnabled)
                            .onChange(of: pmsEnabled) { _, _ in reschedule() }
                        Toggle("按周期阶段的智能提醒", isOn: $smartEnabled)
                            .onChange(of: smartEnabled) { _, _ in reschedule() }
                        if smartEnabled,
                           let preview = SmartReminderEngine.preview(prediction: prediction, logs: allLogs) {
                            Text(preview)
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } header: {
                        Text("Pro · 高级提醒")
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
                                    Text("高级提醒(Pro)").font(.subheadline.weight(.semibold))
                                    Text("多时段用药、经期提前天数自定义、PMS 关怀、按阶段智能提醒。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text("Pro · 高级提醒")
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
                            Text("健康数据只存在这台设备上。我们的服务器永不接触,也绝不共享给第三方或用于广告。")
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
                    Text("永久删除本机上的全部经期、每日记录、自定义症状、用药与打卡历史,无法撤销。删除前建议先在「日历」页导出一份备份。")
                }
            }
            .confirmationDialog("确定要删除所有数据吗?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("删除全部记录", role: .destructive) { deleteAllData() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会清空 \(periodDays.count) 条经期记录、\(allLogs.count) 条每日记录,以及全部自定义症状、用药与打卡历史,且无法恢复。")
            }
            .navigationTitle("设置")
            // 给底部留出空间,避免最后一行被浮动标签栏遮住。
            .contentMargins(.bottom, 56, for: .scrollContent)
            .sheet(isPresented: $showPCOS) { PCOSInfoView() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .alert("恢复购买", isPresented: $showRestoreAlert) {
                Button("好") {}
            } message: { Text(restoreMsg) }
            .onAppear { notifs.refreshAuthorization() }
        }
    }

    private func reschedule() {
        notifs.scheduleDailyReminder(enabled: dailyEnabled, hour: dailyHour)
        let advance = store.premium ? periodAdvanceDays : 2
        notifs.schedulePeriodReminder(enabled: periodEnabled, advanceDays: advance, nextPeriodStart: prediction.nextPeriodStart)
        // Pro 高级提醒:免费层强制以 false 传入,确保不残留旧排期。
        notifs.schedulePMSReminder(enabled: store.premium && pmsEnabled, nextPeriodStart: prediction.nextPeriodStart)
        notifs.scheduleSmartReminders(enabled: store.premium && smartEnabled, prediction: prediction, logs: allLogs)
    }

    /// 一键清空本机全部健康数据。「你的数据永远属于你」也包含「随时能全部带走或抹掉」。
    /// 必须删掉全部五个模型,否则用药历史/自定义症状会残留,违反隐私承诺。
    private func deleteAllData() {
        for p in periodDays { context.delete(p) }
        for l in allLogs { context.delete(l) }
        // 用药相关:先撤掉已排期的本地通知,再删库。
        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        for m in meds { NotificationManager.shared.cancelAllMedicationReminders(notificationId: m.notificationId) }
        meds.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<MedicationIntake>()))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<CustomSymptom>()))?.forEach { context.delete($0) }
        try? context.save()
        // 自定义症状快照也要刷新,否则导出/洞察仍用旧显示名。
        CustomSymptomStore.refresh(context)
        // 数据没了,已排期的提醒也必须撤掉,否则会基于旧预测继续弹。
        notifs.schedulePeriodReminder(enabled: periodEnabled, advanceDays: 2, nextPeriodStart: nil)
        notifs.schedulePMSReminder(enabled: false, nextPeriodStart: nil)
        notifs.scheduleSmartReminders(enabled: false, prediction: .empty, logs: [])
        WidgetCenter.shared.reloadAllTimelines()
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
