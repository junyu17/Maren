import Foundation
import UIKit
import XCTest
@testable import Vela

/// TrackerCatalog 稳定性回归测试。
/// 验证追踪项目录的完整性、向后兼容性和分类覆盖。
final class TrackerCatalogTests: XCTestCase {

    // MARK: - 1. 至少 80 个唯一非空 key

    func testAtLeast80UniqueNonEmptyKeys() {
        let keys = TrackerCatalog.allKeys
        XCTAssertGreaterThanOrEqual(keys.count, 80,
            "TrackerCatalog must contain at least 80 unique keys, found \(keys.count)")
        // 不允许空字符串
        XCTAssertFalse(keys.contains(""), "TrackerCatalog must not contain empty string keys")
    }

    // MARK: - 2. 全部 14 个 legacy key 仍然存在

    func testAll14LegacyKeysExist() {
        let legacyKeys: [String] = [
            "cramps", "headache", "bloating", "backache", "tender",
            "acne", "fatigue", "nausea", "cravings", "insomnia",
            "anxious", "irritable", "hairloss", "hirsutism",
        ]
        let catalogKeys = TrackerCatalog.allKeys
        for key in legacyKeys {
            XCTAssertTrue(catalogKeys.contains(key),
                "Legacy key '\(key)' must exist in TrackerCatalog")
        }
    }

    // MARK: - 3. 每个分类至少有 3 个条目

    func testEachCategoryHasMinimum3Entries() {
        for cat in TrackerCategory.allCases {
            let entries = TrackerCatalog.allEntries.filter { $0.category == cat }
            XCTAssertGreaterThanOrEqual(entries.count, 3,
                "Category '\(cat.rawValue)' must have at least 3 entries, found \(entries.count)")
        }
    }

    // MARK: - 4. 10 个分类全覆盖

    func testAll10CategoriesCovered() {
        let covered = Set(TrackerCatalog.allEntries.map(\.category))
        let all = Set(TrackerCategory.allCases)
        XCTAssertEqual(covered, all,
            "All 10 categories must have entries: missing \(all.subtracting(covered).map(\.rawValue))")
    }

    // MARK: - 5. 所有 key 唯一(无重复)

    func testAllKeysAreUnique() {
        let keys = TrackerCatalog.allEntries.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count,
            "TrackerCatalog must not have duplicate keys")
    }

    // MARK: - 6. 每个内置 key 都有非空标签

    func testAllBuiltInKeysHaveNonEmptyLabels() {
        for entry in TrackerCatalog.allEntries {
            let label = Symptoms.label(for: entry.key)
            XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty,
                "Label for key '\(entry.key)' must not be empty")
        }
    }

    // MARK: - 7. label(for:) 对未知 key 返回 key 本身(fallback)

    func testLabelFallbackForUnknownKey() {
        let unknownKey = "zzz_unknown_key_\(UUID().uuidString)"
        XCTAssertEqual(Symptoms.label(for: unknownKey), unknownKey,
            "label(for:) should return the key itself for unknown keys")
    }

    // MARK: - 8. tag(for:) 对未知 key 返回 fallback tag

    func testTagFallbackForUnknownKey() {
        let unknownKey = "zzz_fallback_\(UUID().uuidString)"
        let tag = Symptoms.tag(for: unknownKey)
        XCTAssertEqual(tag.key, unknownKey)
        XCTAssertEqual(tag.label, unknownKey)
        XCTAssertEqual(tag.emoji, "•")
    }

    // MARK: - 9. tag(for:) 已知 key 返回正确 emoji

    func testTagForKnownKeyReturnsCorrectEmoji() {
        let tag = Symptoms.tag(for: "cramps")
        XCTAssertEqual(tag.emoji, "🩸")
        XCTAssertEqual(tag.key, "cramps")
    }

    // MARK: - 10. Symptoms.tags(for:) 返回对应分类条目

    func testSymptomsTagsForCategoryReturnsCorrectItems() {
        let moodTags = Symptoms.tags(for: .mood)
        let moodKeys = Set(moodTags.map(\.key))
        // 验证 mood 分类的关键 legacy key 存在
        XCTAssertTrue(moodKeys.contains("anxious"), "anxious should be in mood category")
        XCTAssertTrue(moodKeys.contains("irritable"), "irritable should be in mood category")
        // 标签不为空
        for tag in moodTags {
            XCTAssertFalse(tag.label.isEmpty, "Mood tag '\(tag.key)' must have a label")
        }
    }

    // MARK: - 11. categoryByKey 映射与 entries 一致

    func testCategoryByKeyMappingConsistent() {
        for entry in TrackerCatalog.allEntries {
            XCTAssertEqual(TrackerCatalog.categoryByKey[entry.key], entry.category,
                "categoryByKey mismatch for key '\(entry.key)'")
        }
    }

    // MARK: - 12. 没有空 key 或含空白符的 key

    func testNoEmptyOrWhitespaceKeys() {
        for entry in TrackerCatalog.allEntries {
            XCTAssertFalse(entry.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Key must not be empty or whitespace-only")
            XCTAssertFalse(entry.key.contains(" "),
                "Key '\(entry.key)' must not contain spaces")
        }
    }

    // MARK: - 13. 每个 TrackerCatalog entry 解析到非 bullet 的 SymptomTag(key 匹配)

    func testEveryCatalogEntryResolvesToNonFallbackTag() {
        for entry in TrackerCatalog.allEntries {
            let tag = Symptoms.tag(for: entry.key)
            XCTAssertEqual(tag.key, entry.key,
                "tag(for:) key mismatch for '\(entry.key)': got '\(tag.key)'")
            XCTAssertNotEqual(tag.emoji, "•",
                "tag(for:) returned bullet fallback for catalog key '\(entry.key)'")
        }
    }

    // MARK: - 14. allTags 覆盖全部 TrackerCatalog key

    func testAllTagsCoversAllCatalogKeys() {
        let allTagKeys = Set(Symptoms.allTags.map(\.key))
        for entry in TrackerCatalog.allEntries {
            XCTAssertTrue(allTagKeys.contains(entry.key),
                "TrackerCatalog key '\(entry.key)' missing from Symptoms.allTags")
        }
    }

    // MARK: - 15. picker selectedTags 查找路径可解析每个 selected key

    func testPickerLookupResolvesEverySelectedKey() {
        let all = Symptoms.allTags
        let catalogKeys = TrackerCatalog.allKeys
        // 模拟用户选择了全部内置 key
        for key in catalogKeys {
            let resolved = all.first { $0.key == key }
            XCTAssertNotNil(resolved,
                "Picker lookup failed for catalog key '\(key)'")
            XCTAssertNotEqual(resolved?.emoji, "•",
                "Picker lookup returned bullet fallback for '\(key)'")
        }
    }

    // MARK: - 16. legacyKeys 集合与原始 14 条一致

    func testLegacyKeysSetMatchesOriginal14() {
        XCTAssertEqual(Symptoms.legacyKeys.count, 14,
            "legacyKeys must contain exactly 14 entries")
        let expected: Set<String> = [
            "cramps", "headache", "bloating", "backache", "tender",
            "acne", "fatigue", "nausea", "cravings", "insomnia",
            "anxious", "irritable", "hairloss", "hirsutism",
        ]
        XCTAssertEqual(Symptoms.legacyKeys, expected,
            "legacyKeys set does not match the original 14 legacy keys")
    }

    // MARK: - 17. 每个分类的视觉符号非空且可解析为 SF Symbol

    func testEveryCategoryHasResolvableNonEmptySymbol() {
        for cat in TrackerCategory.allCases {
            let v = TrackerCatalog.visual(forCategory: cat)
            XCTAssertFalse(v.symbol.trimmingCharacters(in: .whitespaces).isEmpty,
                "Category '\(cat.rawValue)' visual symbol must not be empty")
            XCTAssertNotNil(UIImage(systemName: v.symbol),
                "Category '\(cat.rawValue)' visual symbol '\(v.symbol)' must resolve via UIImage(systemName:)")
        }
    }

    // MARK: - 18. 每个内置 key 解析到的视觉符号非空且可解析

    func testEveryCatalogEntryVisualResolvesToValidSymbol() {
        for entry in TrackerCatalog.allEntries {
            let v = TrackerCatalog.visual(for: entry.key)
            XCTAssertFalse(v.symbol.trimmingCharacters(in: .whitespaces).isEmpty,
                "Visual symbol for catalog key '\(entry.key)' must not be empty")
            XCTAssertNotNil(UIImage(systemName: v.symbol),
                "Visual symbol '\(v.symbol)' for catalog key '\(entry.key)' must resolve via UIImage(systemName:)")
        }
    }

    // MARK: - 19. 内置 key 的视觉契约(keyVisuals 或分类 fallback 必须存在)

    /// 契约:每个内置 key 通过 visual(for:) 都能解析到有效视觉 —— 要么在
    /// keyVisuals 中显式定义,要么回到所属分类的 categoryVisuals 默认值。
    func testEveryBuiltInKeyHasVisualContract() {
        for entry in TrackerCatalog.allEntries {
            if TrackerCatalog.keyVisuals[entry.key] == nil {
                // 不在 keyVisuals 中时,必须通过分类视觉兜底。
                XCTAssertNotNil(TrackerCatalog.categoryVisuals[entry.category],
                    "Built-in key '\(entry.key)' is not in keyVisuals and has no category fallback for '\(entry.category.rawValue)'")
            }
            // 无论如何,解析结果必须是有效 SF Symbol。
            let v = TrackerCatalog.visual(for: entry.key)
            XCTAssertNotNil(UIImage(systemName: v.symbol),
                "Built-in key '\(entry.key)' must resolve to a valid symbol")
        }
    }

    // MARK: - 20. 未知 key 的视觉 fallback 仍可解析为有效符号

    func testUnknownKeyVisualFallbackResolves() {
        let unknownKey = "zzz_unknown_visual_\(UUID().uuidString)"
        let v = TrackerCatalog.visual(for: unknownKey)
        XCTAssertFalse(v.symbol.trimmingCharacters(in: .whitespaces).isEmpty,
            "Unknown-key visual fallback symbol must not be empty")
        XCTAssertNotNil(UIImage(systemName: v.symbol),
            "Unknown-key visual fallback symbol '\(v.symbol)' must resolve via UIImage(systemName:)")
    }
}
