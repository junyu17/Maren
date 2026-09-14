import SwiftUI
import SwiftData

/// 层级 2 · 自定义追踪项管理(增删)。新增在「今天」页的症状区就地进行,这里主要负责删除/查看。
struct CustomSymptomManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomSymptom.createdAt) private var items: [CustomSymptom]
    /// `DailyLog.symptoms` is a SwiftData transformable `[String]`. SwiftData
    /// can compile a `#Predicate` using `contains`, but evaluating that
    /// predicate against the transformable column crashes on iOS 26. Keep
    /// this all-history fetch for the exact usage-count semantics instead of
    /// trading a performance hint for a data-screen crash.
    @Query private var logs: [DailyLog]
    @State private var showAdd = false
    @State private var editing: CustomSymptom?
    @State private var showPaywall = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var mutationErrorTitle = ""
    @ObservedObject private var store = Store.shared
    @StateObject private var notifs = NotificationManager.shared

    @AppStorage("notif.dailyEnabled") private var dailyEnabled: Bool = false
    @AppStorage("notif.dailyHour") private var dailyHour: Int = 21
    @AppStorage("notif.periodEnabled") private var periodEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.periodAdvanceDays) private var periodAdvanceDays: Int = 2
    @AppStorage(ProReminderSettings.Keys.pmsEnabled) private var pmsEnabled: Bool = false
    @AppStorage(ProReminderSettings.Keys.smartEnabled) private var smartEnabled: Bool = false
    @AppStorage(ManualCycle.Keys.enabled) private var manualEnabled = false
    @AppStorage(ManualCycle.Keys.cycleLength) private var manualCycleLength = ManualCycle.defaultCycleLength
    @AppStorage(ManualCycle.Keys.periodLength) private var manualPeriodLength = ManualCycle.defaultPeriodLength

    private var manualCycle: ManualCycle {
        ManualCycle(enabled: manualEnabled, cycleLength: manualCycleLength, periodLength: manualPeriodLength)
    }

    /// symptom key -> 被打卡次数。
    private var useCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for log in logs {
            for key in log.symptoms { counts[key, default: 0] += 1 }
        }
        return counts
    }

    var body: some View {
        List {
            Section {
                if items.isEmpty {
                    Text("你还没有自定义追踪项。可以在「今天」页的「症状与追踪项」区点「＋ 自定义」添加,也可以点右上角「＋」。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button { editing = item } label: {
                        HStack {
                            Text(item.emoji)
                            Text(item.label).foregroundStyle(.primary)
                            Spacer()
                            let count = useCounts[item.key] ?? 0
                            Text(count == 0
                                 ? String(localized: "还没记录过")
                                 : String(localized: "已记录 \(count) 次"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete(perform: delete)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自定义项会排在「今天」页「症状与追踪项」区的最后,和内置症状一样打勾。记录会写进导出文件,并计入「趋势」的追踪项频次与洞察(Premium)。")
                    if !store.premium {
                        Text(String(localized: "免费最多 \(CustomSymptom.freeLimit) 个自定义项,Premium 无限。已达上限时点「＋」升级。"))
                    }
                }
            }
        }
        .navigationTitle("自定义追踪项")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tryAdd() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("添加自定义追踪项")
            }
        }
        .sheet(isPresented: $showAdd) {
            CustomSymptomEditor(existing: nil) { label, emoji in
                saveCustomSymptom(nil, label: label, emoji: emoji)
            }
        }
        .sheet(item: $editing) { item in
            CustomSymptomEditor(existing: item) { label, emoji in
                saveCustomSymptom(item, label: label, emoji: emoji)
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert(mutationErrorTitle, isPresented: $showDeleteError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
    }

    private func delete(_ offsets: IndexSet) {
        let toDelete = offsets.map { items[$0] }
        for item in toDelete {
            do {
                try UserContentDeletion.deleteCustomTracker(
                    item,
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
            } catch let deletionError as DeletionError {
                mutationErrorTitle = String(localized: "自定义追踪项已删除")
                switch deletionError {
                case .healthKitSyncFailed(let underlying):
                    deleteErrorMessage = String(localized: "本机记录已经删除,但 Apple Health 同步未完成。请稍后重试。\n\(underlying.localizedDescription)")
                case .derivedRefreshFailed(let underlying):
                    deleteErrorMessage = String(localized: "本机记录已经删除,但未能刷新提醒或小组件。请重新打开此页面。\n\(underlying.localizedDescription)")
                }
                showDeleteError = true
            } catch {
                mutationErrorTitle = String(localized: "删除失败")
                deleteErrorMessage = error.localizedDescription
                showDeleteError = true
                return
            }
        }
    }

    /// Saves in place for edits so `key` remains stable and historical
    /// DailyLog.symptoms references continue to resolve to the renamed item.
    /// Returning false keeps the editor presented after a save failure.
    private func saveCustomSymptom(
        _ existing: CustomSymptom?,
        label: String,
        emoji: String
    ) -> Bool {
        if let existing {
            do {
                try UserContentDeletion.updateCustomTracker(
                    existing,
                    label: label,
                    emoji: emoji,
                    context: context
                )
                return true
            } catch {
                mutationErrorTitle = String(localized: "保存失败")
                deleteErrorMessage = error.localizedDescription
                showDeleteError = true
                return false
            }
        } else {
            context.insert(CustomSymptom(label: label, emoji: emoji))
        }

        do {
            try context.save()
            CustomSymptomStore.refresh(context)
            LocalDataChangeCenter.shared.post(kind: .customTrackerChanged)
            return true
        } catch {
            context.rollback()
            mutationErrorTitle = String(localized: "保存失败")
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
            return false
        }
    }

    /// 添加:免费层达上限弹付费墙,Pro 无限。
    private func tryAdd() {
        if !store.premium && items.count >= CustomSymptom.freeLimit {
            showPaywall = true
        } else {
            showAdd = true
        }
    }
}
