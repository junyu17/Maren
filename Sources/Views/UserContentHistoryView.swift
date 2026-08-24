import SwiftUI
import SwiftData

/// 层级 2 · 记录与内容管理:所有可删除的用户内容一览,左滑删除。
struct UserContentHistoryView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var notifs = NotificationManager.shared
    @ObservedObject private var store = Store.shared

    @Query(sort: \DailyLog.dayKey, order: .reverse) private var dailyLogs: [DailyLog]
    @Query(sort: \PeriodDay.dayKey, order: .reverse) private var periodDays: [PeriodDay]
    @Query(sort: \MedicationIntake.takenAt, order: .reverse) private var intakes: [MedicationIntake]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]

    @AppStorage("notif.dailyEnabled") private var dailyEnabled: Bool = false
    @AppStorage("notif.dailyHour") private var dailyHour: Int = 21
    @AppStorage("notif.periodEnabled") private var periodEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.periodAdvanceDays) private var periodAdvanceDays: Int = 2
    @AppStorage(ProReminderSettings.Keys.pmsEnabled) private var pmsEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.smartEnabled) private var smartEnabled: Bool = false
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength
    @AppStorage("education.bookmarks") private var bookmarksData = ""
    @AppStorage(ContraceptionSettings.storageKey) private var contraceptionData = Data()

    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showHealthKitWarning = false
    @State private var healthKitWarningMessage = ""

    private var manualCycle: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }

    private var bookmarkedIDs: [String] {
        guard !bookmarksData.isEmpty else { return [] }
        return bookmarksData.split(separator: ",").map(String.init)
    }

    private var contraceptionProfile: ContraceptionSettings? {
        _ = contraceptionData
        let profile = ContraceptionSettings.load()
        return profile.method == .none ? nil : profile
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        List {
            dailyLogsSection
            periodDaysSection
            intakesSection
            bookmarksSection
            contraceptionSection
        }
        .navigationTitle(String(localized: "记录与内容管理"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "删除失败"), isPresented: $showDeleteError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
        .alert(String(localized: "Apple Health 同步"), isPresented: $showHealthKitWarning) {
            Button("好", role: .cancel) {}
        } message: {
            Text(healthKitWarningMessage)
        }
    }

    // MARK: - Section 1: DailyLog

    private var dailyLogsSection: some View {
        Section {
            if dailyLogs.isEmpty {
                Text("暂无每日记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "暂无每日记录"))
            }
            ForEach(dailyLogs) { log in
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.date, formatter: dateFormatter)
                        .font(.subheadline.weight(.medium))
                    Text(dailyLogSummary(log))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(dailyLogAccessibilityLabel(log))
            }
            .onDelete { offsets in
                let toDelete = offsets.map { dailyLogs[$0] }
                Task { @MainActor in
                    for log in toDelete {
                        do {
                            try await UserContentDeletion.deleteDailyLog(
                                log,
                                context: context,
                                notificationManager: notifs,
                                dailyEnabled: dailyEnabled,
                                dailyHour: dailyHour,
                                periodEnabled: periodEnabled,
                                periodAdvanceDays: periodAdvanceDays,
                                smartEnabled: smartEnabled,
                                pmsEnabled: pmsEnabled,
                                storePremium: store.premium,
                                manualCycle: manualCycle
                            )
                        } catch let deletionErr as DeletionError {
                            showDeletionAlert(deletionError: deletionErr)
                        } catch {
                            deleteErrorMessage = error.localizedDescription
                            showDeleteError = true
                            return
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "每日记录"))
        } footer: {
            Text(String(localized: "\(dailyLogs.count) 条每日记录"))
        }
    }

    private func dailyLogSummary(_ log: DailyLog) -> String {
        var parts: [String] = []
        if let mood = log.mood { parts.append(mood.emoji) }
        if log.energy != 0 { parts.append(String(localized: "精力 \(log.energy)")) }
        if log.pain >= 0 { parts.append(String(localized: "痛感 \(log.pain)")) }
        if let h = log.sleepHours { parts.append(String(localized: "睡眠 \(h, specifier: "%.1f")h")) }
        if let w = log.weight { parts.append(String(localized: "体重 \(w, specifier: "%.1f")kg")) }
        if let t = log.basalBodyTemperatureCelsius { parts.append(String(localized: "BBT \(t, specifier: "%.1f")°C")) }
        if log.spotting == true { parts.append(String(localized: "点滴出血")) }
        if !log.symptoms.isEmpty { parts.append(String(localized: "\(log.symptoms.count) 项追踪")) }
        if !log.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(String(localized: "有备注"))
        }
        return parts.isEmpty ? String(localized: "空记录") : parts.joined(separator: " · ")
    }

    private func dailyLogAccessibilityLabel(_ log: DailyLog) -> String {
        let dateStr = log.date.formatted(.dateTime.year().month().day())
        let summary = dailyLogSummary(log)
        return "\(dateStr), \(summary)"
    }

    // MARK: - Section 2: PeriodDay

    private var periodDaysSection: some View {
        Section {
            if periodDays.isEmpty {
                Text("暂无经期记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "暂无经期记录"))
            }
            ForEach(periodDays) { period in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.date, formatter: dateFormatter)
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 6) {
                            Text(period.flow.label)
                            if period.importedFromHealth {
                                Text(String(localized: "来自健康"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(period.flow.dots > 0 ? String(repeating: "●", count: min(period.flow.dots, 3)) : "")
                        .foregroundStyle(period.flow.tint)
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(periodAccessibilityLabel(period))
            }
            .onDelete { offsets in
                let toDelete = offsets.map { periodDays[$0] }
                Task { @MainActor in
                    for period in toDelete {
                        do {
                            try await UserContentDeletion.deletePeriodDay(
                                period,
                                context: context,
                                notificationManager: notifs,
                                dailyEnabled: dailyEnabled,
                                dailyHour: dailyHour,
                                periodEnabled: periodEnabled,
                                periodAdvanceDays: periodAdvanceDays,
                                smartEnabled: smartEnabled,
                                pmsEnabled: pmsEnabled,
                                storePremium: store.premium,
                                manualCycle: manualCycle
                            )
                        } catch let deletionErr as DeletionError {
                            showDeletionAlert(deletionError: deletionErr)
                        } catch {
                            deleteErrorMessage = error.localizedDescription
                            showDeleteError = true
                            return
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "经期记录"))
        } footer: {
            Text(String(localized: "\(periodDays.count) 条经期记录"))
        }
    }

    private func periodAccessibilityLabel(_ period: PeriodDay) -> String {
        let dateStr = period.date.formatted(.dateTime.year().month().day())
        let imported = period.importedFromHealth ? String(localized: ", 来自 Apple 健康") : ""
        return "\(dateStr), \(period.flow.label)\(imported)"
    }

    // MARK: - Section 3: MedicationIntake

    private var intakesSection: some View {
        Section {
            if intakes.isEmpty {
                Text("暂无用药打卡记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "暂无用药打卡记录"))
            }
            ForEach(intakes) { intake in
                VStack(alignment: .leading, spacing: 2) {
                    Text(medicationName(for: intake.medicationId))
                        .font(.subheadline.weight(.medium))
                    Text(DayKey.date(from: intake.dayKey), formatter: dateFormatter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                let toDelete = offsets.map { intakes[$0] }
                for intake in toDelete {
                    do {
                        try UserContentDeletion.deleteMedicationIntake(intake, context: context)
                    } catch {
                        deleteErrorMessage = error.localizedDescription
                        showDeleteError = true
                        return
                    }
                }
            }
        } header: {
            Text(String(localized: "用药打卡"))
        } footer: {
            Text(String(localized: "\(intakes.count) 条打卡记录"))
        }
    }

    private func medicationName(for id: UUID) -> String {
        if let med = medications.first(where: { $0.id == id }) {
            return "\(med.emoji) \(med.name)"
        }
        return String(localized: "已删除的用药")
    }

    // MARK: - Section 4: Education bookmarks

    private var bookmarksSection: some View {
        Section {
            let ids = bookmarkedIDs
            if ids.isEmpty {
                Text("暂无收藏的文章。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "暂无收藏的文章"))
            }
            ForEach(ids, id: \.self) { id in
                if let item = EducationCatalog.load().first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EducationCatalog.localized(item.title))
                            .font(.subheadline.weight(.medium))
                        Text(EducationCatalog.localized(item.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(String(localized: "未知文章"))
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                deleteBookmarks(at: offsets)
            }
        } header: {
            Text(String(localized: "收藏文章"))
        } footer: {
            Text(String(localized: "\(bookmarkedIDs.count) 篇收藏"))
        }
    }

    // MARK: - Section 5: Contraception profile

    private var contraceptionSection: some View {
        Section {
            if let profile = contraceptionProfile {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.method.displayName)
                            .font(.subheadline.weight(.medium))
                        if let dayKey = profile.startDayKey {
                            Text(DayKey.date(from: dayKey), formatter: dateFormatter)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        resetContraception()
                    } label: {
                        Label(String(localized: "重置"), systemImage: "trash")
                    }
                }
            } else {
                Text("未设置避孕记录。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "未设置避孕记录"))
            }
        } header: {
            Text(String(localized: "避孕记录"))
        }
    }

    // MARK: - Delete actions

    private func deleteBookmarks(at offsets: IndexSet) {
        var ids = bookmarkedIDs
        ids.remove(atOffsets: offsets)
        bookmarksData = ids.joined(separator: ",")
    }

    private func resetContraception() {
        ContraceptionSettings.reset()
        notifs.cancelContraceptionDailyReminder()
    }

    private func showHealthKitAlert(deletionError: Error) {
        healthKitWarningMessage = String(localized: "本机记录已删除,但未能同步删除 Apple Health 中的对应样本。请稍后在「健康」App 中手动检查。\n\(deletionError.localizedDescription)")
        showHealthKitWarning = true
    }

    private func showDeletionAlert(deletionError: DeletionError) {
        switch deletionError {
        case .healthKitSyncFailed(let underlying):
            showHealthKitAlert(deletionError: underlying)
        case .derivedRefreshFailed(let underlying):
            deleteErrorMessage = String(localized: "本机记录已经删除,但未能刷新提醒或小组件。请重新打开此页面。\n\(underlying.localizedDescription)")
            showDeleteError = true
        }
    }
}
