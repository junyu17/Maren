import Foundation
import StoreKit
import StoreKitTest
import XCTest
@testable import Vela

/// StoreKit/Privacy 配置的回归测试。
/// 这些测试不触发真实购买，只校验提交前必须保持一致的静态契约。
final class StoreConfigurationTests: XCTestCase {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPremiumProductIdentifiersAreStableAndUnique() {
        XCTAssertEqual(Store.ProductID.all, [
            "cd.cc.vela.premium.yearly",
            "cd.cc.vela.premium.monthly",
            "cd.cc.vela.premium.lifetime"
        ])
        XCTAssertEqual(Set(Store.ProductID.all).count, 3)
    }

    func testLocalStoreKitHasCorrectPricesSubscriptionGroupAndLocalizations() throws {
        let url = projectRoot.appendingPathComponent("Maren.storekit")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let version = try XCTUnwrap(root["version"] as? [String: Any])
        XCTAssertEqual(version["major"] as? Int, 5)
        XCTAssertEqual(version["minor"] as? Int, 0)
        let appPolicies = try XCTUnwrap(root["appPolicies"] as? [String: Any])
        XCTAssertEqual(appPolicies["eula"] as? String, "")
        let settings = try XCTUnwrap(root["settings"] as? [String: Any])
        XCTAssertNil(settings["_applicationInternalID"], "Local StoreKit files must not remain bound to App Store Connect")
        XCTAssertNil(settings["_developerTeamID"], "Local StoreKit files must stay editable in Xcode")
        for key in ["_askToBuyEnabled", "_billingGracePeriodEnabled", "_billingIssuesEnabled", "_disableDialogs", "_failTransactionsEnabled", "_renewalBillingIssuesEnabled"] {
            XCTAssertEqual(settings[key] as? Bool, false, "Missing StoreKit v5 setting: \(key)")
        }
        let products = try XCTUnwrap(root["products"] as? [[String: Any]])
        let groups = try XCTUnwrap(root["subscriptionGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)

        let group = try XCTUnwrap(groups.first)
        let groupID = try XCTUnwrap(group["id"] as? String)
        let subscriptions = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])
        XCTAssertEqual(subscriptions.count, 2)

        let byID: [String: [String: Any]] = Dictionary(uniqueKeysWithValues: (products + subscriptions).compactMap { product in
            guard let id = product["productID"] as? String else { return nil }
            return (id, product)
        })
        XCTAssertEqual(Set(byID.keys), Set(Store.ProductID.all))
        XCTAssertEqual(byID[Store.ProductID.yearly]?["displayPrice"] as? String, "29.99")
        XCTAssertEqual(byID[Store.ProductID.monthly]?["displayPrice"] as? String, "3.99")
        XCTAssertEqual(byID[Store.ProductID.lifetime]?["displayPrice"] as? String, "69.99")

        for id in [Store.ProductID.yearly, Store.ProductID.monthly] {
            let subscription = try XCTUnwrap(byID[id])
            XCTAssertEqual(subscription["subscriptionGroupID"] as? String, groupID)
            XCTAssertEqual(subscription["groupNumber"] as? Int, 1)
            let localizations = try XCTUnwrap(subscription["localizations"] as? [[String: Any]])
            XCTAssertEqual(Set(localizations.compactMap { $0["locale"] as? String }), ["en_US", "zh_Hans"])
        }

        let groupLocalizations = try XCTUnwrap(group["localizations"] as? [[String: Any]])
        XCTAssertEqual(Set(groupLocalizations.compactMap { $0["locale"] as? String }), ["en_US", "zh_Hans"])
        let lifetimeLocalizations = try XCTUnwrap(byID[Store.ProductID.lifetime]?["localizations"] as? [[String: Any]])
        XCTAssertEqual(Set(lifetimeLocalizations.compactMap { $0["locale"] as? String }), ["en_US", "zh_Hans"])
    }

    func testPrivacyManifestDeclaresOnlyExpectedRequiredReasons() throws {
        let url = projectRoot.appendingPathComponent("Resources/PrivacyInfo.xcprivacy")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        let entries = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons: [String: Set<String>] = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            guard let category = entry["NSPrivacyAccessedAPIType"] as? String,
                  let values = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (category, Set(values))
        })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["3B52.1"])
    }

    func testBackupUTIIsAppInternalAndNotDeclaredAsSystemDocumentHandler() throws {
        let project = try String(contentsOf: projectRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertEqual(project.components(separatedBy: "UTTypeIdentifier: cd.cc.vela.encrypted-backup").count - 1, 1)
        XCTAssertFalse(project.contains("CFBundleDocumentTypes:"))
        XCTAssertTrue(project.contains("UTTypeConformsTo:"))
    }

    func testStoreNeverUsesUserDefaultsAsEntitlementAuthority() throws {
        let source = try String(contentsOf: projectRoot.appendingPathComponent("Sources/Support/Store.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("store.premium"))
        XCTAssertFalse(source.contains("UserDefaults.standard.bool(forKey:"))
        XCTAssertFalse(source.contains("UserDefaults.standard.set(true, forKey:"))
    }

    func testYearlySubscriptionHasSevenDayFreeTrialInStoreKit() throws {
        let url = projectRoot.appendingPathComponent("Maren.storekit")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(root["subscriptionGroups"] as? [[String: Any]])
        let group = try XCTUnwrap(groups.first)
        let subscriptions = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])

        let yearly = try XCTUnwrap(subscriptions.first { ($0["productID"] as? String) == Store.ProductID.yearly })
        let introOffers = try XCTUnwrap(yearly["introductoryOffers"] as? [[String: Any]])
        XCTAssertEqual(introOffers.count, 1)
        let introOffer = try XCTUnwrap(introOffers.first)
        XCTAssertEqual(introOffer["paymentMode"] as? String, "free")
        XCTAssertEqual(introOffer["subscriptionPeriod"] as? String, "P1W")
        XCTAssertEqual(introOffer["numberOfPeriods"] as? Int, 1)
        XCTAssertEqual(introOffer["billingPlanType"] as? String, "BILLED_UPFRONT")
    }

    func testMonthlySubscriptionHasNoIntroOffer() throws {
        let url = projectRoot.appendingPathComponent("Maren.storekit")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(root["subscriptionGroups"] as? [[String: Any]])
        let group = try XCTUnwrap(groups.first)
        let subscriptions = try XCTUnwrap(group["subscriptions"] as? [[String: Any]])

        let monthly = try XCTUnwrap(subscriptions.first { ($0["productID"] as? String) == Store.ProductID.monthly })
        let introOffers = try XCTUnwrap(monthly["introductoryOffers"] as? [[String: Any]])
        XCTAssertTrue(introOffers.isEmpty)
    }

    func testPaywallPricingUsesStorefrontValues() {
        XCTAssertEqual(
            PaywallPricing.savingsPercentage(yearlyPrice: Decimal(string: "29.99")!,
                                              monthlyPrice: Decimal(string: "3.99")!),
            37
        )
        XCTAssertNil(PaywallPricing.savingsPercentage(yearlyPrice: 48, monthlyPrice: 4))
        let equivalent = PaywallPricing.monthlyEquivalent(
            yearlyPrice: Decimal(string: "29.99")!)
        XCTAssertEqual(
            NSDecimalNumber(decimal: equivalent).doubleValue,
            29.99 / 12,
            accuracy: 0.000_000_001
        )
    }

    func testPaywallStrategyUsesSevenDayTrialOnlyForEligibleYearlyProduct() throws {
        let yearly = try XCTUnwrap(PaywallPurchaseStrategy.presentation(
            productID: Store.ProductID.yearly,
            displayName: "Annual Premium",
            displayPrice: "$29.99",
            eligibleTrialDays: 7
        ))
        XCTAssertEqual(yearly.kind, .yearly)
        XCTAssertEqual(yearly.displayName, "Annual Premium")
        XCTAssertEqual(yearly.displayPrice, "$29.99")
        XCTAssertEqual(yearly.cta, .startTrial(days: 7))
        XCTAssertEqual(yearly.billingDisclosure, .automaticRenewal(trialDays: 7, postTrialPrice: "$29.99"))

        let ineligibleYearly = try XCTUnwrap(PaywallPurchaseStrategy.presentation(
            productID: Store.ProductID.yearly,
            displayName: "Annual Premium",
            displayPrice: "￥218",
            eligibleTrialDays: nil
        ))
        XCTAssertEqual(ineligibleYearly.cta, .subscribe)
        XCTAssertEqual(ineligibleYearly.billingDisclosure, .automaticRenewal(trialDays: nil, postTrialPrice: nil))

        let nonSevenDayYearly = try XCTUnwrap(PaywallPurchaseStrategy.presentation(
            productID: Store.ProductID.yearly,
            displayName: "Annual Premium",
            displayPrice: "$29.99",
            eligibleTrialDays: 3
        ))
        XCTAssertEqual(nonSevenDayYearly.cta, .subscribe)
        XCTAssertEqual(nonSevenDayYearly.billingDisclosure, .automaticRenewal(trialDays: nil, postTrialPrice: nil))
    }

    func testPaywallStrategyNeverShowsTrialForMonthlyOrLifetime() throws {
        let monthly = try XCTUnwrap(PaywallPurchaseStrategy.presentation(
            productID: Store.ProductID.monthly,
            displayName: "Monthly Premium",
            displayPrice: "€3.99",
            eligibleTrialDays: 7
        ))
        XCTAssertEqual(monthly.kind, .monthly)
        XCTAssertEqual(monthly.cta, .subscribe)
        XCTAssertEqual(monthly.billingDisclosure, .automaticRenewal(trialDays: nil, postTrialPrice: nil))
        XCTAssertNil(monthly.trialDays)

        let lifetime = try XCTUnwrap(PaywallPurchaseStrategy.presentation(
            productID: Store.ProductID.lifetime,
            displayName: "Maren Lifetime",
            displayPrice: "£69.99",
            eligibleTrialDays: 7
        ))
        XCTAssertEqual(lifetime.kind, .lifetime)
        XCTAssertEqual(lifetime.cta, .purchase)
        XCTAssertEqual(lifetime.billingDisclosure, .oneTime)
        XCTAssertNil(lifetime.trialDays)
    }

    func testPaywallStrategyRejectsUnknownProducts() {
        XCTAssertNil(PaywallPurchaseStrategy.presentation(
            productID: "cd.cc.vela.premium.unknown",
            displayName: "Unknown",
            displayPrice: "$0.00",
            eligibleTrialDays: 7
        ))
    }

    func testPaywallSelectsDefaultPlanWithoutWaitingForTrialEligibility() {
        XCTAssertEqual(
            PaywallSelectionPolicy.defaultProductID(availableProductIDs: [
                Store.ProductID.monthly,
                Store.ProductID.yearly
            ]),
            Store.ProductID.yearly
        )
        XCTAssertEqual(
            PaywallSelectionPolicy.defaultProductID(availableProductIDs: [
                Store.ProductID.lifetime
            ]),
            Store.ProductID.lifetime
        )
        XCTAssertNil(PaywallSelectionPolicy.defaultProductID(availableProductIDs: []))
    }

    @MainActor
    func testLocalStoreKitSessionReturnsAllConfiguredProducts() async throws {
        let url = projectRoot.appendingPathComponent("Maren.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.resetToDefaultState() }

        let products = try await Product.products(for: Store.ProductID.all)
        XCTAssertEqual(Set(products.map(\.id)), Set(Store.ProductID.all))

        // Keep the per-ID query behavior visible too: it is the fallback used
        // by Store when a device-side StoreKit bridge returns an empty batch.
        var individuallyLoaded: [Product] = []
        for id in Store.ProductID.all {
            if let product = try await Product.products(for: [id]).first {
                individuallyLoaded.append(product)
            }
        }
        XCTAssertEqual(Set(individuallyLoaded.map(\.id)), Set(Store.ProductID.all))
    }
}
