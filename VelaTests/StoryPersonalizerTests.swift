import Foundation
import XCTest
@testable import Vela

/// StoryPersonalizer 确定性选择与优先级测试。
final class StoryPersonalizerTests: XCTestCase {

    // MARK: - Fixtures (适配 EducationCatalog.Item 当前 [String] 标签合约)

    private func makeItem(id: String,
                          category: EducationCatalog.Category = .general,
                          trackerTags: [String] = [],
                          phaseTags: [String] = ["any"],
                          audienceTags: [String] = ["all"]) -> EducationCatalog.Item {
        EducationCatalog.Item(
            id: id,
            category: category,
            title: EducationCatalog.BilingualString(zh: id, en: id),
            summary: EducationCatalog.BilingualString(zh: "\(id)-summary", en: "\(id)-summary"),
            body: EducationCatalog.BilingualString(zh: "\(id)-body", en: "\(id)-body"),
            trackerTags: trackerTags,
            phaseTags: phaseTags,
            audienceTags: audienceTags
        )
    }

    private func context(items: [EducationCatalog.Item],
                         trackerKeys: Set<String> = [],
                         phase: String? = nil,
                         isPerimenopause: Bool = false,
                         recentIDs: [String] = [],
                         date: Date = Date()) -> StoryPersonalizer.Context {
        StoryPersonalizer.Context(
            items: items,
            date: date,
            trackerKeys: trackerKeys,
            phase: phase,
            isPerimenopause: isPerimenopause,
            recentIDs: recentIDs
        )
    }

    // MARK: - 空输入

    func testEmptyInputReturnsNil() {
        let result = StoryPersonalizer.select(from: context(items: []))
        XCTAssertNil(result)
    }

    // MARK: - 优先级: tracker > perimenopause > phase > general

    func testTrackerBeatsPerimenopause() {
        let items = [
            makeItem(id: "peri", category: .perimenopause, audienceTags: ["perimenopause"]),
            makeItem(id: "tracker", category: .menstrualHealth, trackerTags: ["cramps"]),
        ]
        let ctx = context(items: items, trackerKeys: ["cramps"], isPerimenopause: true)
        let result = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(result?.item.id, "tracker")
    }

    func testPerimenopauseBeatsPhase() {
        let items = [
            makeItem(id: "phase-hit", category: .cyclePhases, phaseTags: ["luteal"]),
            makeItem(id: "peri-hit", category: .perimenopause, audienceTags: ["perimenopause"]),
        ]
        let ctx = context(items: items, phase: "luteal", isPerimenopause: true)
        let result = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(result?.item.id, "peri-hit")
    }

    func testPhaseBeatsGeneral() {
        let items = [
            makeItem(id: "general", category: .general),
            makeItem(id: "phase-match", category: .cyclePhases, phaseTags: ["menstrual"]),
        ]
        let ctx = context(items: items, phase: "menstrual")
        let result = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(result?.item.id, "phase-match")
    }

    // MARK: - Recent 过滤

    func testRecentTrackerCannotBeatNonrecentGeneral() {
        let items = [
            makeItem(id: "recent-tracker", trackerTags: ["cramps"]),
            makeItem(id: "nonrecent-general", category: .general),
        ]
        let ctx = context(items: items, trackerKeys: ["cramps"], recentIDs: ["recent-tracker"])
        let result = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(result?.item.id, "nonrecent-general")
    }

    func testAllRecentFallbackWorks() {
        let items = [
            makeItem(id: "recent-a", category: .menstrualHealth, trackerTags: ["cramps"]),
            makeItem(id: "recent-b", category: .mentalWellbeing),
        ]
        let ctx = context(items: items, trackerKeys: ["cramps"],
                          recentIDs: ["recent-a", "recent-b"])
        let result = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(result?.item.id, "recent-a")
    }

    // MARK: - 任意 tracker key

    func testArbitraryTrackerKeyWorks() {
        let items = [
            makeItem(id: "matched", trackerTags: ["customKey123"]),
            makeItem(id: "other", category: .general),
        ]
        let ctx = context(items: items, trackerKeys: ["customKey123"])
        let result = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(result?.item.id, "matched")
    }

    // MARK: - 同日稳定

    func testSameDayStability() {
        let items = [
            makeItem(id: "x", phaseTags: ["menstrual"]),
            makeItem(id: "y", phaseTags: ["menstrual"]),
            makeItem(id: "z", phaseTags: ["menstrual"]),
        ]
        let date = DayKey.date(from: 20260101)
        let ctx = context(items: items, phase: "menstrual", date: date)
        let r1 = StoryPersonalizer.select(from: ctx)
        let r2 = StoryPersonalizer.select(from: ctx)
        XCTAssertEqual(r1?.item.id, r2?.item.id)
    }

    // MARK: - 异日旋转

    func testDifferentDayRotationAmongEqualCandidates() {
        let items = [
            makeItem(id: "a-item", phaseTags: ["menstrual"]),
            makeItem(id: "b-item", phaseTags: ["menstrual"]),
            makeItem(id: "c-item", phaseTags: ["menstrual"]),
        ]
        let date1 = DayKey.date(from: 20260101) // dayKey 20260101 % 3 = 0 → "a-item"
        let date2 = DayKey.date(from: 20260102) // dayKey 20260102 % 3 = 1 → "b-item"

        let ctx1 = context(items: items, phase: "menstrual", date: date1)
        let ctx2 = context(items: items, phase: "menstrual", date: date2)

        let r1 = StoryPersonalizer.select(from: ctx1)
        let r2 = StoryPersonalizer.select(from: ctx2)

        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertEqual(r1?.score, r2?.score, "等分候选应同分")
        XCTAssertNotEqual(r1?.item.id, r2?.item.id,
                          "不同天应旋转到不同候选")
    }

    // MARK: - Phase mapping

    func testPhaseStringMapping() {
        XCTAssertEqual(StoryPersonalizer.phaseString(from: .menstrual), "menstrual")
        XCTAssertEqual(StoryPersonalizer.phaseString(from: .follicular), "follicular")
        XCTAssertEqual(StoryPersonalizer.phaseString(from: .ovulatory), "ovulatory")
        XCTAssertEqual(StoryPersonalizer.phaseString(from: .luteal), "luteal")
        XCTAssertEqual(StoryPersonalizer.phaseString(from: .unknown), "unknown")
    }
}
