import Foundation

/// Education catalog engine. Codable models + local bundle loading, no UI dependency.
enum EducationCatalog {

    // MARK: - Category

    enum Category: String, Codable, CaseIterable, Identifiable {
        case general
        case menstrualHealth
        case cyclePhases
        case perimenopause
        case nutrition
        case exercise
        case mentalWellbeing

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general:          return String(localized: "综合")
            case .menstrualHealth:  return String(localized: "经期健康")
            case .cyclePhases:      return String(localized: "周期阶段")
            case .perimenopause:    return String(localized: "围绝经期")
            case .nutrition:        return String(localized: "营养")
            case .exercise:         return String(localized: "运动")
            case .mentalWellbeing:  return String(localized: "心理健康")
            }
        }
    }

    // MARK: - Bilingual String

    struct BilingualString: Codable, Equatable {
        let zh: String
        let en: String
        /// Added after zh/en shipped, so older content files decode without it.
        let es: String?
        /// Added after zh/en/es shipped, so older content files decode without it.
        let ja: String?

        init(zh: String, en: String, es: String? = nil, ja: String? = nil) {
            self.zh = zh
            self.en = en
            self.es = es
            self.ja = ja
        }
    }

    // MARK: - Source

    struct Source: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let url: String
    }

    // MARK: - Item

    struct Item: Codable, Identifiable, Equatable {
        let id: String
        let category: Category
        let title: BilingualString
        let summary: BilingualString
        let body: BilingualString
        let trackerTags: [String]
        let phaseTags: [String]
        let audienceTags: [String]
        let sources: [Source]
        let reviewedAt: String
        let nonMedicalAdvice: BilingualString
        let isPro: Bool

        init(id: String, category: Category,
             title: BilingualString, summary: BilingualString, body: BilingualString,
             trackerTags: [String] = [], phaseTags: [String] = [],
             audienceTags: [String] = [],
             sources: [Source] = [], reviewedAt: String = "",
             nonMedicalAdvice: BilingualString = BilingualString(zh: "", en: ""),
             isPro: Bool = false) {
            self.id = id
            self.category = category
            self.title = title
            self.summary = summary
            self.body = body
            self.trackerTags = trackerTags
            self.phaseTags = phaseTags
            self.audienceTags = audienceTags
            self.sources = sources
            self.reviewedAt = reviewedAt
            self.nonMedicalAdvice = nonMedicalAdvice
            self.isPro = isPro
        }
    }

    // MARK: - Loading

    /// Safe bundle loader. Looks for education_content.json; returns only a fully
    /// valid unique collection or [] on any error.
    static func load(from bundle: Bundle = .main) -> [Item] {
        guard let url = bundle.url(forResource: "education_content", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return validatedCollection(items)
    }

    // MARK: - Locale

    static func localized(_ b: BilingualString, locale: String? = nil) -> String {
        let loc = locale ?? Bundle.main.preferredLocalizations.first ?? "en"
        if loc.hasPrefix("zh") { return b.zh }
        if loc.hasPrefix("es") { return b.es ?? b.en }
        if loc.hasPrefix("ja") { return b.ja ?? b.en }
        return b.en
    }

    /// Stable bilingual category terms for search, independent of the current
    /// UI language. The catalog stores a raw enum value, so these labels keep a
    /// Chinese user able to find the same article with an English term (and
    /// vice versa).
    static func categorySearchTerms(_ category: Category) -> [String] {
        switch category {
        case .general: return ["综合", "General", "general"]
        case .menstrualHealth: return ["经期健康", "Menstrual health", "menstrualHealth"]
        case .cyclePhases: return ["周期阶段", "Cycle phases", "cyclePhases"]
        case .perimenopause: return ["围绝经期", "Perimenopause", "perimenopause"]
        case .nutrition: return ["营养", "Nutrition", "nutrition"]
        case .exercise: return ["运动", "Exercise", "exercise"]
        case .mentalWellbeing: return ["心理健康", "Mental wellbeing", "mentalWellbeing"]
        }
    }

    // MARK: - Search

    static func search(_ items: [Item], query: String, locale: String? = nil) -> [Item] {
        let documents = items.map { item in
            LocalSearchEngine.Document(
                id: item.id,
                kind: .education,
                title: localized(item.title, locale: locale),
                subtitle: localized(item.summary, locale: locale),
                body: localized(item.body, locale: locale),
                // Keep both languages and the catalog tags searchable even when
                // the device UI is currently using the other language.
                keywords: [
                    item.title.zh, item.title.en,
                    item.summary.zh, item.summary.en,
                    item.body.zh, item.body.en,
                    item.trackerTags.joined(separator: " "),
                    item.phaseTags.joined(separator: " "),
                    item.audienceTags.joined(separator: " ")
                ]
                + categorySearchTerms(item.category)
            )
        }
        let byID = items.reduce(into: [String: Item]()) { result, item in
            if result[item.id] == nil { result[item.id] = item }
        }
        return LocalSearchEngine.search(documents, query: query).compactMap { byID[$0.document.id] }
    }

    // MARK: - Filter

    static func filter(_ items: [Item],
                       category: Category? = nil,
                       trackerTag: String? = nil,
                       phaseTag: String? = nil,
                       audienceTag: String? = nil) -> [Item] {
        items.filter { item in
            if let c = category, item.category != c { return false }
            if let t = trackerTag, !item.trackerTags.contains(t) { return false }
            if let p = phaseTag, !item.phaseTags.contains(p) && !item.phaseTags.contains("any") { return false }
            if let a = audienceTag, !item.audienceTags.contains(a) && !item.audienceTags.contains("all") { return false }
            return true
        }
    }

    // MARK: - Validation

    static func validate(_ item: Item) -> [String] {
        var e: [String] = []

        // id
        if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            e.append("id must not be empty")
        }

        // bilingual fields
        func checkBilingual(_ b: BilingualString, _ prefix: String) {
            if b.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { e.append("\(prefix).zh must not be empty") }
            if b.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { e.append("\(prefix).en must not be empty") }
        }
        checkBilingual(item.title, "title")
        checkBilingual(item.summary, "summary")
        checkBilingual(item.body, "body")
        checkBilingual(item.nonMedicalAdvice, "nonMedicalAdvice")

        // tags
        if item.trackerTags.isEmpty { e.append("trackerTags must not be empty") }
        if item.phaseTags.isEmpty { e.append("phaseTags must not be empty") }
        if item.audienceTags.isEmpty { e.append("audienceTags must not be empty") }

        // sources
        if item.sources.isEmpty {
            e.append("sources must not be empty")
        } else {
            for (i, src) in item.sources.enumerated() {
                if src.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    e.append("sources[\(i)].name must not be empty")
                }
                if !src.url.hasPrefix("https://") || URL(string: src.url) == nil {
                    e.append("sources[\(i)].url must be a valid https URL")
                }
            }
        }

        // reviewedAt - strict yyyy-MM-dd with exact round-trip
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.isLenient = false
        guard let date = fmt.date(from: item.reviewedAt) else {
            e.append("reviewedAt must be a valid yyyy-MM-dd date")
            return e
        }
        let roundTrip = fmt.string(from: date)
        if roundTrip != item.reviewedAt {
            e.append("reviewedAt must be exact yyyy-MM-dd with no extra whitespace")
        }

        return e
    }

    static func validatedCollection(_ items: [Item]) -> [Item] {
        var seen = Set<String>()
        var result: [Item] = []
        for item in items {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || seen.contains(id) { continue }
            if validate(item).isEmpty {
                seen.insert(id)
                result.append(item)
            }
        }
        return result
    }
}

/// Shared, deterministic local search used by the knowledge library, trackers,
/// and the cross-content search screen. It intentionally has no networking,
/// analytics, or persistence side effects.
enum LocalSearchEngine {

    enum Kind: String, CaseIterable, Hashable {
        case education
        case tracker
        case customTracker
        case medication
        case dailyLog
        case periodDay

        fileprivate var sortOrder: Int {
            switch self {
            case .education: return 0
            case .tracker: return 1
            case .customTracker: return 2
            case .medication: return 3
            case .dailyLog: return 4
            case .periodDay: return 5
            }
        }
    }

    struct Document: Identifiable, Equatable {
        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let body: String
        let keywords: [String]
        /// 日期类结果(每日记录、经期日)的真实日期。它们的标题是本地化后的日期
        /// 文本,按标题排序会变成按字符串排 —— "14 ago" 排在 "14 sep" 前面 ——
        /// 所以同分时改用这个日期从新到旧排。
        let sortDate: Date?

        init(id: String,
             kind: Kind,
             title: String,
             subtitle: String = "",
             body: String = "",
             keywords: [String] = [],
             sortDate: Date? = nil) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.keywords = keywords
            self.sortDate = sortDate
        }
    }

    struct Result: Identifiable, Equatable {
        let document: Document
        let score: Int

        var id: String { document.id }
    }

    private struct Field {
        let text: String
        let weight: Int
    }

    private struct ScoredDocument {
        let document: Document
        let score: Int
        let originalIndex: Int
    }

    /// Search with all query terms required. Terms may match exactly, by word
    /// prefix, as a substring, or with a small edit distance for typo tolerance.
    /// Results are ranked by title, subtitle, keyword, and body relevance, then
    /// by stable kind/title/id tie-breakers so edits do not make the list jump.
    static func search(_ documents: [Document], query: String, limit: Int? = nil) -> [Result] {
        let uniqueDocuments = deduplicated(documents)
        let normalizedQuery = normalize(query)
        let terms = uniqueTerms(tokenize(normalizedQuery))

        guard !terms.isEmpty else {
            let results = uniqueDocuments.map { Result(document: $0, score: 0) }
            return limited(results, limit: limit)
        }

        let scored = uniqueDocuments.enumerated().compactMap { index, document -> ScoredDocument? in
            guard let score = relevance(of: document, query: normalizedQuery, terms: terms) else {
                return nil
            }
            return ScoredDocument(document: document, score: score, originalIndex: index)
        }

        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.document.kind.sortOrder != rhs.document.kind.sortOrder {
                return lhs.document.kind.sortOrder < rhs.document.kind.sortOrder
            }
            if let l = lhs.document.sortDate, let r = rhs.document.sortDate, l != r {
                return l > r
            }
            let titleOrder = normalize(lhs.document.title).localizedCompare(normalize(rhs.document.title))
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if lhs.document.id != rhs.document.id { return lhs.document.id < rhs.document.id }
            return lhs.originalIndex < rhs.originalIndex
        }
        return limited(sorted.map { Result(document: $0.document, score: $0.score) }, limit: limit)
    }

    /// Normalization is shared by callers that want to display or pre-compute
    /// search state. It handles case, accents, width differences, punctuation,
    /// and repeated whitespace without changing the stored user content.
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { $0.isWhitespace }
            .joined(separator: " ")
    }

    // MARK: - Matching

    private static func relevance(of document: Document,
                                  query: String,
                                  terms: [String]) -> Int? {
        let fields = [
            Field(text: document.title, weight: 900),
            Field(text: document.subtitle, weight: 420),
            Field(text: document.body, weight: 150)
        ] + document.keywords.map { Field(text: $0, weight: 260) }

        let normalizedFields = fields.map { (normalize($0.text), $0.weight) }
        guard !normalizedFields.isEmpty else { return nil }

        var score = 0
        for term in terms {
            var best = 0
            for (field, weight) in normalizedFields where !field.isEmpty {
                best = max(best, termScore(term, in: field, weight: weight))
            }
            guard best > 0 else { return nil }
            score += best
        }

        if let title = normalizedFields.first?.0, !title.isEmpty {
            if title == query {
                score += 2_400
            } else if title.hasPrefix(query) {
                score += 1_250
            } else if title.contains(query) {
                score += 850
            }
        }
        if terms.count > 1 {
            score += 100 * terms.filter { query.contains($0) }.count
        }
        return score
    }

    private static func termScore(_ term: String, in field: String, weight: Int) -> Int {
        guard !term.isEmpty else { return 0 }
        let words = tokenize(field)
        guard !words.isEmpty else { return 0 }

        if words.contains(term) {
            return weight + 230
        }
        if words.contains(where: { $0.hasPrefix(term) }) {
            return weight + 155
        }
        if field.contains(term) {
            return weight + 95
        }

        // Fuzzy matching is deliberately conservative: it helps with a short
        // typo, but does not turn a one-character query into a broad match.
        guard term.count >= 3 else { return 0 }
        let threshold = term.count >= 7 ? 2 : 1
        let distance = words.map { levenshtein(term, $0) }.min() ?? Int.max
        guard distance <= threshold else { return 0 }
        return max(1, weight + 55 - distance * 18)
    }

    private static func tokenize(_ value: String) -> [String] {
        value.split { character in
            !(character.isLetter || character.isNumber)
        }.map(String.init)
    }

    private static func uniqueTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }

    private static func deduplicated(_ documents: [Document]) -> [Document] {
        var seen = Set<String>()
        return documents.filter { seen.insert($0.id).inserted }
    }

    private static func limited(_ results: [Result], limit: Int?) -> [Result] {
        guard let limit, limit >= 0 else { return results }
        return Array(results.prefix(limit))
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1]
            current.reserveCapacity(b.count + 1)
            for (j, right) in b.enumerated() {
                let insertion = current[j] + 1
                let deletion = previous[j + 1] + 1
                let substitution = previous[j] + (left == right ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Stable, local-only navigation contract for a search result.  Keeping the
/// ID parsing separate from SwiftUI makes date/UUID failures explicit and
/// testable before a destination view is built.
enum LocalSearchNavigationTarget: Equatable {
    case education(id: String)
    case tracker(key: String)
    case customTracker(key: String)
    case medication(id: UUID)
    case dailyLog(dayKey: Int)
    case periodDay(dayKey: Int)

    static func resolve(_ document: LocalSearchEngine.Document) -> Self? {
        let parts = document.id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let prefix = String(parts[0])
        let value = String(parts[1])
        guard !value.isEmpty else { return nil }

        switch document.kind {
        case .education:
            guard prefix == "education" else { return nil }
            return .education(id: value)
        case .tracker:
            guard prefix == "tracker" else { return nil }
            return .tracker(key: value)
        case .customTracker:
            guard prefix == "customTracker" else { return nil }
            return .customTracker(key: value)
        case .medication:
            guard prefix == "medication", let id = UUID(uuidString: value) else { return nil }
            return .medication(id: id)
        case .dailyLog:
            guard prefix == "dailyLog", let dayKey = Int(value), date(forDayKey: dayKey) != nil else {
                return nil
            }
            return .dailyLog(dayKey: dayKey)
        case .periodDay:
            guard prefix == "periodDay", let dayKey = Int(value), date(forDayKey: dayKey) != nil else {
                return nil
            }
            return .periodDay(dayKey: dayKey)
        }
    }

    /// Returns nil instead of silently opening the Unix epoch for malformed
    /// yyyymmdd values.  `DayKey` remains the single source of truth for the
    /// actual date conversion.
    static func date(forDayKey dayKey: Int) -> Date? {
        guard dayKey > 0 else { return nil }
        let date = DayKey.date(from: dayKey)
        return DayKey.from(date) == dayKey ? date : nil
    }

    var date: Date? {
        switch self {
        case .dailyLog(let dayKey), .periodDay(let dayKey):
            return Self.date(forDayKey: dayKey)
        default:
            return nil
        }
    }
}
