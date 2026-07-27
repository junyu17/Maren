import Foundation
import WidgetKit

/// 层级 3 · 主 app 侧:算好展示文案写入共享快照,并刷新小组件时间线。
/// 在数据变化后调用(标经期、存每日记录、app 启动)。
enum WidgetSync {
    static func refresh(periodDays: [PeriodDay], logs: [DailyLog]) {
        let today = Cal.startOfDay(Date())
        let p = CyclePredictor.predict(from: periodDays, manual: ManualCycle.current)

        let title: String
        let value: String

        if p.hasEnoughData, let next = p.nextPeriodStart {
            let days = Cal.daysBetween(today, next)
            if days > 1 {
                title = String(localized: "距下次经期")
                value = String(localized: "\(days) 天")
            } else if days >= 0 {
                title = String(localized: "下次经期")
                value = String(localized: "就在这几天")
            } else {
                title = String(localized: "经期可能已延后")
                value = String(localized: "\(-days) 天")
            }
        } else if let start = p.lastCycleStart {
            // 数据不足以预测下次经期,就显示「当前周期第几天」。
            title = String(localized: "当前周期")
            value = String(localized: "第 \(Cal.daysBetween(start, today) + 1) 天")
        } else {
            title = String(localized: "Maren")
            value = String(localized: "开始记录")
        }

        // 每日一句(按当天阶段)。
        let phase = PhaseModel.phase(for: today, prediction: p,
                                     periodDates: Set(periodDays.map { $0.date }))
        let quote = DailyQuote.forToday(phase: phase, date: today)

        let snapshot = WidgetSnapshot(title: title, value: value, note: quote,
                                      themeRaw: AppTheme.current.rawValue, updated: Date())
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // 同一份快照也推给手表(手表只展示,不存库)。
        PhoneConnectivity.shared.push(snapshot)
    }
}
