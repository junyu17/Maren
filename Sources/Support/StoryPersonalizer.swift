import Foundation

/// V1.1 故事个性化选择器。给定候选条目和用户上下文,确定性地选一条最相关的内容。
enum StoryPersonalizer {

    struct Context {
        let items: [EducationCatalog.Item]
        let date: Date
        let trackerKeys: Set<String>
        let phase: String?
        let isPerimenopause: Bool
        let recentIDs: [String]
    }

    struct Selection {
        let item: EducationCatalog.Item
        let score: Int
    }

    // MARK: - 评分权重

    private enum Weight {
        static let tracker          = 400
        static let perimenopause    = 300
        static let exactPhase       = 200
        static let general          = 50
        static let phaseAnyOnly     = 10
        static let audienceAllOnly  = 5
    }

    // MARK: - 核心

    /// 确定性选择:同输入 → 同输出。
    ///
    /// **Recent 过滤**:若候选池中存在至少一条非 recent 条目,则**全部** recent 条目被移除;
    /// 仅当每一条候选都是 recent 时才保留 recent 参与评分(fallback)。
    ///
    /// **评分**tracker overlap 400 → perimenopause exact 300 → exact phase 200
    /// → general 50 → phase-any-only 10 → audience-all-only 5。
    ///
    /// **同分旋转**:等分候选按 id 稳定排序后,用 `DayKey.from(date) % count` 取
    /// 确定性索引,同一天稳定、不同天可旋转。
    static func select(from ctx: Context) -> Selection? {
        guard !ctx.items.isEmpty else { return nil }
        let recentSet = Set(ctx.recentIDs)

        // ── Recent 过滤 ──
        let hasNonRecent = ctx.items.contains { !recentSet.contains($0.id) }
        let candidates = hasNonRecent
            ? ctx.items.filter { !recentSet.contains($0.id) }
            : ctx.items

        // ── 评分 ──
        let scored = candidates.map { item -> (item: EducationCatalog.Item, score: Int) in
            var score = 0

            // tracker overlap: +400
            if item.trackerTags.contains(where: { ctx.trackerKeys.contains($0) }) {
                score += Weight.tracker
            }

            // perimenopause audience exact: +300
            if ctx.isPerimenopause && item.audienceTags.contains("perimenopause") {
                score += Weight.perimenopause
            }

            // exact phase: +200
            if let p = ctx.phase, item.phaseTags.contains(p) {
                score += Weight.exactPhase
            }

            // general category: +50
            if item.category == .general {
                score += Weight.general
            }

            // phase any only: +10 (exact phase 不命中时 "any" 作为兜底)
            if let p = ctx.phase, !item.phaseTags.contains(p), item.phaseTags.contains("any") {
                score += Weight.phaseAnyOnly
            }

            // audience all only fallback: +5 (perimenopause 不命中时 "all" 作为兜底)
            if item.audienceTags.contains("all")
                && !(ctx.isPerimenopause && item.audienceTags.contains("perimenopause")) {
                score += Weight.audienceAllOnly
            }

            return (item, score)
        }

        guard !scored.isEmpty else { return nil }

        // ── 稳定排序:score 降序 → id 字典序 ──
        let sorted = scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.item.id < $1.item.id
        }

        let bestScore = sorted[0].score
        let topItems = sorted.filter { $0.score == bestScore }

        // ── 同分旋转 ──
        if topItems.count == 1 {
            return Selection(item: topItems[0].item, score: bestScore)
        }
        let dayKey = DayKey.from(ctx.date)
        let index = dayKey % topItems.count
        return Selection(item: topItems[index].item, score: bestScore)
    }

    // MARK: - 辅助

    /// 将 CyclePhase 的 rawValue 映射到教育标签的 phase 字符串。
    static func phaseString(from phase: CyclePhase) -> String {
        switch phase {
        case .menstrual:  return "menstrual"
        case .follicular: return "follicular"
        case .ovulatory:  return "ovulatory"
        case .luteal:     return "luteal"
        case .unknown:    return "unknown"
        }
    }
}
