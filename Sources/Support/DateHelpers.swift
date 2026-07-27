import Foundation

/// 与时区无关的「日期主键」:把一天编码成 yyyymmdd 整数(如 2026-07-23 → 20260723)。
///
/// 为什么不用 Date 当主键:Date 存的是绝对时间戳,「本地零点」在不同时区是不同的瞬间。
/// 用户出国、改时区或经历夏令时后,同一个日历日会算出不同的时间戳,
/// 结果就是同一天出现两条记录,或者已记录的那天在日历上「消失」。
/// 整数日键只描述「哪一天」,不含时刻,因此跨时区绝对稳定。
enum DayKey {
    /// 取该时刻在**当前时区**下所属的日历日,编码为 yyyymmdd。
    static func from(_ date: Date) -> Int {
        let c = Cal.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 1970) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    /// 还原成该日在**当前时区**下的零点,仅用于显示与日期运算。
    static func date(from key: Int) -> Date {
        var c = DateComponents()
        c.year = key / 10_000
        c.month = (key / 100) % 100
        c.day = key % 100
        return Cal.current.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    static var today: Int { from(Date()) }
}

/// 全 app 统一使用「当天 00:00(本地时区)」作为显示与运算的日期基准。
enum Cal {
    /// 注意:必须是**计算属性**而不是 `static let`。
    /// 缓存快照会在用户中途切换时区 / 地区 / 日历设置后失效,
    /// 导致 startOfDay 与已存记录对不上,当天记录看起来「消失」。
    static var current: Calendar { Calendar.current }

    /// 归一化到当天起点。所有存储的 date 都应先经过它。
    static func startOfDay(_ date: Date) -> Date {
        current.startOfDay(for: date)
    }

    /// 两个日期是否为同一天。
    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        current.isDate(a, inSameDayAs: b)
    }

    /// 一周的起始日跟随用户地区(中国大陆=周一,美国=周日),不再写死周一。
    static var firstWeekday: Int { current.firstWeekday } // 1 = 周日 ... 7 = 周六

    /// 按用户地区排序后的星期简写,供日历表头使用。
    static var orderedWeekdaySymbols: [String] {
        let symbols = current.veryShortStandaloneWeekdaySymbols // 索引 0 = 周日
        guard symbols.count == 7 else { return symbols }
        let offset = firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// 给定日期所在月份的所有「日」(1...天数),以及该月 1 号之前的前置空位数。
    static func monthGrid(for month: Date) -> (leadingBlanks: Int, days: [Date]) {
        let cal = current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else {
            return (0, [])
        }
        // 前置空位 = 该月 1 号的星期 与 本地区「一周第一天」之间的距离。
        let weekday = cal.component(.weekday, from: first) // 1..7 (周日..周六)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let days: [Date] = range.compactMap { day in
            cal.date(byAdding: .day, value: day - 1, to: first)
        }
        return (leading, days)
    }

    static func addMonths(_ n: Int, to date: Date) -> Date {
        current.date(byAdding: .month, value: n, to: date) ?? date
    }

    /// 两个日期相隔的整天数(按日历天算,不受时分秒影响)。
    static func daysBetween(_ from: Date, _ to: Date) -> Int {
        current.dateComponents([.day], from: startOfDay(from), to: startOfDay(to)).day ?? 0
    }

    /// 跟随系统语言:中文显示「2026 年 7 月」,英文显示「July 2026」。
    /// 同样用计算属性,避免用户切换语言 / 地区后格式不跟着变。
    static var monthTitleFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f
    }

    /// 中文「7 月 8 日 星期三」,英文「Wednesday, July 8」。
    static var fullDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return f
    }

    /// 简短日期「7 月 23 日」/「Jul 23」,用于区间显示。
    static var shortDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }
}
