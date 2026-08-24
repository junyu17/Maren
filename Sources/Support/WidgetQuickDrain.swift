import Foundation
import SwiftData
import WidgetKit

/// 层级 4 · 主 app 侧排空小组件/App Shortcuts 写入的快速操作队列。
///
/// 触发时机:app 启动(VelaApp.init)、切回前台(RootView.scenePhase.active)、
/// Darwin 通知(Maren 已活跃时快速操作入队后立即排空)。
///
/// 关键设计:peek → apply → acknowledge 模式。
/// 仅在 SwiftData context.save() 成功后才从队列中移除条目,
/// 避免崩溃/保存失败时丢失未持久化的条目。
enum WidgetQuickDrain {
    /// 排空并落库。幂等:空队列无操作。
    /// 使用 peek/apply/acknowledge 模式保证崩溃安全:
    /// 1. peek 获取条目快照(不删除);
    /// 2. 转换并调用 QuickLogApplier.applyWithKeys (内含 context.save());
    /// 3. 仅在 save 成功后 acknowledge 移除已处理条目;
    /// 4. 刷新 widget 快照与时间线。
    @MainActor
    static func drainIfNeeded(
        context: ModelContext,
        groupID: String = WidgetSnapshotStore.appGroup,
        defaults: UserDefaults = .standard
    ) {
        let entries = QuickActionQueue.peek(from: groupID)
        guard !entries.isEmpty else { return }

        // 转换为 QuickLog 格式,复用已有的 QuickLogApplier 校验与落库逻辑。
        let logs = entries.compactMap { entry -> QuickLog? in
            switch entry.kind {
            case "period":
                guard let flowRaw = entry.flowRaw else { return nil }
                return QuickLog.period(flowRaw: flowRaw, dayKey: entry.dayKey,
                                       sentAt: entry.createdAt, tzOffsetSeconds: TimeZone.current.secondsFromGMT())
            case "mood":
                guard let moodRaw = entry.moodRaw else { return nil }
                return QuickLog.mood(moodRaw: moodRaw, dayKey: entry.dayKey,
                                     sentAt: entry.createdAt, tzOffsetSeconds: TimeZone.current.secondsFromGMT())
            default:
                return nil
            }
        }

        // Invalid and replay-blocked entries cannot ever become valid by
        // retrying.  Acknowledge them independently so one unrelated
        // persistence failure cannot leave them pending forever.  Valid new
        // entries are acknowledged only after apply successfully saves.
        let discardIDs = Set(entries.compactMap { entry -> UUID? in
            guard let log = quickLog(for: entry) else { return entry.id }
            return QuickLogApplier.shouldDiscard(log, defaults: defaults) ? entry.id : nil
        })

        // applyWithKeys 内部调用 context.save();仅在成功时才 acknowledge
        // 可验证为有效的条目。invalid/replay 条目可以安全丢弃,但有效条目
        // 在保存失败时必须留在队列中等待下一次排空。
        let result = QuickLogApplier.applyWithKeys(logs, context: context, defaults: defaults)
        var idsToAcknowledge = discardIDs
        if result.success {
            let acceptedIDs = entries.compactMap { entry -> UUID? in
                guard let log = quickLog(for: entry),
                      !QuickLogApplier.shouldDiscard(log, defaults: defaults) else { return nil }
                return entry.id
            }
            idsToAcknowledge.formUnion(acceptedIDs)
        }
        if !idsToAcknowledge.isEmpty {
            QuickActionQueue.acknowledge(idsToAcknowledge, from: groupID)
        }

        guard result.success, !result.affectedDayKeys.isEmpty else {
            // 保存失败时保留有效 pending 条目; invalid/replay 条目仍已被
            // 单独确认。刷新时间线让 Widget 能显示 pending 状态。
            refreshSnapshot(context: context)
            return
        }

        let settings = UserDefaults.standard
        do {
            let actual = try UserContentDeletion.refreshAfterMutation(
                context: context,
                notificationManager: NotificationManager.shared,
                dailyEnabled: settings.bool(forKey: "notif.dailyEnabled"),
                dailyHour: settings.object(forKey: "notif.dailyHour") as? Int ?? 21,
                periodEnabled: settings.bool(forKey: "notif.periodEnabled"),
                periodAdvanceDays: settings.object(forKey: ProReminderSettings.Keys.periodAdvanceDays) as? Int ?? 2,
                smartEnabled: settings.bool(forKey: ProReminderSettings.Keys.smartEnabled),
                pmsEnabled: settings.bool(forKey: ProReminderSettings.Keys.pmsEnabled),
                storePremium: Store.shared.premium,
                manualCycle: ManualCycle.current
            )
            LocalDataChangeCenter.shared.post(
                kind: .quickLogApplied,
                affectedDayKeys: result.affectedDayKeys
            )
            // HealthKit is deliberately best-effort: the local quick action is
            // already saved and must remain visible even if Health is locked or
            // temporarily unavailable.
            Task { @MainActor in
                _ = await UserContentDeletion.syncQuickLogHealthBestEffort(
                    affectedDayKeys: result.affectedDayKeys,
                    periodDays: actual.periodDays,
                    logs: actual.logs
                )
            }
        } catch {
            // The model mutation succeeded; WidgetKit still gets a reload and
            // the event still reaches dirty DailyLog editors.  The explicit
            // fallback prevents a fetch failure from being silently ignored.
            LocalDataChangeCenter.shared.post(
                kind: .quickLogApplied,
                affectedDayKeys: result.affectedDayKeys
            )
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func quickLog(for entry: QuickActionEntry) -> QuickLog? {
        switch entry.kind {
        case "period":
            guard let flowRaw = entry.flowRaw else { return nil }
            return QuickLog.period(flowRaw: flowRaw, dayKey: entry.dayKey,
                                   sentAt: entry.createdAt,
                                   tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        case "mood":
            guard let moodRaw = entry.moodRaw else { return nil }
            return QuickLog.mood(moodRaw: moodRaw, dayKey: entry.dayKey,
                                 sentAt: entry.createdAt,
                                 tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        default:
            return nil
        }
    }

    /// 获取最新数据并刷新 widget 快照和时间线。
    /// drain 成功后调用,确保 widget 不显示过期的快照。
    @MainActor
    static func refreshSnapshot(context: ModelContext) {
        do {
            let periodDays = try context.fetch(FetchDescriptor<PeriodDay>())
            let logs = try context.fetch(FetchDescriptor<DailyLog>())
            WidgetSync.refresh(periodDays: periodDays, logs: logs)
        } catch {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
