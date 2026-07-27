import Foundation
import SwiftData

/// 层级 4 · 把手表发来的「快速记录」落进手机的 SwiftData。
/// 手表不存库,所有写入都在这里统一走与 UI 相同的 upsert 逻辑,保证行为一致。
enum QuickLogApplier {

    @MainActor
    static func apply(_ logs: [QuickLog], context: ModelContext) {
        guard !logs.isEmpty else { return }
        for log in logs {
            switch log.kind {
            case "period": applyPeriod(log, context: context)
            case "mood":   applyMood(log, context: context)
            default:       break
            }
        }
        try? context.save()
    }

    private static func applyPeriod(_ log: QuickLog, context: ModelContext) {
        let key = log.dayKey
        let existing = (try? context.fetch(
            FetchDescriptor<PeriodDay>(predicate: #Predicate { $0.dayKey == key })))?.first
        let flow = FlowLevel(rawValue: log.flowRaw ?? 2) ?? .medium
        if let existing {
            existing.flow = flow
        } else {
            context.insert(PeriodDay(date: DayKey.date(from: key), flow: flow))
        }
    }

    private static func applyMood(_ log: QuickLog, context: ModelContext) {
        let key = log.dayKey
        let existing = (try? context.fetch(
            FetchDescriptor<DailyLog>(predicate: #Predicate { $0.dayKey == key })))?.first
        let mood = Mood(rawValue: log.moodRaw ?? 0)
        if let existing {
            existing.mood = mood
            existing.updatedAt = Date()
        } else {
            context.insert(DailyLog(date: DayKey.date(from: key), mood: mood))
        }
    }
}
