import Foundation
import SwiftUI

/// 周期阶段。用于日历多色标注 + 每日一句的阶段匹配。
/// 说明:阶段仅为「基于你自己记录的估算」,**不作排卵/避孕依据**(见预测卡片免责声明)。
enum CyclePhase: String, CaseIterable, Identifiable {
    case menstrual   // 经期
    case follicular  // 卵泡期
    case ovulatory   // 排卵期(估算)
    case luteal      // 黄体期
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .menstrual:  return String(localized: "经期")
        case .follicular: return String(localized: "卵泡期")
        case .ovulatory:  return String(localized: "排卵期")
        case .luteal:     return String(localized: "黄体期")
        case .unknown:    return "—"
        }
    }

    /// 日历格背景填充浓度。排卵期刻意更深,让它在一片浅色里更醒目。
    var fillOpacity: Double {
        switch self {
        case .ovulatory: return 0.42
        default:         return 0.22
        }
    }

    /// 日历格背景色(浅,保证数字可读)。
    var tint: Color {
        switch self {
        case .menstrual:  return Color(red: 0.90, green: 0.40, blue: 0.46)
        case .follicular: return Color(red: 0.34, green: 0.70, blue: 0.62)
        case .ovulatory:  return Color(red: 0.38, green: 0.26, blue: 0.74)
        case .luteal:     return Color(red: 0.95, green: 0.66, blue: 0.36)
        case .unknown:    return .clear
        }
    }
}

/// 依据自适应预测,为「当前周期窗口」内的每一天估算阶段。
/// 关键:排卵期用「下次经期倒推约 14 天(黄体期相对稳定)」估算,
/// **不写死「从周期第 1 天起第 14 天排卵」**,因此对长/不规律周期更合理。
enum PhaseModel {

    /// 黄体期典型长度(天)。相对个体差异小,用它倒推排卵更稳。
    private static let lutealLength = 14

    /// 核心阶段划分:给定「周期内第几天 / 周期总长 / 经期天数」,返回阶段。
    /// 抽出来供当前周期与历史周期共用。
    static func phaseWithin(dayIndex: Int, cycleLength: Int, periodLen: Double) -> CyclePhase {
        guard dayIndex >= 0, cycleLength > 0, dayIndex < cycleLength else { return .unknown }
        // 经期天数不能长过周期本身(极端数据保护)。
        let periodDays = max(1, min(Int(periodLen.rounded()), max(1, cycleLength - 2)))
        // 排卵日估算 = 下次经期 - 黄体期长度(黄体期比卵泡期稳定,倒推比正推准)。
        // 短周期必须压缩黄体期,否则排卵日会落进经期里,导致卵泡期/排卵期永远不显示。
        let luteal = min(lutealLength, max(7, cycleLength - periodDays - 2))
        let ovulationOffset = max(periodDays + 1, cycleLength - luteal)

        if dayIndex < periodDays { return .menstrual }
        if abs(dayIndex - ovulationOffset) <= 1 { return .ovulatory }
        if dayIndex < ovulationOffset { return .follicular }
        return .luteal
    }

    /// 返回某天的阶段;只对「上次经期首日 → 下次预测经期首日」这一段有估算,窗口外返回 unknown。
    static func phase(for day: Date,
                      prediction p: CyclePredictor.Prediction,
                      periodDates: Set<Date>) -> CyclePhase {
        let cal = Cal.current
        let day = Cal.startOfDay(day)

        // 实际记录的经期日 → 经期,最确定。
        if periodDates.contains(day) { return .menstrual }

        guard p.hasEnoughData,
              let cycleStart = p.lastCycleStart,
              let nextStart = p.nextPeriodStart,
              let periodLen = p.averagePeriodLength else {
            return .unknown
        }

        // 只估算当前这个周期窗口 [cycleStart, nextStart)。
        guard day >= cycleStart && day < nextStart else { return .unknown }

        let dayIndex = cal.dateComponents([.day], from: cycleStart, to: day).day ?? 0
        let cycleLength = cal.dateComponents([.day], from: cycleStart, to: nextStart).day ?? 28
        return phaseWithin(dayIndex: dayIndex, cycleLength: cycleLength, periodLen: periodLen)
    }

    /// 历史阶段划分:给某个**过去的日子**估算它当时所处的阶段。
    /// 用于洞察(把每条历史记录归到它当时的周期阶段),而不仅是当前这一个周期。
    static func phaseForPast(_ day: Date,
                             cycles: [CyclePredictor.CycleRecord],
                             avgCycle: Double?,
                             avgPeriod: Double?) -> CyclePhase {
        let cal = Cal.current
        let day = Cal.startOfDay(day)
        // 找到「首日 <= 该天」的最近一个周期。
        guard let rec = cycles.last(where: { Cal.startOfDay($0.start) <= day }) else { return .unknown }
        let dayIndex = cal.dateComponents([.day], from: Cal.startOfDay(rec.start), to: day).day ?? 0
        // 本周期长度:优先用实测长度,进行中的周期用平均值兜底。
        let cycleLength = rec.length ?? Int((avgCycle ?? 28).rounded())
        guard cycleLength > 0, dayIndex < cycleLength else { return .unknown }
        let periodLen = avgPeriod ?? Double(rec.periodDays)
        return phaseWithin(dayIndex: dayIndex, cycleLength: cycleLength, periodLen: periodLen)
    }
}
