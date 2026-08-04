import Foundation

/// F4:每日激励一句话。本地 JSON 词库,离线可用,按周期阶段智能匹配。
enum DailyQuote {

    private struct Entry: Decodable { let zh: String; let en: String }

    /// 词库缓存(阶段 key -> 句子列表)。
    private static let library: [String: [Entry]] = {
        guard let url = Bundle.main.url(forResource: "quotes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [Entry]].self, from: data) else {
            return [:]
        }
        return dict
    }()

    /// 用「bundle 实际解析出的本地化」而不是 Locale.current 来判断语言,
    /// 这样每日一句和界面文案永远一致(例如系统是法语、界面回退到英文时,句子也给英文)。
    private static var preferEnglish: Bool {
        let localization = Bundle.main.preferredLocalizations.first ?? "en"
        return !localization.hasPrefix("zh")
    }

    /// 取今天这句:按阶段选桶(无则回落到 general),同一天稳定返回同一句。
    static func forToday(phase: CyclePhase, date: Date = Date()) -> String {
        let bucketKey: String
        switch phase {
        case .menstrual:  bucketKey = "menstrual"
        case .follicular: bucketKey = "follicular"
        case .ovulatory:  bucketKey = "ovulatory"
        case .luteal:     bucketKey = "luteal"
        case .unknown:    bucketKey = "general"
        }
        let bucket = library[bucketKey] ?? library["general"] ?? []
        guard !bucket.isEmpty else {
            return String(localized: "记录本身,就是善待自己的一种方式。")
        }
        // 用「日期主键」做确定性索引,保证当天固定、逐日轮换。
        // 不能用 epoch 秒/86400:夏令时切换日或半时区(印度 +5:30 等)下,
        // 本地午夜除以 86400 的商会跳变/重复,与 dayKey 铁律不一致。
        let dayNumber = DayKey.from(date)
        let entry = bucket[((dayNumber % bucket.count) + bucket.count) % bucket.count]
        return preferEnglish ? entry.en : entry.zh
    }
}
