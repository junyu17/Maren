import Foundation
import XCTest

/// Static safeguards for the two shipped localizations.  This intentionally
/// reads the catalog as a release artifact instead of relying on the current
/// simulator locale, so missing English strings cannot hide behind Chinese
/// source fallbacks during review.
final class LocalizationCatalogTests: XCTestCase {
    private struct Catalog {
        let strings: [String: [String: Any]]

        init(projectRoot: URL) throws {
            let url = projectRoot.appendingPathComponent("Resources/Localizable.xcstrings")
            let data = try Data(contentsOf: url)
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rawStrings = try XCTUnwrap(object["strings"] as? [String: Any])
            strings = rawStrings.compactMapValues { $0 as? [String: Any] }
        }

        func value(for key: String, locale: String) -> String? {
            strings[key]?["localizations"]
                .flatMap { $0 as? [String: Any] }?[locale]
                .flatMap { $0 as? [String: Any] }?["stringUnit"]
                .flatMap { $0 as? [String: Any] }?["value"] as? String
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testEveryCatalogEntryHasTranslatedEnglishAndSimplifiedChineseValues() throws {
        let catalog = try Catalog(projectRoot: projectRoot)
        for (key, _) in catalog.strings {
            let english = try XCTUnwrap(catalog.value(for: key, locale: "en"), "Missing en value for \(key)")
            let simplifiedChinese = try XCTUnwrap(
                catalog.value(for: key, locale: "zh-Hans"),
                "Missing zh-Hans value for \(key)"
            )
            XCTAssertFalse(english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Empty en value for \(key)")
            XCTAssertFalse(simplifiedChinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Empty zh-Hans value for \(key)")
        }
    }

    func testNewSwiftUIFeatureKeysArePresentInBothLocales() throws {
        let catalog = try Catalog(projectRoot: projectRoot)
        let requiredKeys = [
            // Paywall and StoreKit
            "7 天免费试用",
            "开始 %lld 天免费试用",
            "购买并永久解锁",
            "最划算",
            "一次性付款，永久有效",
            "确认购买时将向你的 Apple ID 收费。一次性付款，永久有效，无续费。所有交易由 Apple 处理，我们不接触你的支付信息。",
            "确认购买时将向你的 Apple ID 收费。订阅会自动续期，除非在当前订阅期结束至少 24 小时前取消；账户会在当前订阅期结束前 24 小时内按所选方案收取续订费用。你可以在 App Store 账户设置中管理或取消订阅。",
            "开始 %lld 天免费试用时不会立即收费。试用结束后将按 %@ / 年自动续费；你可以在试用结束前取消，避免产生费用。",
            "开始 %@ 天免费试用时不会立即收费。试用结束后将按 %@ / 年自动续费；你可以在试用结束前取消，避免产生费用。",
            "确认订阅时将按 %@ 收费。订阅会自动续期，除非在当前订阅期结束至少 24 小时前取消；账户会在当前订阅期结束前 24 小时内按所选方案收取续订费用。你可以在 App Store 账户设置中管理或取消订阅。",
            "确认购买时将按 %@ 向你的 Apple ID 收费。一次性付款，永久有效，无续费。所有交易由 Apple 处理，我们不接触你的支付信息。",
            // Appearance
            "外观",
            "显示模式",
            "文字大小",
            "跟随系统",
            "系统默认",
            "浅色",
            "深色",
            "较小",
            "较大",
            // Live edits and deletion
            "记录与内容管理",
            "有外部更新影响了当前日期的记录。你要重新加载还是保留未保存的修改？",
            "保留我的修改",
            "本机记录已删除",
            "本机记录已删除,但未能刷新提醒和小组件。",
            "本机记录已删除,但未能同步删除 Apple Health 中的对应样本。请稍后在「健康」App 中手动检查。\n%@",
            "当天记录没有删除。",
            "删除当天记录",
            "暂时无法读取这一天的经期记录,未写入新数据。",
            "这一天的记录暂时无法读取,未清空当前草稿。",
            "读取失败",
            "要同步的健康数值无效,本机记录未修改",
            "有一笔交易未能通过签名校验,已跳过。",
            "这笔购买已验签,但当前权益已过期或已撤销。请点「恢复购买」重试。",
            "购买还在等待确认,通过后权益会自动生效。",
            "购买返回了未知状态,权益未生效。请重试。",
            "查到 %lld 笔无法验签的购买记录,权益未生效。请重试或联系 billy.yu@me.com。",
            "以下类型未能清理,因为 Maren 没有 HealthKit 写入权限: %@。请在「健康」App 中检查权限。",
            "以下类型清理失败: %@。你可以稍后重试;其他来源的 Health 数据不会被删除。",
            "经期已删除,但未能完整同步 Apple Health。",
            "提醒已达系统上限",
            "还没有添加任何用药或补剂。点右上角「＋」加一个,比如二甲双胍、肌醇、维生素 D。",
            // Reviews and new feature surfaces
            "回顾",
            "完成周期回顾",
            "周期概况",
            "周期均值",
            "有记录的天数",
            "已记录 %lld 天",
            "回顾数据基于你本机记录,为统计趋势洞察,不构成医学建议。",
            "经期与周期日历",
            "每日心情 / 症状打卡",
            "PMS 关怀与按阶段智能提醒",
            "经期提前天数自定义",
            "自定义日期范围生成结构化 PDF"
        ]

        for key in requiredKeys {
            let english = try XCTUnwrap(catalog.value(for: key, locale: "en"), "Missing en key: \(key)")
            let simplifiedChinese = try XCTUnwrap(
                catalog.value(for: key, locale: "zh-Hans"),
                "Missing zh-Hans key: \(key)"
            )
            XCTAssertFalse(english.isEmpty)
            XCTAssertFalse(simplifiedChinese.isEmpty)
        }
    }

    func testPrintfAndInterpolationPlaceholdersMatchSourceAndLocales() throws {
        let catalog = try Catalog(projectRoot: projectRoot)
        for (key, _) in catalog.strings {
            let english = try XCTUnwrap(catalog.value(for: key, locale: "en"))
            let simplifiedChinese = try XCTUnwrap(catalog.value(for: key, locale: "zh-Hans"))
            XCTAssertEqual(placeholderSignature(key), placeholderSignature(english), "en placeholder mismatch: \(key)")
            XCTAssertEqual(
                placeholderSignature(key),
                placeholderSignature(simplifiedChinese),
                "zh-Hans placeholder mismatch: \(key)"
            )
            XCTAssertEqual(interpolationTokens(key), interpolationTokens(english), "en interpolation mismatch: \(key)")
            XCTAssertEqual(
                interpolationTokens(key),
                interpolationTokens(simplifiedChinese),
                "zh-Hans interpolation mismatch: \(key)"
            )
        }
    }

    private func placeholderSignature(_ text: String) -> [[String]] {
        let pattern = #"%(?:(\d+)\$)?[-+0 #]*\d*(?:\.\d+)?(?:hh|h|ll|l|L)?([@diouxXfFeEgGaAcsp])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var implicitIndex = 1
        var result: [[String]] = []

        for match in regex.matches(in: text, range: range) {
            let positionRange = match.range(at: 1)
            let conversionRange = match.range(at: 2)
            let position: Int
            if let valueRange = Range(positionRange, in: text), !valueRange.isEmpty {
                position = Int(text[valueRange]) ?? implicitIndex
            } else {
                position = implicitIndex
                implicitIndex += 1
            }
            guard let valueRange = Range(conversionRange, in: text) else { continue }
            result.append([String(position), String(text[valueRange])])
        }
        return result.sorted { lhs, rhs in
            if lhs[0] == rhs[0] { return lhs[1] < rhs[1] }
            return lhs[0] < rhs[0]
        }
    }

    private func interpolationTokens(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\$\{[^}]+\}"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: text) else { return nil }
            return String(text[tokenRange])
        }.sorted()
    }
}
