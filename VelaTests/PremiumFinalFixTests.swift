import XCTest
@testable import Vela

final class PremiumFinalFixTests: XCTestCase {
    func testFreeClinicalReportExportIsFixedToSixMonthsWithoutNotes() {
        let options = ClinicalReportAccessPolicy.effectiveOptions(
            premium: false,
            selectedRange: .all,
            includeNotes: true)

        XCTAssertEqual(options.range, .sixMonths)
        XCTAssertFalse(options.includeNotes)
    }

    func testPremiumClinicalReportExportKeepsSelectedOptions() {
        let options = ClinicalReportAccessPolicy.effectiveOptions(
            premium: true,
            selectedRange: .twelveMonths,
            includeNotes: true)

        XCTAssertEqual(options.range, .twelveMonths)
        XCTAssertTrue(options.includeNotes)
    }

    func testCorrelationOverviewLabelsRecordCoverageInsteadOfPairwiseN() {
        let label = CorrelationExplorerSummary.recordCountLabel(17)

        XCTAssertTrue(label.contains("17"))
        XCTAssertFalse(label.hasPrefix("N ="))
    }

    func testPremiumDowngradePlanCancelsOnlyPremiumRequestsAndRebuildsFreeBases() {
        let medicationID = "vela.med.123"
        let pending = [
            PremiumReminderDowngradePlan.dailyIdentifier,
            PremiumReminderDowngradePlan.periodIdentifier,
            medicationID,
            "\(medicationID).s0",
            "\(medicationID).s1.w2",
            PremiumReminderDowngradePlan.pmsIdentifier,
            PremiumReminderDowngradePlan.smartIdentifier,
            "vela.other.request"
        ]

        let plan = PremiumReminderDowngradePlan.make(pendingIdentifiers: pending)

        XCTAssertTrue(plan.idsToCancel.contains(PremiumReminderDowngradePlan.pmsIdentifier))
        XCTAssertTrue(plan.idsToCancel.contains(PremiumReminderDowngradePlan.smartIdentifier))
        XCTAssertTrue(plan.idsToCancel.contains("\(medicationID).s0"))
        XCTAssertTrue(plan.idsToCancel.contains("\(medicationID).s1.w2"))
        XCTAssertTrue(plan.idsToCancel.contains(PremiumReminderDowngradePlan.periodIdentifier))
        XCTAssertFalse(plan.idsToCancel.contains(PremiumReminderDowngradePlan.dailyIdentifier))
        XCTAssertFalse(plan.idsToCancel.contains(medicationID))
        XCTAssertEqual(plan.medicationIDsToRebuild, [medicationID])
        XCTAssertTrue(plan.rebuildPeriod)
    }

    func testPremiumDowngradePlanRejectsNonSlotMedicationIdentifiers() {
        let pending = [
            "vela.med.123",
            "vela.med.123.s0.bad",
            "vela.med.123.sx",
            "vela.med.123.s0.w8"
        ]

        let plan = PremiumReminderDowngradePlan.make(pendingIdentifiers: pending)

        XCTAssertTrue(plan.medicationIDsToRebuild.isEmpty)
        XCTAssertFalse(plan.idsToCancel.contains("vela.med.123"))
    }

    func testEntitlementTransitionOnlyTriggersOnVerifiedDowngrade() {
        XCTAssertTrue(PremiumEntitlementTransition.didDowngrade(from: true, to: false))
        XCTAssertFalse(PremiumEntitlementTransition.didDowngrade(from: false, to: false))
        XCTAssertFalse(PremiumEntitlementTransition.didDowngrade(from: false, to: true))
        XCTAssertFalse(PremiumEntitlementTransition.didDowngrade(from: true, to: true))
    }

    func testNoEntitlementSnapshotReconcilesStaleNotificationsOnStartup() {
        XCTAssertTrue(PremiumEntitlementTransition.shouldReconcileNotifications(forEntitledValue: false))
        XCTAssertFalse(PremiumEntitlementTransition.shouldReconcileNotifications(forEntitledValue: true))
        // The policy is intentionally independent of the previous in-memory
        // value, covering both startup false→false and true→false expiry.
        XCTAssertTrue(PremiumEntitlementTransition.shouldReconcileNotifications(forEntitledValue: false))
    }

    func testConsecutivePeriodReconcileKeepsFreeReminderStable() {
        XCTAssertEqual(PremiumPeriodReminderPolicy.action(leadDays: 4), .rebuild)
        XCTAssertEqual(PremiumPeriodReminderPolicy.action(leadDays: 2), .keep)
        XCTAssertEqual(PremiumPeriodReminderPolicy.action(from: [
            PremiumPeriodReminderPolicy.leadDaysUserInfoKey: 2
        ]), .keep)
    }

    func testLegacyPeriodReminderWithoutMetadataIsCancelledOnce() {
        XCTAssertEqual(PremiumPeriodReminderPolicy.action(leadDays: nil), .cancelLegacy)
        XCTAssertEqual(PremiumPeriodReminderPolicy.action(from: [:]), .cancelLegacy)
    }
}
