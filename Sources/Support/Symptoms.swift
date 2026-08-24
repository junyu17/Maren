import Foundation

/// 预置症状标签。极简、可扩展;后续可做「自定义追踪项」。
struct SymptomTag: Identifiable, Hashable {
    let key: String
    let label: String
    let emoji: String
    var id: String { key }
}

enum Symptoms {
    /// 向后兼容:原始 14 条 legacy key。新增代码请用 `TrackerCatalog` + `allTags`。
    static let legacyKeys: Set<String> = [
        "cramps", "headache", "bloating", "backache", "tender",
        "acne", "fatigue", "nausea", "cravings", "insomnia",
        "anxious", "irritable", "hairloss", "hirsutism",
    ]

    /// 向后兼容:保留原始 14 条用于旧代码路径(如有)。
    static let all: [SymptomTag] = [
        SymptomTag(key: "cramps",    label: String(localized: "痛经"),   emoji: "🩸"),
        SymptomTag(key: "headache",  label: String(localized: "头痛"),   emoji: "🤕"),
        SymptomTag(key: "bloating",  label: String(localized: "腹胀"),   emoji: "🎈"),
        SymptomTag(key: "backache",  label: String(localized: "腰酸"),   emoji: "🔥"),
        SymptomTag(key: "tender",    label: String(localized: "乳房胀痛"), emoji: "💗"),
        SymptomTag(key: "acne",      label: String(localized: "痤疮"),   emoji: "🌋"),
        SymptomTag(key: "fatigue",   label: String(localized: "疲惫"),   emoji: "🥱"),
        SymptomTag(key: "nausea",    label: String(localized: "恶心"),   emoji: "🤢"),
        SymptomTag(key: "cravings",  label: String(localized: "食欲变化"), emoji: "🍫"),
        SymptomTag(key: "insomnia",  label: String(localized: "失眠"),   emoji: "🌙"),
        SymptomTag(key: "anxious",   label: String(localized: "焦虑"),   emoji: "😰"),
        SymptomTag(key: "irritable", label: String(localized: "易怒"),   emoji: "⚡️"),
        SymptomTag(key: "hairloss",  label: String(localized: "脱发"),   emoji: "💇‍♀️"),
        SymptomTag(key: "hirsutism", label: String(localized: "多毛"),   emoji: "🧑‍🦱"),
    ]

    /// 规范 106 条内置标签目录(与 TrackerCatalog 完全对齐)。
    /// `selectedTags` / `tag(for:)` / `tags(for:)` 均查此表。
    static let allTags: [SymptomTag] = [
        // 经期与周期
        SymptomTag(key: "cramps",              label: String(localized: "痛经"),           emoji: "🩸"),
        SymptomTag(key: "spotting",            label: String(localized: "点滴出血"),       emoji: "💧"),
        SymptomTag(key: "heavyFlow",           label: String(localized: "经量偏多"),       emoji: "🩸"),
        SymptomTag(key: "lightFlow",           label: String(localized: "经量偏少"),       emoji: "💧"),
        SymptomTag(key: "missedPeriod",        label: String(localized: "停经"),           emoji: "⭕"),
        SymptomTag(key: "irregularCycle",      label: String(localized: "周期不规律"),     emoji: "🔄"),
        SymptomTag(key: "midCyclePain",        label: String(localized: "排卵期疼痛"),     emoji: "⚡"),
        SymptomTag(key: "pelvicPressure",      label: String(localized: "盆腔压迫感"),     emoji: "⬇️"),
        SymptomTag(key: "menstrualCramps",     label: String(localized: "经期痉挛"),       emoji: "🩸"),
        SymptomTag(key: "cycleSpotting",       label: String(localized: "周期点滴出血"),   emoji: "💧"),
        SymptomTag(key: "latePeriod",          label: String(localized: "经期延迟"),       emoji: "⏳"),
        SymptomTag(key: "shortCycle",          label: String(localized: "周期偏短"),       emoji: "⏱️"),
        // 疼痛与不适
        SymptomTag(key: "headache",            label: String(localized: "头痛"),           emoji: "🤕"),
        SymptomTag(key: "backache",            label: String(localized: "腰酸"),           emoji: "🔥"),
        SymptomTag(key: "jointPain",           label: String(localized: "关节痛"),         emoji: "🦴"),
        SymptomTag(key: "neckPain",            label: String(localized: "颈部疼痛"),       emoji: "🦒"),
        SymptomTag(key: "legPain",             label: String(localized: "腿部疼痛"),       emoji: "🦵"),
        SymptomTag(key: "abdominalPain",       label: String(localized: "腹部疼痛"),       emoji: "🔵"),
        SymptomTag(key: "chestTightness",      label: String(localized: "胸闷"),           emoji: "💨"),
        SymptomTag(key: "muscleAches",         label: String(localized: "肌肉酸痛"),       emoji: "💪"),
        SymptomTag(key: "toothache",           label: String(localized: "牙痛"),           emoji: "🦷"),
        SymptomTag(key: "jawPain",             label: String(localized: "下颌疼痛"),       emoji: "😮"),
        SymptomTag(key: "hipPain",             label: String(localized: "髋部疼痛"),       emoji: "🦴"),
        SymptomTag(key: "ribPain",             label: String(localized: "肋骨疼痛"),       emoji: "🫁"),
        // 分泌物与宫颈黏液
        SymptomTag(key: "wateryDischarge",     label: String(localized: "水样分泌物"),     emoji: "💧"),
        SymptomTag(key: "creamyDischarge",     label: String(localized: "乳状分泌物"),     emoji: "🥛"),
        SymptomTag(key: "eggWhiteDischarge",   label: String(localized: "蛋清样分泌物"),   emoji: "🥚"),
        SymptomTag(key: "thickDischarge",      label: String(localized: "稠厚分泌物"),     emoji: "☁️"),
        SymptomTag(key: "unusualDischarge",    label: String(localized: "异常分泌物"),     emoji: "⚠️"),
        SymptomTag(key: "vaginalDryness",      label: String(localized: "阴道干涩"),       emoji: "🏜️"),
        SymptomTag(key: "increasedDischarge",  label: String(localized: "分泌物增多"),     emoji: "💧"),
        SymptomTag(key: "bloodTingedDischarge", label: String(localized: "血性分泌物"),    emoji: "🩸"),
        // 情绪
        SymptomTag(key: "anxious",             label: String(localized: "焦虑"),           emoji: "😰"),
        SymptomTag(key: "irritable",           label: String(localized: "易怒"),           emoji: "⚡️"),
        SymptomTag(key: "sad",                 label: String(localized: "情绪低落"),       emoji: "😢"),
        SymptomTag(key: "euphoric",            label: String(localized: "情绪高涨"),       emoji: "🤩"),
        SymptomTag(key: "calm",                label: String(localized: "平静"),           emoji: "😌"),
        SymptomTag(key: "overwhelmed",         label: String(localized: "压力过大"),       emoji: "😵"),
        SymptomTag(key: "emotional",           label: String(localized: "情绪化"),         emoji: "🎭"),
        SymptomTag(key: "apathy",              label: String(localized: "淡漠"),           emoji: "😐"),
        SymptomTag(key: "moodSwings",          label: String(localized: "情绪波动"),       emoji: "🎢"),
        SymptomTag(key: "depression",          label: String(localized: "低落"),           emoji: "😔"),
        SymptomTag(key: "irritable_mood",      label: String(localized: "烦躁"),           emoji: "😤"),
        SymptomTag(key: "hopeful",             label: String(localized: "充满希望"),       emoji: "🌟"),
        // 睡眠与能量
        SymptomTag(key: "insomnia",            label: String(localized: "失眠"),           emoji: "🌙"),
        SymptomTag(key: "fatigue",             label: String(localized: "疲惫"),           emoji: "🥱"),
        SymptomTag(key: "excessiveSleep",      label: String(localized: "嗜睡"),           emoji: "😴"),
        SymptomTag(key: "vividDreams",         label: String(localized: "多梦"),           emoji: "💭"),
        SymptomTag(key: "nightSweats",         label: String(localized: "盗汗"),           emoji: "💦"),
        SymptomTag(key: "restlessSleep",       label: String(localized: "睡眠不安"),       emoji: "🛏️"),
        SymptomTag(key: "earlyMorningWake",    label: String(localized: "早醒"),           emoji: "🌅"),
        SymptomTag(key: "drowsiness",          label: String(localized: "困倦"),           emoji: "😪"),
        SymptomTag(key: "lowEnergy",           label: String(localized: "精力不足"),       emoji: "🔋"),
        SymptomTag(key: "secondWind",          label: String(localized: "夜间精力充沛"),   emoji: "⚡"),
        SymptomTag(key: "brainFog",            label: String(localized: "脑雾"),           emoji: "🌫️"),
        // 消化系统
        SymptomTag(key: "bloating",            label: String(localized: "腹胀"),           emoji: "🎈"),
        SymptomTag(key: "nausea",              label: String(localized: "恶心"),           emoji: "🤢"),
        SymptomTag(key: "cravings",            label: String(localized: "食欲变化"),       emoji: "🍫"),
        SymptomTag(key: "diarrhea",            label: String(localized: "腹泻"),           emoji: "🚽"),
        SymptomTag(key: "constipation",        label: String(localized: "便秘"),           emoji: "😣"),
        SymptomTag(key: "heartburn",           label: String(localized: "烧心"),           emoji: "🔥"),
        SymptomTag(key: "lossOfAppetite",      label: String(localized: "食欲下降"),       emoji: "🍽️"),
        SymptomTag(key: "increasedAppetite",   label: String(localized: "食欲增加"),       emoji: "🍴"),
        SymptomTag(key: "stomachPain",         label: String(localized: "胃痛"),           emoji: "🤢"),
        SymptomTag(key: "gas",                 label: String(localized: "胀气"),           emoji: "💨"),
        // 皮肤与头发
        SymptomTag(key: "acne",                label: String(localized: "痤疮"),           emoji: "🌋"),
        SymptomTag(key: "hairloss",            label: String(localized: "脱发"),           emoji: "💇‍♀️"),
        SymptomTag(key: "hirsutism",           label: String(localized: "多毛"),           emoji: "🧑‍🦱"),
        SymptomTag(key: "drySkin",             label: String(localized: "皮肤干燥"),       emoji: "🏜️"),
        SymptomTag(key: "oilySkin",            label: String(localized: "皮肤出油"),       emoji: "💧"),
        SymptomTag(key: "skinRash",            label: String(localized: "皮疹"),           emoji: "🔴"),
        SymptomTag(key: "sensitiveSkin",       label: String(localized: "皮肤敏感"),       emoji: "🤍"),
        SymptomTag(key: "hairThinning",        label: String(localized: "头发变稀"),       emoji: "💇"),
        SymptomTag(key: "brittleNails",        label: String(localized: "指甲脆弱"),       emoji: "💅"),
        SymptomTag(key: "stretchMarks",        label: String(localized: "妊娠纹"),         emoji: "📏"),
        // 身体感受
        SymptomTag(key: "tender",              label: String(localized: "乳房胀痛"),       emoji: "💗"),
        SymptomTag(key: "breastSwelling",      label: String(localized: "乳房肿胀"),       emoji: "💗"),
        SymptomTag(key: "waterRetention",      label: String(localized: "水肿"),           emoji: "💧"),
        SymptomTag(key: "hotFlashes",          label: String(localized: "潮热"),           emoji: "🔥"),
        SymptomTag(key: "coldHands",           label: String(localized: "手脚冰凉"),       emoji: "🥶"),
        SymptomTag(key: "dryEyes",             label: String(localized: "眼睛干涩"),       emoji: "👁️"),
        SymptomTag(key: "sensitiveTeeth",      label: String(localized: "牙齿敏感"),       emoji: "🦷"),
        SymptomTag(key: "tingling",            label: String(localized: "麻木刺痛"),       emoji: "⚡"),
        SymptomTag(key: "dizziness",           label: String(localized: "头晕"),           emoji: "💫"),
        SymptomTag(key: "earRinging",          label: String(localized: "耳鸣"),           emoji: "🔔"),
        SymptomTag(key: "heartRacing",         label: String(localized: "心跳加速"),       emoji: "💓"),
        SymptomTag(key: "nasalCongestion",     label: String(localized: "鼻塞"),           emoji: "👃"),
        // 活动与身心
        SymptomTag(key: "exercise",            label: String(localized: "运动"),           emoji: "🏋️"),
        SymptomTag(key: "yoga",                label: String(localized: "瑜伽"),           emoji: "🧘"),
        SymptomTag(key: "meditation",          label: String(localized: "冥想"),           emoji: "🧘‍♀️"),
        SymptomTag(key: "walking",             label: String(localized: "步行"),           emoji: "🚶"),
        SymptomTag(key: "stretching",          label: String(localized: "拉伸"),           emoji: "🤸"),
        SymptomTag(key: "deepBreathing",       label: String(localized: "深呼吸"),         emoji: "🌬️"),
        SymptomTag(key: "journaling",          label: String(localized: "写日记"),         emoji: "📝"),
        SymptomTag(key: "socializing",         label: String(localized: "社交"),           emoji: "👥"),
        SymptomTag(key: "nature",              label: String(localized: "接触自然"),       emoji: "🌿"),
        SymptomTag(key: "relaxation",          label: String(localized: "放松"),           emoji: "☕"),
        SymptomTag(key: "music",               label: String(localized: "听音乐"),         emoji: "🎵"),
        SymptomTag(key: "creativeActivity",    label: String(localized: "创作活动"),       emoji: "🎨"),
        SymptomTag(key: "selfCare",            label: String(localized: "自我关怀"),       emoji: "💖"),
        SymptomTag(key: "relaxBath",           label: String(localized: "泡澡放松"),       emoji: "🛁"),
        SymptomTag(key: "outdoorActivity",     label: String(localized: "户外活动"),       emoji: "🏕️"),
        SymptomTag(key: "reading",             label: String(localized: "阅读"),           emoji: "📚"),
        // 性与生殖健康
        SymptomTag(key: "libido",              label: String(localized: "性欲变化"),       emoji: "💕"),
        SymptomTag(key: "ovulationPain",       label: String(localized: "排卵疼痛"),       emoji: "⚡"),
        SymptomTag(key: "breastTenderness",    label: String(localized: "乳房触痛"),       emoji: "💗"),
    ]

    /// 内置 key -> tag,便于 O(1) 查询。从 allTags 构建,覆盖全部 106 条。
    private static let builtInByKey = Dictionary(uniqueKeysWithValues: allTags.map { ($0.key, $0) })

    /// 全部内置 key 的标签映射(含新增项),统一在一处维护中英文标签。
    private static let labelByKey: [String: String] = [
        // 经期与周期
        "cramps":              String(localized: "痛经"),
        "spotting":            String(localized: "点滴出血"),
        "heavyFlow":           String(localized: "经量偏多"),
        "lightFlow":           String(localized: "经量偏少"),
        "missedPeriod":        String(localized: "停经"),
        "irregularCycle":      String(localized: "周期不规律"),
        "midCyclePain":        String(localized: "排卵期疼痛"),
        "pelvicPressure":      String(localized: "盆腔压迫感"),
        "menstrualCramps":     String(localized: "经期痉挛"),
        "cycleSpotting":       String(localized: "周期点滴出血"),
        "latePeriod":          String(localized: "经期延迟"),
        "shortCycle":          String(localized: "周期偏短"),
        // 疼痛与不适
        "headache":            String(localized: "头痛"),
        "backache":            String(localized: "腰酸"),
        "jointPain":           String(localized: "关节痛"),
        "neckPain":            String(localized: "颈部疼痛"),
        "legPain":             String(localized: "腿部疼痛"),
        "abdominalPain":       String(localized: "腹部疼痛"),
        "chestTightness":      String(localized: "胸闷"),
        "muscleAches":         String(localized: "肌肉酸痛"),
        "toothache":           String(localized: "牙痛"),
        "jawPain":             String(localized: "下颌疼痛"),
        "hipPain":             String(localized: "髋部疼痛"),
        "ribPain":             String(localized: "肋骨疼痛"),
        // 分泌物与宫颈黏液
        "wateryDischarge":     String(localized: "水样分泌物"),
        "creamyDischarge":     String(localized: "乳状分泌物"),
        "eggWhiteDischarge":   String(localized: "蛋清样分泌物"),
        "thickDischarge":      String(localized: "稠厚分泌物"),
        "unusualDischarge":    String(localized: "异常分泌物"),
        "vaginalDryness":      String(localized: "阴道干涩"),
        "increasedDischarge":  String(localized: "分泌物增多"),
        "bloodTingedDischarge": String(localized: "血性分泌物"),
        // 情绪
        "anxious":             String(localized: "焦虑"),
        "irritable":           String(localized: "易怒"),
        "sad":                 String(localized: "情绪低落"),
        "euphoric":            String(localized: "情绪高涨"),
        "calm":                String(localized: "平静"),
        "overwhelmed":         String(localized: "压力过大"),
        "emotional":           String(localized: "情绪化"),
        "apathy":              String(localized: "淡漠"),
        "moodSwings":          String(localized: "情绪波动"),
        "depression":          String(localized: "低落"),
        "irritable_mood":      String(localized: "烦躁"),
        "hopeful":             String(localized: "充满希望"),
        // 睡眠与能量
        "insomnia":            String(localized: "失眠"),
        "fatigue":             String(localized: "疲惫"),
        "excessiveSleep":      String(localized: "嗜睡"),
        "vividDreams":         String(localized: "多梦"),
        "nightSweats":         String(localized: "盗汗"),
        "restlessSleep":       String(localized: "睡眠不安"),
        "earlyMorningWake":    String(localized: "早醒"),
        "drowsiness":          String(localized: "困倦"),
        "lowEnergy":           String(localized: "精力不足"),
        "secondWind":          String(localized: "夜间精力充沛"),
        "brainFog":            String(localized: "脑雾"),
        // 消化系统
        "bloating":            String(localized: "腹胀"),
        "nausea":              String(localized: "恶心"),
        "cravings":            String(localized: "食欲变化"),
        "diarrhea":            String(localized: "腹泻"),
        "constipation":        String(localized: "便秘"),
        "heartburn":           String(localized: "烧心"),
        "lossOfAppetite":      String(localized: "食欲下降"),
        "increasedAppetite":   String(localized: "食欲增加"),
        "stomachPain":         String(localized: "胃痛"),
        "gas":                 String(localized: "胀气"),
        // 皮肤与头发
        "acne":                String(localized: "痤疮"),
        "hairloss":            String(localized: "脱发"),
        "hirsutism":           String(localized: "多毛"),
        "drySkin":             String(localized: "皮肤干燥"),
        "oilySkin":            String(localized: "皮肤出油"),
        "skinRash":            String(localized: "皮疹"),
        "sensitiveSkin":       String(localized: "皮肤敏感"),
        "hairThinning":        String(localized: "头发变稀"),
        "brittleNails":        String(localized: "指甲脆弱"),
        "stretchMarks":        String(localized: "妊娠纹"),
        // 身体感受
        "tender":              String(localized: "乳房胀痛"),
        "breastSwelling":      String(localized: "乳房肿胀"),
        "waterRetention":      String(localized: "水肿"),
        "hotFlashes":          String(localized: "潮热"),
        "coldHands":           String(localized: "手脚冰凉"),
        "dryEyes":             String(localized: "眼睛干涩"),
        "sensitiveTeeth":      String(localized: "牙齿敏感"),
        "tingling":            String(localized: "麻木刺痛"),
        "dizziness":           String(localized: "头晕"),
        "earRinging":          String(localized: "耳鸣"),
        "heartRacing":         String(localized: "心跳加速"),
        "nasalCongestion":     String(localized: "鼻塞"),
        // 活动与身心
        "exercise":            String(localized: "运动"),
        "yoga":                String(localized: "瑜伽"),
        "meditation":          String(localized: "冥想"),
        "walking":             String(localized: "步行"),
        "stretching":          String(localized: "拉伸"),
        "deepBreathing":       String(localized: "深呼吸"),
        "journaling":          String(localized: "写日记"),
        "socializing":         String(localized: "社交"),
        "nature":              String(localized: "接触自然"),
        "relaxation":          String(localized: "放松"),
        "music":               String(localized: "听音乐"),
        "creativeActivity":    String(localized: "创作活动"),
        "selfCare":            String(localized: "自我关怀"),
        "relaxBath":           String(localized: "泡澡放松"),
        "outdoorActivity":     String(localized: "户外活动"),
        "reading":             String(localized: "阅读"),
        // 性与生殖健康
        "libido":              String(localized: "性欲变化"),
        "ovulationPain":       String(localized: "排卵疼痛"),
        "breastTenderness":    String(localized: "乳房触痛"),
    ]

    /// 解析任意 key 的显示名(内置 + 自定义)。
    /// 新增 key 只需在 `labelByKey` 加一行即可自动生效。
    static func label(for key: String) -> String {
        if let lbl = labelByKey[key] { return lbl }
        if let t = CustomSymptomStore.byKey[key] { return t.label }
        return key
    }

    /// 解析任意 key 的完整标签(含 emoji)。
    /// 从 allTags 查找,对未知 key 返回 bullet fallback。
    static func tag(for key: String) -> SymptomTag {
        builtInByKey[key] ?? CustomSymptomStore.byKey[key]
            ?? SymptomTag(key: key, label: label(for: key), emoji: "•")
    }

    /// 根据 TrackerCatalog 分类返回该分类下所有 SymptomTag。
    static func tags(for category: TrackerCategory) -> [SymptomTag] {
        TrackerCatalog.allEntries
            .filter { $0.category == category }
            .map { SymptomTag(key: $0.key, label: label(for: $0.key), emoji: emoji(for: $0.key)) }
    }

    /// 内置 key 对应的 emoji。分类展示时用。
    private static let emojiByKey: [String: String] = [
        "cramps": "🩸", "headache": "🤕", "bloating": "🎈", "backache": "🔥",
        "tender": "💗", "acne": "🌋", "fatigue": "🥱", "nausea": "🤢",
        "cravings": "🍫", "insomnia": "🌙", "anxious": "😰", "irritable": "⚡️",
        "hairloss": "💇‍♀️", "hirsutism": "🧑‍🦱",
        "spotting": "💧", "heavyFlow": "🩸", "lightFlow": "💧",
        "missedPeriod": "⭕", "irregularCycle": "🔄", "midCyclePain": "⚡",
        "pelvicPressure": "⬇️", "menstrualCramps": "🩸", "cycleSpotting": "💧",
        "latePeriod": "⏳", "shortCycle": "⏱️",
        "jointPain": "🦴", "neckPain": "🦒", "legPain": "🦵",
        "abdominalPain": "🔵", "chestTightness": "💨", "muscleAches": "💪",
        "toothache": "🦷", "jawPain": "😮", "hipPain": "🦴", "ribPain": "🫁",
        "wateryDischarge": "💧", "creamyDischarge": "🥛", "eggWhiteDischarge": "🥚",
        "thickDischarge": "☁️", "unusualDischarge": "⚠️", "vaginalDryness": "🏜️",
        "increasedDischarge": "💧", "bloodTingedDischarge": "🩸",
        "sad": "😢", "euphoric": "🤩", "calm": "😌", "overwhelmed": "😵",
        "emotional": "🎭", "apathy": "😐", "moodSwings": "🎢",
        "depression": "😔", "irritable_mood": "😤", "hopeful": "🌟",
        "excessiveSleep": "😴", "vividDreams": "💭", "nightSweats": "💦",
        "restlessSleep": "🛏️", "earlyMorningWake": "🌅", "drowsiness": "😪",
        "lowEnergy": "🔋", "secondWind": "⚡", "brainFog": "🌫️",
        "diarrhea": "🚽", "constipation": "😣", "heartburn": "🔥",
        "lossOfAppetite": "🍽️", "increasedAppetite": "🍴", "stomachPain": "🤢", "gas": "💨",
        "drySkin": "🏜️", "oilySkin": "💧", "skinRash": "🔴",
        "sensitiveSkin": "🤍", "hairThinning": "💇", "brittleNails": "💅", "stretchMarks": "📏",
        "breastSwelling": "💗", "waterRetention": "💧", "hotFlashes": "🔥",
        "coldHands": "🥶", "dryEyes": "👁️", "sensitiveTeeth": "🦷",
        "tingling": "⚡", "dizziness": "💫", "earRinging": "🔔",
        "heartRacing": "💓", "nasalCongestion": "👃",
        "exercise": "🏋️", "yoga": "🧘", "meditation": "🧘‍♀️", "walking": "🚶",
        "stretching": "🤸", "deepBreathing": "🌬️", "journaling": "📝",
        "socializing": "👥", "nature": "🌿", "relaxation": "☕",
        "music": "🎵", "creativeActivity": "🎨", "selfCare": "💖",
        "relaxBath": "🛁", "outdoorActivity": "🏕️", "reading": "📚",
        "libido": "💕", "ovulationPain": "⚡", "breastTenderness": "💗",
    ]

    static func emoji(for key: String) -> String {
        emojiByKey[key] ?? "•"
    }
}
