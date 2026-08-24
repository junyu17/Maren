import Foundation
import XCTest
@testable import Vela

final class ContraceptionSettingsTests: XCTestCase {
    private var firstSuiteName = ""
    private var secondSuiteName = ""
    private var firstDefaults: UserDefaults!
    private var secondDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        firstSuiteName = "ContraceptionSettingsTests.first.\(UUID().uuidString)"
        secondSuiteName = "ContraceptionSettingsTests.second.\(UUID().uuidString)"
        firstDefaults = UserDefaults(suiteName: firstSuiteName)
        secondDefaults = UserDefaults(suiteName: secondSuiteName)
        XCTAssertNotNil(firstDefaults)
        XCTAssertNotNil(secondDefaults)
    }

    override func tearDown() {
        firstDefaults.removePersistentDomain(forName: firstSuiteName)
        secondDefaults.removePersistentDomain(forName: secondSuiteName)
        firstDefaults = nil
        secondDefaults = nil
        super.tearDown()
    }

    func testRoundTripUsesInjectedSuiteAndExportSnapshot() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_725_000_000)
        let original = ContraceptionSettings(
            method: .pill,
            startDayKey: 20260821,
            reminderEnabled: true,
            reminderHour: 8,
            reminderMinute: 15,
            note: "  personal note  ",
            updatedAt: updatedAt
        )

        XCTAssertTrue(original.save(to: firstDefaults))
        let loaded = ContraceptionSettings.load(from: firstDefaults)

        XCTAssertEqual(loaded, ContraceptionSettings(
            method: .pill,
            startDayKey: 20260821,
            reminderEnabled: true,
            reminderHour: 8,
            reminderMinute: 15,
            note: "personal note",
            updatedAt: updatedAt
        ))
        XCTAssertEqual(loaded.snapshot, original.snapshot)
        XCTAssertEqual(ContraceptionSettings.exportSnapshot(from: firstDefaults), loaded.snapshot)
    }

    func testAbsentAndCorruptDataUseSafeDefault() {
        XCTAssertEqual(ContraceptionSettings.load(from: firstDefaults).method, .none)

        firstDefaults.set(Data("not-json".utf8), forKey: ContraceptionSettings.storageKey)
        let fallback = ContraceptionSettings.load(from: firstDefaults)
        XCTAssertEqual(fallback.method, .none)
        XCTAssertNil(fallback.startDayKey)
        XCTAssertFalse(fallback.reminderEnabled)
        XCTAssertEqual(fallback.reminderHour, 9)
        XCTAssertEqual(fallback.reminderMinute, 0)
        XCTAssertEqual(fallback.note, "")
    }

    func testHourMinuteAreClampedAndNoteIsTrimmedAndCapped() {
        let longNote = String(repeating: "x", count: ContraceptionSettings.maxNoteLength + 50)
        let value = ContraceptionSettings(
            method: .pill,
            reminderHour: -4,
            reminderMinute: 90,
            note: " \n\(longNote) \n"
        )

        XCTAssertEqual(value.reminderHour, 0)
        XCTAssertEqual(value.reminderMinute, 59)
        XCTAssertEqual(value.note.count, ContraceptionSettings.maxNoteLength)
        XCTAssertFalse(value.note.hasPrefix(" "))
        XCTAssertFalse(value.note.hasSuffix(" "))

        var edited = value
        edited.reminderHour = 99
        edited.reminderMinute = -1
        XCTAssertTrue(edited.save(to: firstDefaults))
        let loaded = ContraceptionSettings.load(from: firstDefaults)
        XCTAssertEqual(loaded.reminderHour, 23)
        XCTAssertEqual(loaded.reminderMinute, 0)
    }

    func testResetRemovesOnlyTheInjectedProfile() {
        let value = ContraceptionSettings(method: .patch)
        value.save(to: firstDefaults)
        XCTAssertEqual(ContraceptionSettings.load(from: firstDefaults).method, .patch)

        ContraceptionSettings.reset(in: firstDefaults)

        XCTAssertEqual(ContraceptionSettings.load(from: firstDefaults).method, .none)
    }

    func testDailyReminderSupportIsExplicitAndClaimFree() {
        XCTAssertTrue(ContraceptionSettings.Method.pill.supportsDailyReminder)
        for method in ContraceptionSettings.Method.allCases where method != .pill {
            XCTAssertFalse(method.supportsDailyReminder, "Unexpected daily reminder for \(method.rawValue)")
        }
    }

    func testNoneMethodClearsDependentDetailsWhenSaved() {
        let value = ContraceptionSettings(
            method: .none,
            startDayKey: 20260821,
            reminderEnabled: true,
            note: "old detail"
        )
        XCTAssertTrue(value.save(to: firstDefaults))

        let loaded = ContraceptionSettings.load(from: firstDefaults)
        XCTAssertEqual(loaded.method, .none)
        XCTAssertNil(loaded.startDayKey)
        XCTAssertFalse(loaded.reminderEnabled)
        XCTAssertEqual(loaded.note, "")
    }

    func testDifferentSuitesAreIsolated() {
        ContraceptionSettings(method: .pill).save(to: firstDefaults)
        XCTAssertEqual(ContraceptionSettings.load(from: firstDefaults).method, .pill)
        XCTAssertEqual(ContraceptionSettings.load(from: secondDefaults).method, .none)

        ContraceptionSettings(method: .iud).save(to: secondDefaults)
        XCTAssertEqual(ContraceptionSettings.load(from: firstDefaults).method, .pill)
        XCTAssertEqual(ContraceptionSettings.load(from: secondDefaults).method, .iud)
    }
}
