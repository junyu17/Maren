import SwiftUI
import SwiftData

struct EducationLibraryView: View {
    @State private var allItems: [EducationCatalog.Item] = []
    @State private var searchText = ""
    @State private var selectedCategory: EducationCatalog.Category? = nil
    @State private var showError = false
    @State private var errorMessage = ""

    @AppStorage("education.bookmarks") private var bookmarksData = ""

    private var bookmarkedIDs: Set<String> {
        guard !bookmarksData.isEmpty else { return [] }
        return Set(bookmarksData.split(separator: ",").map(String.init))
    }

    private var filteredItems: [EducationCatalog.Item] {
        let items = EducationCatalog.search(allItems, query: searchText)
        if let cat = selectedCategory {
            return EducationCatalog.filter(items, category: cat)
        }
        return items
    }

    private var featuredItem: EducationCatalog.Item? {
        filteredItems.first
    }

    private var savedItems: [EducationCatalog.Item] {
        allItems.filter { bookmarkedIDs.contains($0.id) }
    }

    private var remainingItems: [EducationCatalog.Item] {
        guard let featured = featuredItem else { return filteredItems }
        return filteredItems.filter { $0.id != featured.id }
    }

    var body: some View {
        Group {
            if allItems.isEmpty && !showError {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                ContentUnavailableView {
                    Label(searchText.isEmpty && selectedCategory == nil
                          ? String(localized: "暂无文章")
                          : String(localized: "没有找到匹配的文章"),
                          systemImage: "doc.text.magnifyingglass")
                } description: {
                    if !searchText.isEmpty || selectedCategory != nil {
                        Text(String(localized: "尝试调整搜索词或筛选条件。"))
                    } else {
                        Text(String(localized: "教育内容加载为空。"))
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Featured hero
                        if let featured = featuredItem {
                            NavigationLink {
                                EducationArticleView(
                                    item: featured,
                                    isBookmarked: bookmarkedIDs.contains(featured.id)
                                ) { isBookmarked in
                                    toggleBookmark(featured.id, isBookmarked: isBookmarked)
                                }
                            } label: {
                                EducationCover(
                                    category: featured.category,
                                    title: EducationCatalog.localized(featured.title),
                                    summary: EducationCatalog.localized(featured.summary),
                                    isBookmarked: bookmarkedIDs.contains(featured.id),
                                    readingCue: String(localized: "阅读全文")
                                )
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }
                            .buttonStyle(.plain)
                        }

                        // Category chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                CategoryChip(
                                    title: String(localized: "全部"),
                                    isSelected: selectedCategory == nil
                                ) {
                                    selectedCategory = nil
                                }
                                ForEach(EducationCatalog.Category.allCases) { cat in
                                    CategoryChip(
                                        title: cat.label,
                                        isSelected: selectedCategory == cat
                                    ) {
                                        selectedCategory = cat
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        // Saved section
                        if searchText.isEmpty && selectedCategory == nil && !savedItems.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(String(localized: "已收藏"))
                                    .font(.headline.weight(.semibold))
                                    .padding(.horizontal, 16)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(savedItems) { item in
                                            NavigationLink {
                                                EducationArticleView(
                                                    item: item,
                                                    isBookmarked: true
                                                ) { isBookmarked in
                                                    toggleBookmark(item.id, isBookmarked: isBookmarked)
                                                }
                                            } label: {
                                                SavedCard(
                                                    title: EducationCatalog.localized(item.title),
                                                    category: item.category
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        // All content rows
                        VStack(spacing: 0) {
                            ForEach(remainingItems) { item in
                                NavigationLink {
                                    EducationArticleView(
                                        item: item,
                                        isBookmarked: bookmarkedIDs.contains(item.id)
                                    ) { isBookmarked in
                                        toggleBookmark(item.id, isBookmarked: isBookmarked)
                                    }
                                } label: {
                                    CompactRow(
                                        item: item,
                                        isBookmarked: bookmarkedIDs.contains(item.id)
                                    )
                                }
                                .buttonStyle(.plain)

                                if item.id != remainingItems.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.top, 4)

                        Color.clear.frame(height: 24)
                    }
                }
                .searchable(text: $searchText, prompt: String(localized: "搜索文章"))
                .accessibilityLabel(String(localized: "教育文章列表"))
            }
        }
        .navigationTitle(String(localized: "知识库"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    LocalSearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text("全局搜索"))
            }
        }
        .alert(String(localized: "加载失败"), isPresented: $showError) {
            Button(String(localized: "重试")) { loadItems() }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear(perform: loadItems)
    }

    private func loadItems() {
        let items = EducationCatalog.load()
        if items.isEmpty {
            showError = true
            errorMessage = String(localized: "无法加载本地教育内容，请稍后重试。")
        } else {
            allItems = items
        }
    }

    private func toggleBookmark(_ id: String, isBookmarked: Bool) {
        var set = bookmarkedIDs
        if isBookmarked {
            set.remove(id)
        } else {
            set.insert(id)
        }
        bookmarksData = set.joined(separator: ",")
    }
}

// MARK: - Cross-content local search

/// One local search surface for content that otherwise lives in separate tabs.
/// SwiftData @Query values are intentionally used directly, so deletion and
/// edits are reflected without a cache invalidation button or a network call.
struct LocalSearchView: View {
    @Query(sort: \CustomSymptom.createdAt) private var customSymptoms: [CustomSymptom]
    @Query(sort: \Medication.createdAt) private var medications: [Medication]
    @Query(sort: \DailyLog.dayKey, order: .reverse) private var dailyLogs: [DailyLog]
    @Query(sort: \PeriodDay.dayKey, order: .reverse) private var periodDays: [PeriodDay]

    @State private var educationItems: [EducationCatalog.Item] = []
    @State private var searchText: String
    @State private var selectedKind: LocalSearchEngine.Kind?
    @AppStorage("education.bookmarks") private var bookmarksData = ""

    init(initialQuery: String = "") {
        _searchText = State(initialValue: initialQuery)
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var documents: [LocalSearchEngine.Document] {
        var result = educationItems.map { item in
            LocalSearchEngine.Document(
                id: "education:\(item.id)",
                kind: .education,
                title: EducationCatalog.localized(item.title),
                subtitle: EducationCatalog.localized(item.summary),
                body: EducationCatalog.localized(item.body),
                keywords: [
                    item.title.zh, item.title.en,
                    item.summary.zh, item.summary.en,
                    item.body.zh, item.body.en,
                    item.category.label,
                    item.trackerTags.joined(separator: " "),
                    item.phaseTags.joined(separator: " "),
                    item.audienceTags.joined(separator: " ")
                ]
                + EducationCatalog.categorySearchTerms(item.category)
            )
        }

        result += TrackerCatalog.allEntries.map { entry in
            LocalSearchEngine.Document(
                id: "tracker:\(entry.key)",
                kind: .tracker,
                title: Symptoms.label(for: entry.key),
                subtitle: entry.category.label,
                keywords: [entry.key, entry.category.rawValue]
            )
        }

        result += customSymptoms.map { symptom in
            LocalSearchEngine.Document(
                id: "customTracker:\(symptom.key)",
                kind: .customTracker,
                title: symptom.label,
                subtitle: String(localized: "自定义追踪项"),
                keywords: [symptom.key, symptom.emoji]
            )
        }

        result += medications.map { medication in
            LocalSearchEngine.Document(
                id: "medication:\(medication.id.uuidString)",
                kind: .medication,
                title: medication.name,
                subtitle: medication.emoji,
                keywords: [String(localized: "用药与补剂")]
            )
        }

        result += dailyLogs.map { log in
            let symptomLabels = log.symptoms.map { Symptoms.label(for: $0) }.joined(separator: " ")
            let summary = [log.note, symptomLabels, log.mood?.label ?? ""]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            let dateText = LocalSearchView.dateFormatter.string(from: log.date)
            return LocalSearchEngine.Document(
                id: "dailyLog:\(log.dayKey)",
                kind: .dailyLog,
                title: dateText,
                subtitle: summary,
                body: summary,
                keywords: [String(log.dayKey), String(localized: "每日记录")]
            )
        }

        result += periodDays.map { period in
            let dateText = LocalSearchView.dateFormatter.string(from: period.date)
            return LocalSearchEngine.Document(
                id: "periodDay:\(period.dayKey)",
                kind: .periodDay,
                title: dateText,
                subtitle: period.flow.label,
                keywords: [String(period.dayKey), String(localized: "经期记录")]
            )
        }
        return result
    }

    private var results: [LocalSearchEngine.Result] {
        guard !trimmedQuery.isEmpty else { return [] }
        // Keep the count truthful and make every matching content type
        // reachable; the engine already ranks results, so the List can render
        // the complete local result set without a hidden 80-item cutoff.
        let all = LocalSearchEngine.search(documents, query: trimmedQuery)
        guard let selectedKind else { return all }
        return all.filter { $0.document.kind == selectedKind }
    }

    private var availableKinds: [LocalSearchEngine.Kind] {
        var seen = Set<LocalSearchEngine.Kind>()
        return LocalSearchEngine.search(documents, query: trimmedQuery)
            .compactMap { result in
                seen.insert(result.document.kind).inserted ? result.document.kind : nil
            }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = .current
        return formatter
    }()

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "开始搜索"), systemImage: "magnifyingglass")
                } description: {
                    Text(String(localized: "搜索文章、追踪项、用药和本地记录。"))
                }
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "没有找到匹配内容"), systemImage: "magnifyingglass")
                } description: {
                    Text(String(localized: "尝试调整搜索词或筛选条件。"))
                }
            } else {
                List {
                    if availableKinds.count > 1 {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    searchScopeChip(title: String(localized: "全部"), kind: nil)
                                    ForEach(availableKinds, id: \.self) { kind in
                                        searchScopeChip(title: kind.label, kind: kind)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        ForEach(results) { result in
                            NavigationLink {
                                destination(for: result)
                            } label: {
                                LocalSearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(verbatim: "\(results.count) \(String(localized: "个搜索结果"))")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(String(localized: "搜索"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: String(localized: "搜索文章、追踪项、用药和记录"))
        .onAppear {
            if educationItems.isEmpty { educationItems = EducationCatalog.load() }
        }
        .onChange(of: searchText) { _, _ in
            // A new query should never keep an old content-type scope hidden.
            selectedKind = nil
        }
    }

    @ViewBuilder
    private func searchScopeChip(title: String, kind: LocalSearchEngine.Kind?) -> some View {
        Button {
            selectedKind = kind
        } label: {
            Text(title)
                .font(.caption.weight(selectedKind == kind ? .semibold : .regular))
                .foregroundStyle(selectedKind == kind ? AppTheme.current.onAccent : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(
                    selectedKind == kind
                        ? AnyShapeStyle(AppTheme.current.accent)
                        : AnyShapeStyle(Color(.tertiarySystemBackground)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selectedKind == kind ? [.isSelected] : [])
    }

    @ViewBuilder
    private func destination(for result: LocalSearchEngine.Result) -> some View {
        if let target = LocalSearchNavigationTarget.resolve(result.document) {
            switch target {
            case .education(let id):
                if let item = educationItems.first(where: { $0.id == id }) {
                    EducationArticleView(
                        item: item,
                        isBookmarked: bookmarkedIDs.contains(item.id),
                        onBookmarkToggle: { isBookmarked in toggleBookmark(item.id, isBookmarked: isBookmarked) }
                    )
                } else {
                    ContentUnavailableView(String(localized: "内容已不可用"), systemImage: "doc.text")
                }
            case .tracker(let key), .customTracker(let key):
                // The picker receives the result title as its initial query,
                // so the matched control is the only visible/highlighted item.
                DailyLogView(
                    focusedTrackerQuery: result.document.title,
                    focusedTrackerKey: key
                )
            case .medication(let id):
                if let medication = medications.first(where: { $0.id == id }) {
                    MedicationManagerView(focusedMedication: medication)
                } else {
                    ContentUnavailableView(String(localized: "内容已不可用"), systemImage: "pills")
                }
            case .dailyLog(let dayKey), .periodDay(let dayKey):
                if let date = LocalSearchNavigationTarget.date(forDayKey: dayKey) {
                    if case .dailyLog = target {
                        DailyLogView(focusedDate: date)
                    } else {
                        CalendarView(focusedDate: date)
                    }
                } else {
                    ContentUnavailableView(String(localized: "内容已不可用"), systemImage: "calendar")
                }
            }
        } else {
            ContentUnavailableView(String(localized: "内容已不可用"), systemImage: "doc.text")
        }
    }

    private var bookmarkedIDs: Set<String> {
        guard !bookmarksData.isEmpty else { return [] }
        return Set(bookmarksData.split(separator: ",").map(String.init))
    }

    private func toggleBookmark(_ id: String, isBookmarked: Bool) {
        var values = bookmarkedIDs
        if isBookmarked {
            values.insert(id)
        } else {
            values.remove(id)
        }
        bookmarksData = values.joined(separator: ",")
    }
}

private extension LocalSearchEngine.Kind {
    var label: String {
        switch self {
        case .education: return String(localized: "文章")
        case .tracker: return String(localized: "内置追踪项")
        case .customTracker: return String(localized: "自定义追踪项")
        case .medication: return String(localized: "用药与补剂")
        case .dailyLog: return String(localized: "每日记录")
        case .periodDay: return String(localized: "经期记录")
        }
    }
}

private struct LocalSearchResultRow: View {
    let result: LocalSearchEngine.Result

    private var icon: String {
        switch result.document.kind {
        case .education: return "book.closed"
        case .tracker, .customTracker: return "checklist"
        case .medication: return "pills"
        case .dailyLog: return "heart.text.square"
        case .periodDay: return "drop.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppTheme.current.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.document.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(result.document.kind.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.current.accent)
                    if !result.document.subtitle.isEmpty {
                        Text(result.document.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(result.document.kind.label), \(result.document.title), \(result.document.subtitle)"))
    }
}

// MARK: - CategoryChip

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.current.onAccent : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    isSelected
                        ? AnyShapeStyle(AppTheme.current.accent)
                        : AnyShapeStyle(Color(.tertiarySystemBackground))
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - SavedCard

private struct SavedCard: View {
    let title: String
    let category: EducationCatalog.Category

    private var categoryIcon: String {
        switch category {
        case .general:          return "book.closed"
        case .menstrualHealth:  return "drop.fill"
        case .cyclePhases:      return "arrow.triangle.2.circlepath"
        case .perimenopause:    return "sparkles"
        case .nutrition:        return "leaf.fill"
        case .exercise:         return "figure.run"
        case .mentalWellbeing:  return "heart.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: categoryIcon)
                .font(.title3)
                .foregroundStyle(AppTheme.current.accent)

            Text(title)
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
        }
        .frame(width: 130, alignment: .leading)
        .frame(minHeight: 44, alignment: .topLeading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CompactRow

private struct CompactRow: View {
    let item: EducationCatalog.Item
    let isBookmarked: Bool

    private var localeTitle: String {
        EducationCatalog.localized(item.title)
    }

    private var categoryIcon: String {
        switch item.category {
        case .general:          return "book.closed"
        case .menstrualHealth:  return "drop.fill"
        case .cyclePhases:      return "arrow.triangle.2.circlepath"
        case .perimenopause:    return "sparkles"
        case .nutrition:        return "leaf.fill"
        case .exercise:         return "figure.run"
        case .mentalWellbeing:  return "heart.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: categoryIcon)
                .font(.body)
                .foregroundStyle(AppTheme.current.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(localeTitle)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)

                Text(item.category.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isBookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.current.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(localeTitle), \(item.category.label)")
        .accessibilityAddTraits(.isButton)
    }
}
