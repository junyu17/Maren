import Foundation
import SwiftUI

/// 追踪项分类。每项属于唯一分类,用于日志页分组展示。
enum TrackerCategory: String, CaseIterable, Identifiable {
    case bleedingCycle = "bleeding_cycle"
    case pain = "pain"
    case discharge = "discharge"
    case mood = "mood"
    case sleepEnergy = "sleep_energy"
    case digestive = "digestive"
    case skinHair = "skin_hair"
    case body = "body"
    case activityWellbeing = "activity_wellbeing"
    case sexualReproductive = "sexual_reproductive"

    var id: String { rawValue }

    /// 分类显示名(本地化)。
    var label: String {
        switch self {
        case .bleedingCycle:     return String(localized: "经期与周期")
        case .pain:              return String(localized: "疼痛与不适")
        case .discharge:         return String(localized: "分泌物与宫颈黏液")
        case .mood:              return String(localized: "情绪")
        case .sleepEnergy:       return String(localized: "睡眠与能量")
        case .digestive:         return String(localized: "消化系统")
        case .skinHair:          return String(localized: "皮肤与头发")
        case .body:              return String(localized: "身体感受")
        case .activityWellbeing: return String(localized: "活动与身心")
        case .sexualReproductive: return String(localized: "性与生殖健康")
        }
    }
}

/// 单个追踪项的静态描述。
struct TrackerEntry: Identifiable, Hashable {
    let key: String
    let category: TrackerCategory
    var id: String { key }
}

/// 内置追踪项目录。80+ 条,按分类组织。
/// 所有标签通过 `Symptoms.label(for:)` 解析;此处只存 key 和分类。
/// 追踪项的显示名(中/英文)在 `Symptoms` 中定义,保持与 `DailyLog.symptoms: [String]` 存储兼容。
enum TrackerCatalog {

    // MARK: - 按分类列出全部条目

    static let bleedingCycle: [TrackerEntry] = [
        TrackerEntry(key: "cramps",              category: .bleedingCycle),
        TrackerEntry(key: "spotting",            category: .bleedingCycle),
        TrackerEntry(key: "heavyFlow",           category: .bleedingCycle),
        TrackerEntry(key: "lightFlow",           category: .bleedingCycle),
        TrackerEntry(key: "missedPeriod",        category: .bleedingCycle),
        TrackerEntry(key: "irregularCycle",      category: .bleedingCycle),
        TrackerEntry(key: "midCyclePain",        category: .bleedingCycle),
        TrackerEntry(key: "pelvicPressure",      category: .bleedingCycle),
        TrackerEntry(key: "menstrualCramps",     category: .bleedingCycle),
        TrackerEntry(key: "cycleSpotting",       category: .bleedingCycle),
        TrackerEntry(key: "latePeriod",          category: .bleedingCycle),
        TrackerEntry(key: "shortCycle",          category: .bleedingCycle),
    ]

    static let pain: [TrackerEntry] = [
        TrackerEntry(key: "headache",            category: .pain),
        TrackerEntry(key: "backache",            category: .pain),
        TrackerEntry(key: "jointPain",           category: .pain),
        TrackerEntry(key: "neckPain",            category: .pain),
        TrackerEntry(key: "legPain",             category: .pain),
        TrackerEntry(key: "abdominalPain",       category: .pain),
        TrackerEntry(key: "chestTightness",      category: .pain),
        TrackerEntry(key: "muscleAches",         category: .pain),
        TrackerEntry(key: "toothache",           category: .pain),
        TrackerEntry(key: "jawPain",             category: .pain),
        TrackerEntry(key: "hipPain",             category: .pain),
        TrackerEntry(key: "ribPain",             category: .pain),
    ]

    static let discharge: [TrackerEntry] = [
        TrackerEntry(key: "wateryDischarge",     category: .discharge),
        TrackerEntry(key: "creamyDischarge",     category: .discharge),
        TrackerEntry(key: "eggWhiteDischarge",   category: .discharge),
        TrackerEntry(key: "thickDischarge",      category: .discharge),
        TrackerEntry(key: "unusualDischarge",    category: .discharge),
        TrackerEntry(key: "vaginalDryness",      category: .discharge),
        TrackerEntry(key: "increasedDischarge",  category: .discharge),
        TrackerEntry(key: "bloodTingedDischarge", category: .discharge),
    ]

    static let mood: [TrackerEntry] = [
        TrackerEntry(key: "anxious",             category: .mood),
        TrackerEntry(key: "irritable",           category: .mood),
        TrackerEntry(key: "sad",                 category: .mood),
        TrackerEntry(key: "euphoric",            category: .mood),
        TrackerEntry(key: "calm",                category: .mood),
        TrackerEntry(key: "overwhelmed",         category: .mood),
        TrackerEntry(key: "emotional",           category: .mood),
        TrackerEntry(key: "apathy",              category: .mood),
        TrackerEntry(key: "moodSwings",          category: .mood),
        TrackerEntry(key: "depression",          category: .mood),
        TrackerEntry(key: "irritable_mood",      category: .mood),
        TrackerEntry(key: "hopeful",             category: .mood),
    ]

    static let sleepEnergy: [TrackerEntry] = [
        TrackerEntry(key: "insomnia",            category: .sleepEnergy),
        TrackerEntry(key: "fatigue",             category: .sleepEnergy),
        TrackerEntry(key: "excessiveSleep",      category: .sleepEnergy),
        TrackerEntry(key: "vividDreams",         category: .sleepEnergy),
        TrackerEntry(key: "nightSweats",         category: .sleepEnergy),
        TrackerEntry(key: "restlessSleep",       category: .sleepEnergy),
        TrackerEntry(key: "earlyMorningWake",    category: .sleepEnergy),
        TrackerEntry(key: "drowsiness",          category: .sleepEnergy),
        TrackerEntry(key: "lowEnergy",           category: .sleepEnergy),
        TrackerEntry(key: "secondWind",          category: .sleepEnergy),
        TrackerEntry(key: "brainFog",            category: .sleepEnergy),
    ]

    static let digestive: [TrackerEntry] = [
        TrackerEntry(key: "bloating",            category: .digestive),
        TrackerEntry(key: "nausea",              category: .digestive),
        TrackerEntry(key: "cravings",            category: .digestive),
        TrackerEntry(key: "diarrhea",            category: .digestive),
        TrackerEntry(key: "constipation",        category: .digestive),
        TrackerEntry(key: "heartburn",           category: .digestive),
        TrackerEntry(key: "lossOfAppetite",      category: .digestive),
        TrackerEntry(key: "increasedAppetite",   category: .digestive),
        TrackerEntry(key: "stomachPain",         category: .digestive),
        TrackerEntry(key: "gas",                 category: .digestive),
    ]

    static let skinHair: [TrackerEntry] = [
        TrackerEntry(key: "acne",                category: .skinHair),
        TrackerEntry(key: "hairloss",            category: .skinHair),
        TrackerEntry(key: "hirsutism",           category: .skinHair),
        TrackerEntry(key: "drySkin",             category: .skinHair),
        TrackerEntry(key: "oilySkin",            category: .skinHair),
        TrackerEntry(key: "skinRash",            category: .skinHair),
        TrackerEntry(key: "sensitiveSkin",       category: .skinHair),
        TrackerEntry(key: "hairThinning",        category: .skinHair),
        TrackerEntry(key: "brittleNails",        category: .skinHair),
        TrackerEntry(key: "stretchMarks",        category: .skinHair),
    ]

    static let body: [TrackerEntry] = [
        TrackerEntry(key: "tender",              category: .body),
        TrackerEntry(key: "breastSwelling",      category: .body),
        TrackerEntry(key: "waterRetention",      category: .body),
        TrackerEntry(key: "hotFlashes",          category: .body),
        TrackerEntry(key: "coldHands",           category: .body),
        TrackerEntry(key: "dryEyes",             category: .body),
        TrackerEntry(key: "sensitiveTeeth",      category: .body),
        TrackerEntry(key: "tingling",            category: .body),
        TrackerEntry(key: "dizziness",           category: .body),
        TrackerEntry(key: "earRinging",          category: .body),
        TrackerEntry(key: "heartRacing",         category: .body),
        TrackerEntry(key: "nasalCongestion",     category: .body),
    ]

    static let activityWellbeing: [TrackerEntry] = [
        TrackerEntry(key: "exercise",            category: .activityWellbeing),
        TrackerEntry(key: "yoga",                category: .activityWellbeing),
        TrackerEntry(key: "meditation",          category: .activityWellbeing),
        TrackerEntry(key: "walking",             category: .activityWellbeing),
        TrackerEntry(key: "stretching",          category: .activityWellbeing),
        TrackerEntry(key: "deepBreathing",       category: .activityWellbeing),
        TrackerEntry(key: "journaling",          category: .activityWellbeing),
        TrackerEntry(key: "socializing",         category: .activityWellbeing),
        TrackerEntry(key: "nature",              category: .activityWellbeing),
        TrackerEntry(key: "relaxation",          category: .activityWellbeing),
        TrackerEntry(key: "music",               category: .activityWellbeing),
        TrackerEntry(key: "creativeActivity",    category: .activityWellbeing),
        TrackerEntry(key: "selfCare",            category: .activityWellbeing),
        TrackerEntry(key: "relaxBath",           category: .activityWellbeing),
        TrackerEntry(key: "outdoorActivity",     category: .activityWellbeing),
        TrackerEntry(key: "reading",             category: .activityWellbeing),
    ]

    static let sexualReproductive: [TrackerEntry] = [
        TrackerEntry(key: "libido",              category: .sexualReproductive),
        TrackerEntry(key: "ovulationPain",       category: .sexualReproductive),
        TrackerEntry(key: "breastTenderness",    category: .sexualReproductive),
    ]

    // MARK: - 聚合

    /// 所有分类,按定义顺序。用于日志页遍历。
    static let allCategories: [TrackerCategory] = TrackerCategory.allCases

    /// 所有内置条目(按分类顺序展平)。
    static let allEntries: [TrackerEntry] = [
        bleedingCycle, pain, discharge, mood, sleepEnergy,
        digestive, skinHair, body, activityWellbeing, sexualReproductive,
    ].flatMap { $0 }

    /// 所有内置 key 的集合。用于 O(1) 查重和测试校验。
    static let allKeys: Set<String> = Set(allEntries.map(\.key))

    /// key -> category 的映射。
    static let categoryByKey: [String: TrackerCategory] = Dictionary(
        uniqueKeysWithValues: allEntries.map { ($0.key, $0.category) }
    )

    // MARK: - TrackerVisual

    /// SF Symbol + 低饱和度配色,用于内置追踪项在选择器中的显示。
    /// 自定义追踪项保留 SymptomTag.emoji,不走此路径。
    struct TrackerVisual {
        let symbol: String
        let color: Color
    }

    /// 分类默认视觉(分类头 + 该分类下无专属定义的条目 fallback)。
    static let categoryVisuals: [TrackerCategory: TrackerVisual] = [
        .bleedingCycle:       TrackerVisual(symbol: "drop.fill",            color: Color(red: 0.82, green: 0.36, blue: 0.42)),
        .pain:                TrackerVisual(symbol: "waveform.path.ecg",     color: Color(red: 0.85, green: 0.45, blue: 0.28)),
        .discharge:           TrackerVisual(symbol: "drop.fill",            color: Color(red: 0.55, green: 0.55, blue: 0.62)),
        .mood:                TrackerVisual(symbol: "face.smiling",         color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        .sleepEnergy:         TrackerVisual(symbol: "moon.zzz.fill",        color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        .digestive:           TrackerVisual(symbol: "leaf.fill",            color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        .skinHair:            TrackerVisual(symbol: "sparkles",             color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        .body:                TrackerVisual(symbol: "heart.fill",           color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        .activityWellbeing:   TrackerVisual(symbol: "figure.mind.and.body", color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        .sexualReproductive:  TrackerVisual(symbol: "leaf.circle.fill",     color: Color(red: 0.62, green: 0.45, blue: 0.68)),
    ]

    /// 内置条目逐 key 专属视觉(按需覆盖分类默认值)。
    static let keyVisuals: [String: TrackerVisual] = [
        // 经期与周期
        "cramps":          TrackerVisual(symbol: "waveform.path.ecg",     color: Color(red: 0.80, green: 0.32, blue: 0.38)),
        "spotting":        TrackerVisual(symbol: "drop.fill",             color: Color(red: 0.82, green: 0.36, blue: 0.42)),
        "heavyFlow":       TrackerVisual(symbol: "drop.fill",             color: Color(red: 0.78, green: 0.28, blue: 0.35)),
        "lightFlow":       TrackerVisual(symbol: "drop.fill",             color: Color(red: 0.88, green: 0.55, blue: 0.55)),
        "missedPeriod":    TrackerVisual(symbol: "questionmark.circle",    color: Color(red: 0.72, green: 0.35, blue: 0.42)),
        "irregularCycle":  TrackerVisual(symbol: "arrow.triangle.2.circlepath", color: Color(red: 0.75, green: 0.38, blue: 0.45)),
        "midCyclePain":    TrackerVisual(symbol: "bolt.fill",             color: Color(red: 0.82, green: 0.36, blue: 0.42)),
        "pelvicPressure":  TrackerVisual(symbol: "arrow.down.to.line",    color: Color(red: 0.78, green: 0.38, blue: 0.42)),
        "menstrualCramps": TrackerVisual(symbol: "waveform.path.ecg",     color: Color(red: 0.80, green: 0.32, blue: 0.38)),
        "cycleSpotting":   TrackerVisual(symbol: "drop.fill",             color: Color(red: 0.82, green: 0.36, blue: 0.42)),
        "latePeriod":      TrackerVisual(symbol: "clock.badge.exclamationmark", color: Color(red: 0.75, green: 0.38, blue: 0.45)),
        "shortCycle":      TrackerVisual(symbol: "speedometer",           color: Color(red: 0.78, green: 0.40, blue: 0.45)),
        // 疼痛与不适
        "headache":        TrackerVisual(symbol: "brain.head.profile",    color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "backache":        TrackerVisual(symbol: "figure.stand",          color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "jointPain":       TrackerVisual(symbol: "figure.flexibility",    color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "neckPain":        TrackerVisual(symbol: "figure.stand",          color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "legPain":         TrackerVisual(symbol: "figure.walk",           color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "abdominalPain":   TrackerVisual(symbol: "figure.seated.side",    color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "chestTightness":  TrackerVisual(symbol: "lungs.fill",            color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "muscleAches":     TrackerVisual(symbol: "figure.strengthtraining.traditional", color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "toothache":       TrackerVisual(symbol: "mouth.fill",            color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "jawPain":         TrackerVisual(symbol: "mouth.fill",            color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "hipPain":         TrackerVisual(symbol: "figure.seated.side",    color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        "ribPain":         TrackerVisual(symbol: "lungs.fill",            color: Color(red: 0.82, green: 0.42, blue: 0.28)),
        // 分泌物与宫颈黏液
        "wateryDischarge":         TrackerVisual(symbol: "drop.fill",         color: Color(red: 0.58, green: 0.58, blue: 0.65)),
        "creamyDischarge":         TrackerVisual(symbol: "drop.fill",         color: Color(red: 0.60, green: 0.58, blue: 0.62)),
        "eggWhiteDischarge":       TrackerVisual(symbol: "drop.fill",         color: Color(red: 0.62, green: 0.60, blue: 0.60)),
        "thickDischarge":          TrackerVisual(symbol: "drop.fill",         color: Color(red: 0.55, green: 0.55, blue: 0.60)),
        "unusualDischarge":        TrackerVisual(symbol: "exclamationmark.triangle.fill", color: Color(red: 0.72, green: 0.55, blue: 0.50)),
        "vaginalDryness":          TrackerVisual(symbol: "drop.fill",         color: Color(red: 0.58, green: 0.55, blue: 0.55)),
        "increasedDischarge":      TrackerVisual(symbol: "arrow.up.circle.fill", color: Color(red: 0.58, green: 0.58, blue: 0.65)),
        "bloodTingedDischarge":    TrackerVisual(symbol: "drop.fill",         color: Color(red: 0.78, green: 0.38, blue: 0.42)),
        // 情绪
        "anxious":         TrackerVisual(symbol: "cloud.bolt",             color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "irritable":       TrackerVisual(symbol: "cloud.bolt.rain",        color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "sad":             TrackerVisual(symbol: "cloud.rain",             color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "euphoric":        TrackerVisual(symbol: "sun.max.fill",           color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "calm":            TrackerVisual(symbol: "sun.min.fill",           color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "overwhelmed":     TrackerVisual(symbol: "cloud.rain.fill",        color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "emotional":       TrackerVisual(symbol: "cloud.drizzle",          color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "apathy":          TrackerVisual(symbol: "cloud",                  color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "moodSwings":      TrackerVisual(symbol: "arrow.triangle.2.circlepath", color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "depression":      TrackerVisual(symbol: "cloud.moon",             color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "irritable_mood":  TrackerVisual(symbol: "cloud.bolt",             color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        "hopeful":         TrackerVisual(symbol: "sun.max",                color: Color(red: 0.50, green: 0.42, blue: 0.78)),
        // 睡眠与能量
        "insomnia":          TrackerVisual(symbol: "moon.fill",             color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "fatigue":           TrackerVisual(symbol: "bolt.slash.fill",       color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "excessiveSleep":    TrackerVisual(symbol: "bed.double.fill",       color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "vividDreams":       TrackerVisual(symbol: "cloud.moon.fill",       color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "nightSweats":       TrackerVisual(symbol: "drop.triangle.fill",    color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "restlessSleep":     TrackerVisual(symbol: "bed.double",            color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "earlyMorningWake":  TrackerVisual(symbol: "sunrise.fill",          color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "drowsiness":        TrackerVisual(symbol: "moon.zzz.fill",         color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "lowEnergy":         TrackerVisual(symbol: "battery.25percent",     color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "secondWind":        TrackerVisual(symbol: "bolt.fill",             color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        "brainFog":          TrackerVisual(symbol: "cloud.fog.fill",        color: Color(red: 0.38, green: 0.52, blue: 0.78)),
        // 消化系统
        "bloating":          TrackerVisual(symbol: "circle",               color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "nausea":            TrackerVisual(symbol: "exclamationmark.triangle.fill", color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "cravings":          TrackerVisual(symbol: "fork.knife",            color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "diarrhea":          TrackerVisual(symbol: "arrow.down.to.line",    color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "constipation":      TrackerVisual(symbol: "stop.circle.fill",      color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "heartburn":         TrackerVisual(symbol: "flame.fill",            color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "lossOfAppetite":    TrackerVisual(symbol: "minus.circle.fill",     color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "increasedAppetite": TrackerVisual(symbol: "plus.circle.fill",      color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "stomachPain":       TrackerVisual(symbol: "exclamationmark.circle.fill", color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        "gas":               TrackerVisual(symbol: "wind",                  color: Color(red: 0.45, green: 0.68, blue: 0.42)),
        // 皮肤与头发
        "acne":              TrackerVisual(symbol: "circle.dotted",         color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "hairloss":          TrackerVisual(symbol: "scissors",              color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "hirsutism":         TrackerVisual(symbol: "person.fill",           color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "drySkin":           TrackerVisual(symbol: "drop.triangle",         color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "oilySkin":          TrackerVisual(symbol: "drop.fill",             color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "skinRash":          TrackerVisual(symbol: "circle.badge.exclamationmark", color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "sensitiveSkin":     TrackerVisual(symbol: "hand.raised.fill",      color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "hairThinning":      TrackerVisual(symbol: "scissors",             color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "brittleNails":      TrackerVisual(symbol: "hand.raised.fill",      color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        "stretchMarks":      TrackerVisual(symbol: "line.3.crossed.swirl.circle.fill", color: Color(red: 0.75, green: 0.58, blue: 0.68)),
        // 身体感受
        "tender":              TrackerVisual(symbol: "heart.fill",            color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "breastSwelling":      TrackerVisual(symbol: "heart.fill",            color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "waterRetention":      TrackerVisual(symbol: "drop.fill",             color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "hotFlashes":          TrackerVisual(symbol: "flame.fill",            color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "coldHands":           TrackerVisual(symbol: "snowflake",             color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "dryEyes":             TrackerVisual(symbol: "eye.fill",              color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "sensitiveTeeth":      TrackerVisual(symbol: "exclamationmark.triangle.fill", color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "tingling":            TrackerVisual(symbol: "bolt.fill",             color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "dizziness":           TrackerVisual(symbol: "arrow.triangle.2.circlepath", color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "earRinging":          TrackerVisual(symbol: "ear.fill",              color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "heartRacing":         TrackerVisual(symbol: "heart.fill",            color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        "nasalCongestion":     TrackerVisual(symbol: "nose.fill",             color: Color(red: 0.78, green: 0.42, blue: 0.52)),
        // 活动与身心
        "exercise":          TrackerVisual(symbol: "figure.run",             color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "yoga":              TrackerVisual(symbol: "figure.mind.and.body",    color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "meditation":        TrackerVisual(symbol: "figure.mind.and.body",    color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "walking":           TrackerVisual(symbol: "figure.walk",             color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "stretching":        TrackerVisual(symbol: "figure.flexibility",      color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "deepBreathing":     TrackerVisual(symbol: "wind",                    color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "journaling":        TrackerVisual(symbol: "book.fill",               color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "socializing":       TrackerVisual(symbol: "person.2.fill",           color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "nature":            TrackerVisual(symbol: "leaf.fill",               color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "relaxation":        TrackerVisual(symbol: "cup.and.saucer.fill",     color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "music":             TrackerVisual(symbol: "music.note",              color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "creativeActivity":  TrackerVisual(symbol: "paintbrush.pointed.fill", color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "selfCare":          TrackerVisual(symbol: "heart.circle.fill",       color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "relaxBath":         TrackerVisual(symbol: "shower.fill",             color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "outdoorActivity":   TrackerVisual(symbol: "figure.hiking",           color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        "reading":           TrackerVisual(symbol: "book.closed.fill",        color: Color(red: 0.35, green: 0.62, blue: 0.55)),
        // 性与生殖健康
        "libido":              TrackerVisual(symbol: "heart.circle.fill",     color: Color(red: 0.62, green: 0.45, blue: 0.68)),
        "ovulationPain":       TrackerVisual(symbol: "bolt.fill",             color: Color(red: 0.62, green: 0.45, blue: 0.68)),
        "breastTenderness":    TrackerVisual(symbol: "heart.fill",            color: Color(red: 0.62, green: 0.45, blue: 0.68)),
    ]

    /// 解析追踪项的 SF Symbol 视觉:逐 key 优先,回退到分类默认。
    static func visual(for key: String) -> TrackerVisual {
        if let v = keyVisuals[key] {
            return accessibleVisual(v, category: categoryByKey[key])
        }
        if let cat = categoryByKey[key], let v = categoryVisuals[cat] {
            return accessibleVisual(v, category: cat)
        }
        return TrackerVisual(symbol: "circle.fill", color: .primary)
    }

    /// 解析分类的视觉:用于分类头图标。
    static func visual(forCategory cat: TrackerCategory) -> TrackerVisual {
        guard let visual = categoryVisuals[cat] else {
            return TrackerVisual(symbol: "list.bullet", color: .primary)
        }
        return accessibleVisual(visual, category: cat)
    }

    /// The legacy table keeps its original tones for data compatibility and
    /// previews, while all production lookup paths use these appearance-aware
    /// tones.  This avoids pale tracker icons disappearing on a light surface
    /// or medium tones losing contrast on a dark surface.
    private static func accessibleVisual(_ visual: TrackerVisual,
                                         category: TrackerCategory?) -> TrackerVisual {
        guard let category else {
            return TrackerVisual(symbol: visual.symbol, color: .primary)
        }
        let palette = VelaPalette.trackerTheme(for: category.rawValue)
        return TrackerVisual(
            symbol: visual.symbol,
            color: VelaPalette.dynamicColor(light: palette.light, dark: palette.dark)
        )
    }
}
