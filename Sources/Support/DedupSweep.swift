import Foundation
import SwiftData

/// CloudKit 多端同步去重 sweep。
///
/// **问题**:CloudKit 镜像会**直接插入**远端记录,绕过 app 的「先查后写」去重。两台设备在
/// 同步传播前各自写入同一天(dayKey),同步后就会出现两条同 dayKey 记录。单人串行使用基本
/// 不触发;真发生时**显示层会折叠**(`CalendarView.periodByDay` 字典按天取一、`DailyLogView`
/// 的 `logs.first`),但 DB 里会残留重复记录,久了会累积。
///
/// **本 sweep**:启动时跑一次,把同 dayKey/key 的多余记录真正删除(删除经 CloudKit 镜像同步到
/// 其他设备,全网清理)。无重复时是 no-op(不写库)。DailyLog 做字段级合并,避免丢数据。
///
/// 限定 dayKey/key 类模型:`PeriodDay` / `DailyLog` / `MedicationIntake`。
/// `CustomSymptom` / `Medication` 的键是 UUID(创建即全局唯一),不会产生跨设备同键重复,不处理。
enum DedupSweep {

    /// 启动去重。在 `VelaApp.init` 容器建好后调用一次。
    static func run(in container: ModelContainer) {
        let context = ModelContext(container)
        var changed = false
        changed = dedupPeriodDays(context: context) || changed
        changed = dedupDailyLogs(context: context) || changed
        changed = dedupMedicationIntakes(context: context) || changed
        if changed {
            try? context.save()
            #if DEBUG
            print("[DedupSweep] 合并了重复记录")
            #endif
        }
    }

    // MARK: - PeriodDay(同 dayKey 保留 createdAt 最新的一条)

    private static func dedupPeriodDays(context: ModelContext) -> Bool {
        guard let all = try? context.fetch(FetchDescriptor<PeriodDay>()) else { return false }
        return collapse(all, key: { $0.dayKey }, date: { $0.createdAt }, context: context)
    }

    // MARK: - MedicationIntake(同 key=medId-dayKey 保留一条)

    private static func dedupMedicationIntakes(context: ModelContext) -> Bool {
        guard let all = try? context.fetch(FetchDescriptor<MedicationIntake>()) else { return false }
        return collapse(all, key: { $0.key }, date: { $0.takenAt }, context: context)
    }

    /// 通用「同 key 保留一条」折叠:保留 date 最新者(稳定 tiebreak 用持久 ID),删其余。
    private static func collapse<T: PersistentModel>(_ records: [T],
                                                     key: (T) -> some Hashable,
                                                     date: (T) -> Date,
                                                     context: ModelContext) -> Bool {
        let groups = Dictionary(grouping: records, by: key)
        var deleted = false
        for (_, group) in groups where group.count > 1 {
            let winner = group.sorted {
                let a = date($0), b = date($1)
                if a != b { return a > b }
                return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
            }.first!
            for r in group where r !== winner {
                context.delete(r)
                deleted = true
            }
        }
        return deleted
    }

    // MARK: - DailyLog(同 dayKey 合并字段后保留一条)

    private static func dedupDailyLogs(context: ModelContext) -> Bool {
        guard let all = try? context.fetch(FetchDescriptor<DailyLog>()) else { return false }
        let groups = Dictionary(grouping: all, by: { $0.dayKey })
        var deleted = false
        for (_, group) in groups where group.count > 1 {
            // winner = 最近更新的一条;稳定 tiebreak。
            let sorted = group.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID)
            }
            let winner = sorted[0]
            let others = Array(sorted.dropFirst())

            // 字段级回填:winner 某字段为空/默认时,从其余重复里取非空值(不丢另一端记的内容)。
            if winner.moodRaw == 0 {
                winner.moodRaw = others.first(where: { $0.moodRaw != 0 })?.moodRaw ?? 0
            }
            if winner.energy == 0 {
                winner.energy = others.first(where: { $0.energy != 0 })?.energy ?? 0
            }
            if winner.pain < 0 {
                winner.pain = others.first(where: { $0.pain >= 0 })?.pain ?? -1
            }
            if winner.sleepHours == nil {
                winner.sleepHours = others.lazy.compactMap { $0.sleepHours }.first
            }
            if winner.weight == nil {
                winner.weight = others.lazy.compactMap { $0.weight }.first
            }
            // 症状取并集(两端记的不同症状都保留)。
            var sym = Set(winner.symptoms)
            for o in others { sym.formUnion(o.symptoms) }
            winner.symptoms = Array(sym).sorted()
            // 备注:winner 空则取其他非空;都有则保留 winner(最近)。
            if winner.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                winner.note = others.first {
                    !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }?.note ?? ""
            }

            for r in others {
                context.delete(r)
                deleted = true
            }
        }
        return deleted
    }
}
