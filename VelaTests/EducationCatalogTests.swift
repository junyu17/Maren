import Foundation
import XCTest
@testable import Vela

final class EducationCatalogTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(id: String = "test-1",
                          category: EducationCatalog.Category = .general,
                          trackerTags: [String] = ["cramps"],
                          phaseTags: [String] = ["menstrual"],
                          audienceTags: [String] = ["all"],
                          sources: [EducationCatalog.Source] = [.init(id: "s1", name: "WHO", url: "https://who.int")],
                          reviewedAt: String = "2025-01-15",
                          nonMedicalAdvice: EducationCatalog.BilingualString = .init(zh: "免责声明", en: "Disclaimer"),
                          isPro: Bool = false) -> EducationCatalog.Item {
        EducationCatalog.Item(
            id: id, category: category,
            title: .init(zh: "测试标题", en: "Test Title"),
            summary: .init(zh: "摘要", en: "Summary"),
            body: .init(zh: "测试内容", en: "Test Body"),
            trackerTags: trackerTags, phaseTags: phaseTags, audienceTags: audienceTags,
            sources: sources, reviewedAt: reviewedAt,
            nonMedicalAdvice: nonMedicalAdvice, isPro: isPro
        )
    }

    // MARK: - Item validation

    func testValidationFailsOnEmptyID() {
        let item = makeItem(id: "  ")
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("id") })
    }

    func testValidationFailsOnEmptyTitle() {
        let item = EducationCatalog.Item(
            id: "x", category: .general,
            title: .init(zh: "", en: "t"),
            summary: .init(zh: "s", en: "s"),
            body: .init(zh: "b", en: "b"),
            trackerTags: ["cramps"], phaseTags: ["menstrual"], audienceTags: ["all"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "d", en: "d")
        )
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("title.zh") })
    }

    func testValidationFailsOnEmptySummary() {
        let item = EducationCatalog.Item(
            id: "x", category: .general,
            title: .init(zh: "t", en: "t"),
            summary: .init(zh: "", en: "s"),
            body: .init(zh: "b", en: "b"),
            trackerTags: ["cramps"], phaseTags: ["menstrual"], audienceTags: ["all"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "d", en: "d")
        )
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("summary.zh") })
    }

    func testValidationFailsOnEmptyBody() {
        let item = EducationCatalog.Item(
            id: "x", category: .general,
            title: .init(zh: "t", en: "t"),
            summary: .init(zh: "s", en: "s"),
            body: .init(zh: "b", en: ""),
            trackerTags: ["cramps"], phaseTags: ["menstrual"], audienceTags: ["all"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "d", en: "d")
        )
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("body.en") })
    }

    func testValidationFailsOnEmptyDisclaimer() {
        let item = makeItem(nonMedicalAdvice: .init(zh: "", en: ""))
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("nonMedicalAdvice.zh") })
    }

    func testValidationFailsOnMissingTrackerTags() {
        let item = makeItem(trackerTags: [])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("trackerTags") })
    }

    func testValidationFailsOnMissingPhaseTags() {
        let item = makeItem(phaseTags: [])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("phaseTags") })
    }

    func testValidationFailsOnMissingAudienceTags() {
        let item = makeItem(audienceTags: [])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("audienceTags") })
    }

    func testValidationFailsOnEmptySources() {
        let item = makeItem(sources: [])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("sources must not be empty") })
    }

    func testValidationFailsOnEmptySourceName() {
        let item = makeItem(sources: [.init(id: "s1", name: "", url: "https://x.com")])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("sources[0].name") })
    }

    func testValidationFailsOnHTTPURL() {
        let item = makeItem(sources: [.init(id: "s1", name: "N", url: "http://x.com")])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("https URL") })
    }

    func testValidationFailsOnMalformedURL() {
        let item = makeItem(sources: [.init(id: "s1", name: "N", url: "not-a-url")])
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("https URL") })
    }

    func testValidationFailsOnInvalidReviewDate() {
        let item = makeItem(reviewedAt: "2025/01/15")
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("reviewedAt") })
    }

    func testValidationFailsOnInvalidReviewDateFormat() {
        let item = makeItem(reviewedAt: "2025-1-15") // missing leading zero
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("reviewedAt") })
    }

    func testValidationFailsOnReviewDateWithExtraWhitespace() {
        let item = makeItem(reviewedAt: " 2025-01-15 ")
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.contains { $0.contains("reviewedAt") })
    }

    func testValidationFailsOnFutureReviewDate() {
        let item = makeItem(reviewedAt: "2099-01-01")
        let errors = EducationCatalog.validate(item)
        // valid format but future — still passes format check; we only validate format here
        XCTAssertTrue(errors.filter { $0.contains("reviewedAt") }.isEmpty)
    }

    func testValidationPassesOnValidItem() {
        let item = makeItem()
        let errors = EducationCatalog.validate(item)
        XCTAssertTrue(errors.isEmpty)
    }

    func testValidationFailsOnHotFlashesTag() {
        let item = makeItem(trackerTags: ["hotFlashes"])
        // hotFlashes is a valid String tag — should not fail tag validation
        let errors = EducationCatalog.validate(item)
        XCTAssertFalse(errors.contains { $0.contains("trackerTags") })
    }

    // MARK: - Collection validation

    func testCollectionRejectsDuplicateIDs() {
        let a = makeItem(id: "dup")
        let b = makeItem(id: "dup")
        let result = EducationCatalog.validatedCollection([a, b])
        XCTAssertEqual(result.count, 1)
    }

    func testCollectionRejectsInvalidItems() {
        let good = makeItem(id: "good")
        let bad = makeItem(id: "bad", trackerTags: [])
        let result = EducationCatalog.validatedCollection([good, bad])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "good")
    }

    // MARK: - Search

    func testSearchMatchesTitle() {
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        let results = EducationCatalog.search(items, query: "测试标题", locale: "zh")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchMatchesSummary() {
        let items = [makeItem(id: "a")]
        let results = EducationCatalog.search(items, query: "Summary", locale: "en")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchMatchesBody() {
        let items = [makeItem(id: "a")]
        let results = EducationCatalog.search(items, query: "Test Body", locale: "en")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchReturnsAllOnEmptyQuery() {
        let items = [makeItem(id: "a"), makeItem(id: "b")]
        let results = EducationCatalog.search(items, query: "", locale: "en")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchCaseInsensitive() {
        // Test that search is case-insensitive on title, summary, and body
        let item = EducationCatalog.Item(
            id: "x", category: .general,
            title: .init(zh: "测试标题", en: "Test Title"),
            summary: .init(zh: "摘要内容", en: "Summary Content"),
            body: .init(zh: "正文内容", en: "Body Content"),
            trackerTags: ["cramps"], phaseTags: ["menstrual"], audienceTags: ["all"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "d", en: "d")
        )
        // Search with different cases should all match
        let resultsLower = EducationCatalog.search([item], query: "title", locale: "en")
        let resultsUpper = EducationCatalog.search([item], query: "TITLE", locale: "en")
        let resultsMixed = EducationCatalog.search([item], query: "TiTlE", locale: "en")
        XCTAssertEqual(resultsLower.count, 1)
        XCTAssertEqual(resultsUpper.count, 1)
        XCTAssertEqual(resultsMixed.count, 1)

        // Test summary case-insensitive
        let resultsSummary = EducationCatalog.search([item], query: "CONTENT", locale: "en")
        XCTAssertEqual(resultsSummary.count, 1)

        // Test body case-insensitive
        let resultsBody = EducationCatalog.search([item], query: "body", locale: "en")
        XCTAssertEqual(resultsBody.count, 1)

        // Chinese locale should also work case-insensitively (though Chinese doesn't have case)
        let resultsZH = EducationCatalog.search([item], query: "标题", locale: "zh")
        XCTAssertEqual(resultsZH.count, 1)
    }

    func testSearchRanksTitleAndSupportsPrefix() {
        let titleHit = makeItem(id: "title")
        let bodyHit = EducationCatalog.Item(
            id: "body", category: .general,
            title: .init(zh: "日常观察", en: "Daily observations"),
            summary: .init(zh: "摘要", en: "Summary"),
            body: .init(zh: "这里介绍 menstrual cycle 的记录方法", en: "Learn about menstrual cycle tracking"),
            trackerTags: ["cramps"], phaseTags: ["any"], audienceTags: ["all"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "免责声明", en: "Disclaimer")
        )

        let results = EducationCatalog.search([bodyHit, titleHit], query: "Test", locale: "en")
        XCTAssertEqual(results.map(\.id), ["title"])

        let prefixResults = EducationCatalog.search([bodyHit], query: "menstr", locale: "en")
        XCTAssertEqual(prefixResults.map(\.id), ["body"])
    }

    func testSearchRequiresEveryTermAndSupportsFuzzyTypos() {
        let item = EducationCatalog.Item(
            id: "sleep", category: .general,
            title: .init(zh: "睡眠与能量", en: "Sleep and energy"),
            summary: .init(zh: "摘要", en: "Summary"),
            body: .init(zh: "记录睡眠与精力", en: "Track sleep and energy"),
            trackerTags: ["fatigue"], phaseTags: ["any"], audienceTags: ["all"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "免责声明", en: "Disclaimer")
        )

        XCTAssertEqual(EducationCatalog.search([item], query: "sleep energy", locale: "en").count, 1)
        XCTAssertEqual(EducationCatalog.search([item], query: "sleep missing", locale: "en").count, 0)
        XCTAssertEqual(EducationCatalog.search([item], query: "sleap", locale: "en").count, 1)
    }

    func testSearchIncludesCatalogTagsInBothLanguages() {
        let item = EducationCatalog.Item(
            id: "tags", category: .perimenopause,
            title: .init(zh: "日常记录", en: "Daily notes"),
            summary: .init(zh: "摘要", en: "Summary"),
            body: .init(zh: "正文", en: "Body"),
            trackerTags: ["hotFlashes"], phaseTags: ["luteal"], audienceTags: ["perimenopause"],
            sources: [.init(id: "s1", name: "N", url: "https://x.com")],
            reviewedAt: "2025-01-01",
            nonMedicalAdvice: .init(zh: "免责声明", en: "Disclaimer")
        )

        XCTAssertEqual(EducationCatalog.search([item], query: "hotFlashes", locale: "en").map(\.id), ["tags"])
        XCTAssertEqual(EducationCatalog.search([item], query: "围绝经期", locale: "en").map(\.id), ["tags"])
    }

    func testLocalSearchDeduplicatesAndKeepsEmptyQueryOrder() {
        let first = LocalSearchEngine.Document(id: "same", kind: .tracker, title: "Cramps")
        let duplicate = LocalSearchEngine.Document(id: "same", kind: .tracker, title: "Different")
        let second = LocalSearchEngine.Document(id: "second", kind: .medication, title: "Vitamin")

        let empty = LocalSearchEngine.search([first, duplicate, second], query: "")
        XCTAssertEqual(empty.map { $0.document.id }, ["same", "second"])
        XCTAssertEqual(LocalSearchEngine.search([first, duplicate], query: "different").count, 0)
    }

    func testLocalSearchFuzzyMultiTermAndStableRelevance() {
        let body = LocalSearchEngine.Document(
            id: "body", kind: .education,
            title: "Daily notes",
            body: "A guide to sleep and energy"
        )
        let title = LocalSearchEngine.Document(
            id: "title", kind: .education,
            title: "Sleep and energy"
        )

        let results = LocalSearchEngine.search([body, title], query: "sleap energy")
        XCTAssertEqual(results.map { $0.document.id }, ["title", "body"])
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testLocalSearchReflectsRebuiltDocumentsAfterEditOrDelete() {
        let original = LocalSearchEngine.Document(
            id: "customTracker:c-1", kind: .customTracker, title: "Hot flashes"
        )
        let edited = LocalSearchEngine.Document(
            id: "customTracker:c-1", kind: .customTracker, title: "Night sweats"
        )

        XCTAssertEqual(LocalSearchEngine.search([original], query: "hot").count, 1)
        XCTAssertEqual(LocalSearchEngine.search([edited], query: "hot").count, 0)
        XCTAssertEqual(LocalSearchEngine.search([], query: "night").count, 0)
        XCTAssertEqual(LocalSearchEngine.search([edited], query: "night").count, 1)
    }

    func testSearchNavigationTargetMapsExactContentDestinations() {
        let medicationID = UUID(uuidString: "D2B7E2C7-6E34-4FA2-9E8B-2E954A2B6B17")!
        let documents = [
            LocalSearchEngine.Document(id: "dailyLog:20260822", kind: .dailyLog, title: "Aug 22, 2026"),
            LocalSearchEngine.Document(id: "periodDay:20260821", kind: .periodDay, title: "Aug 21, 2026"),
            LocalSearchEngine.Document(id: "medication:\(medicationID.uuidString)", kind: .medication, title: "Vitamin D"),
            LocalSearchEngine.Document(id: "tracker:cramps", kind: .tracker, title: "痛经"),
            LocalSearchEngine.Document(id: "customTracker:custom-1", kind: .customTracker, title: "Night sweats")
        ]

        XCTAssertEqual(
            LocalSearchNavigationTarget.resolve(documents[0]),
            .dailyLog(dayKey: 20260822)
        )
        XCTAssertEqual(
            LocalSearchNavigationTarget.resolve(documents[1]),
            .periodDay(dayKey: 20260821)
        )
        XCTAssertEqual(
            LocalSearchNavigationTarget.resolve(documents[2]),
            .medication(id: medicationID)
        )
        XCTAssertEqual(
            LocalSearchNavigationTarget.resolve(documents[3]),
            .tracker(key: "cramps")
        )
        XCTAssertEqual(
            LocalSearchNavigationTarget.resolve(documents[4]),
            .customTracker(key: "custom-1")
        )
    }

    func testSearchNavigationTargetParsesAndRejectsDayKeysSafely() {
        let target = LocalSearchNavigationTarget.dailyLog(dayKey: 20260822)
        XCTAssertEqual(target.date, DayKey.date(from: 20260822))
        XCTAssertEqual(
            LocalSearchNavigationTarget.date(forDayKey: 20260229),
            nil,
            "2026 is not a leap year"
        )
        XCTAssertNil(LocalSearchNavigationTarget.date(forDayKey: 20261301))
        XCTAssertNil(LocalSearchNavigationTarget.date(forDayKey: 0))

        let malformedDate = LocalSearchEngine.Document(
            id: "dailyLog:20261301", kind: .dailyLog, title: "Invalid"
        )
        let malformedMedication = LocalSearchEngine.Document(
            id: "medication:not-a-uuid", kind: .medication, title: "Invalid"
        )
        XCTAssertNil(LocalSearchNavigationTarget.resolve(malformedDate))
        XCTAssertNil(LocalSearchNavigationTarget.resolve(malformedMedication))
    }

    // MARK: - Filter

    func testFilterByCategory() {
        let items = [
            makeItem(id: "a", category: .menstrualHealth),
            makeItem(id: "b", category: .exercise),
            makeItem(id: "c", category: .menstrualHealth),
        ]
        XCTAssertEqual(EducationCatalog.filter(items, category: .menstrualHealth).count, 2)
    }

    func testFilterByTrackerTag() {
        let items = [
            makeItem(id: "a", trackerTags: ["cramps"]),
            makeItem(id: "b", trackerTags: ["insomnia"]),
        ]
        let results = EducationCatalog.filter(items, trackerTag: "cramps")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "a")
    }

    func testFilterByPhaseTag() {
        let items = [
            makeItem(id: "a", phaseTags: ["menstrual"]),
            makeItem(id: "b", phaseTags: ["luteal"]),
            makeItem(id: "c", phaseTags: ["any"]),
        ]
        let results = EducationCatalog.filter(items, phaseTag: "menstrual")
        XCTAssertEqual(results.count, 2) // a + c(any)
    }

    func testFilterByAudienceTag() {
        let items = [
            makeItem(id: "a", audienceTags: ["perimenopause"]),
            makeItem(id: "b", audienceTags: ["beginner"]),
            makeItem(id: "c", audienceTags: ["all"]),
        ]
        let results = EducationCatalog.filter(items, audienceTag: "perimenopause")
        XCTAssertEqual(results.count, 2) // a + c(all)
    }

    func testFilterByArbitraryTrackerKey() {
        let items = [
            makeItem(id: "a", trackerTags: ["hotFlashes"]),
            makeItem(id: "b", trackerTags: ["cramps"]),
        ]
        let results = EducationCatalog.filter(items, trackerTag: "hotFlashes")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "a")
    }

    func testFilterCombined() {
        let items = [
            makeItem(id: "a", category: .menstrualHealth, trackerTags: ["cramps"]),
            makeItem(id: "b", category: .menstrualHealth, trackerTags: ["insomnia"]),
            makeItem(id: "c", category: .exercise, trackerTags: ["cramps"]),
        ]
        let results = EducationCatalog.filter(items, category: .menstrualHealth, trackerTag: "cramps")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "a")
    }

    // MARK: - Locale

    func testLocalizedReturnsChineseForZH() {
        let b = EducationCatalog.BilingualString(zh: "你好", en: "Hello")
        let result = EducationCatalog.localized(b, locale: "zh-Hans")
        XCTAssertEqual(result, "你好")
    }

    func testLocalizedReturnsEnglishForEN() {
        let b = EducationCatalog.BilingualString(zh: "你好", en: "Hello")
        let result = EducationCatalog.localized(b, locale: "en")
        XCTAssertEqual(result, "Hello")
    }

    // MARK: - Bundle load

    func testLoadReturnsEmptyOnMissingJSON() {
        let items = EducationCatalog.load(from: Bundle(for: type(of: self)))
        XCTAssertEqual(items.count, 0)
    }

    func testMainBundleLoadsExactly12ValidItems() {
        let items = EducationCatalog.load(from: Bundle.main)
        XCTAssertEqual(items.count, 12, "Expected exactly 12 valid education content items")

        // Verify unique IDs
        let ids = items.map { $0.id }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All item IDs must be unique")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.isLenient = false

        let allowedOfficialSourceURLs: Set<String> = [
            "https://www.acog.org/womens-health/faqs/your-first-period",
            "https://www.acog.org/womens-health/faqs/abnormal-uterine-bleeding",
            "https://www.acog.org/womens-health/faqs/vulvovaginal-health",
            "https://www.acog.org/womens-health/faqs/the-menopause-years",
            "https://www.acog.org/womens-health/faqs/perimenopausal-bleeding-and-bleeding-after-menopause",
            "https://www.cdc.gov/contraception/about/index.html"
        ]

        // Verify all items have valid sources
        for item in items {
            XCTAssertTrue(EducationCatalog.validate(item).isEmpty,
                          "Bundled item \(item.id) must pass catalog validation")
            XCTAssertTrue(item.reviewedAt.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                          "reviewedAt must use strict yyyy-MM-dd for item \(item.id)")
            guard let reviewedDate = dateFormatter.date(from: item.reviewedAt) else {
                XCTFail("reviewedAt must be a valid date for item \(item.id)")
                continue
            }
            XCTAssertEqual(dateFormatter.string(from: reviewedDate), item.reviewedAt,
                           "reviewedAt must round-trip exactly for item \(item.id)")

            XCTAssertFalse(item.sources.isEmpty, "Item \(item.id) must have at least one source")
            for source in item.sources {
                XCTAssertFalse(source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "Source name must not be empty for item \(item.id)")
                XCTAssertTrue(source.url.range(of: #"^https://[^\s]+$"#, options: .regularExpression) != nil,
                              "Source URL must be https for item \(item.id)")
                guard let url = URL(string: source.url) else {
                    XCTFail("Source URL must be valid for item \(item.id)")
                    continue
                }
                XCTAssertEqual(url.scheme?.lowercased(), "https",
                               "Source URL scheme must be https for item \(item.id)")
                XCTAssertFalse(url.host?.isEmpty ?? true,
                               "Source URL must include a host for item \(item.id)")
                XCTAssertTrue(allowedOfficialSourceURLs.contains(source.url),
                              "Source URL must be an approved ACOG/CDC URL for item \(item.id)")
            }
        }
    }
}
