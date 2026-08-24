import XCTest
@testable import Vela

/// QuickActionQueue 的单元测试。使用临时目录替代真实 App Group 容器,
/// 不依赖生产环境或网络。
final class QuickActionQueueTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickActionQueueTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 验证

    func testValidPeriodEntry() {
        let entry = QuickActionEntry.period(flowRaw: 2, dayKey: 20260820)
        XCTAssertTrue(QuickActionQueue.validate(entry))
    }

    func testValidMoodEntry() {
        let entry = QuickActionEntry.mood(moodRaw: 4, dayKey: 20260820)
        XCTAssertTrue(QuickActionQueue.validate(entry))
    }

    func testInvalidFlowRawTooHigh() {
        let entry = QuickActionEntry.period(flowRaw: 5, dayKey: 20260820)
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testInvalidMoodRawTooLow() {
        let entry = QuickActionEntry.mood(moodRaw: 0, dayKey: 20260820)
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testInvalidDayKeyYearTooEarly() {
        let entry = QuickActionEntry.period(flowRaw: 1, dayKey: 19990101)
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testInvalidFeb30() {
        let entry = QuickActionEntry.period(flowRaw: 1, dayKey: 20260230)
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testInvalidUnknownKind() {
        let entry = QuickActionEntry(id: UUID(), kind: "unknown",
                                     flowRaw: nil, moodRaw: nil,
                                     dayKey: 20260820, createdAt: Date())
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    // MARK: - 新增:period 必须有 flowRaw,mood 必须有 moodRaw

    func testPeriodWithNilFlowRawRejected() {
        let entry = QuickActionEntry(id: UUID(), kind: "period",
                                     flowRaw: nil, moodRaw: nil,
                                     dayKey: 20260820, createdAt: Date())
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testMoodWithNilMoodRawRejected() {
        let entry = QuickActionEntry(id: UUID(), kind: "mood",
                                     flowRaw: nil, moodRaw: nil,
                                     dayKey: 20260820, createdAt: Date())
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testPeriodWithExtraneousMoodRawRejected() {
        let entry = QuickActionEntry(id: UUID(), kind: "period",
                                     flowRaw: 2, moodRaw: 4,
                                     dayKey: 20260820, createdAt: Date())
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    func testMoodWithExtraneousFlowRawRejected() {
        let entry = QuickActionEntry(id: UUID(), kind: "mood",
                                     flowRaw: 2, moodRaw: 4,
                                     dayKey: 20260820, createdAt: Date())
        XCTAssertFalse(QuickActionQueue.validate(entry))
    }

    // MARK: - 入队 / 消费

    func testAppendAndPeekAcknowledge() {
        let entry = QuickActionEntry.period(flowRaw: 2, dayKey: 20260820)
        let groupID = tempDir.path
        QuickActionQueue.append(entry, to: groupID)
        let peeked = QuickActionQueue.peek(from: groupID)
        XCTAssertEqual(peeked.count, 1)
        XCTAssertEqual(peeked.first?.kind, "period")
        XCTAssertEqual(peeked.first?.flowRaw, 2)
        // acknowledge 移除
        QuickActionQueue.acknowledge([peeked[0].id], from: groupID)
        let after = QuickActionQueue.peek(from: groupID)
        XCTAssertTrue(after.isEmpty)
    }

    func testPeekEmptyReturnsEmpty() {
        let peeked = QuickActionQueue.peek(from: tempDir.path)
        XCTAssertTrue(peeked.isEmpty)
    }

    func testAcknowledgeIsIdempotent() {
        let entry = QuickActionEntry.mood(moodRaw: 3, dayKey: 20260820)
        QuickActionQueue.append(entry, to: tempDir.path)
        let peeked = QuickActionQueue.peek(from: tempDir.path)
        QuickActionQueue.acknowledge([peeked[0].id], from: tempDir.path)
        // 第二次 acknowledge 同一 ID 不应崩溃
        QuickActionQueue.acknowledge([peeked[0].id], from: tempDir.path)
        let entries = QuickActionQueue.peek(from: tempDir.path)
        XCTAssertTrue(entries.isEmpty)
    }

    func testBoundedQueueMaxEntries() {
        let groupID = tempDir.path
        for i in 0..<25 {
            let entry = QuickActionEntry.period(flowRaw: 1, dayKey: 20260101 + i)
            QuickActionQueue.append(entry, to: groupID)
        }
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertLessThanOrEqual(entries.count, QuickActionQueue.maxEntries)
    }

    func testDedupSameDaySameKind() {
        let groupID = tempDir.path
        let e1 = QuickActionEntry.period(flowRaw: 1, dayKey: 20260820)
        let e2 = QuickActionEntry.period(flowRaw: 3, dayKey: 20260820)
        QuickActionQueue.append(e1, to: groupID)
        QuickActionQueue.append(e2, to: groupID)
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.flowRaw, 3)
    }

    func testDifferentDayKeysAreDistinct() {
        let groupID = tempDir.path
        let e1 = QuickActionEntry.period(flowRaw: 1, dayKey: 20260820)
        let e2 = QuickActionEntry.period(flowRaw: 2, dayKey: 20260821)
        QuickActionQueue.append(e1, to: groupID)
        QuickActionQueue.append(e2, to: groupID)
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - 待处理计数

    func testPendingTodayCount() {
        let groupID = tempDir.path
        let today = QuickActionQueue.todayKey()
        QuickActionQueue.append(QuickActionEntry.period(flowRaw: 1, dayKey: today), to: groupID)
        QuickActionQueue.append(QuickActionEntry.mood(moodRaw: 3, dayKey: today), to: groupID)
        QuickActionQueue.append(QuickActionEntry.period(flowRaw: 2, dayKey: 20260801), to: groupID)
        let count = QuickActionQueue.pendingTodayCount(for: groupID, todayKey: today)
        XCTAssertEqual(count, 2)
    }

    // MARK: - 无效入队不写入

    func testInvalidEntryNotAppended() {
        let groupID = tempDir.path
        let entry = QuickActionEntry.period(flowRaw: 99, dayKey: 20260820)
        QuickActionQueue.append(entry, to: groupID)
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Peek 排序

    func testPeekReturnsSortedAscending() {
        let groupID = tempDir.path
        let e1 = QuickActionEntry.period(flowRaw: 1, dayKey: 20260820)
        let e2 = QuickActionEntry.mood(moodRaw: 3, dayKey: 20260821)
        QuickActionQueue.append(e1, to: groupID)
        QuickActionQueue.append(e2, to: groupID)
        let peeked = QuickActionQueue.peek(from: groupID)
        XCTAssertLessThanOrEqual(peeked[0].createdAt, peeked[1].createdAt)
    }

    // MARK: - todayKey

    func testTodayKeyIsValid() {
        let key = QuickActionQueue.todayKey()
        let year = key / 10_000
        let month = (key / 100) % 100
        let day = key % 100
        XCTAssertTrue((2000...2100).contains(year))
        XCTAssertTrue((1...12).contains(month))
        XCTAssertTrue((1...31).contains(day))
    }

    // MARK: - Mood flowRaw 边界

    func testMoodFlowRawBoundaries() {
        XCTAssertTrue(QuickActionQueue.validate(QuickActionEntry.mood(moodRaw: 1, dayKey: 20260820)))
        XCTAssertTrue(QuickActionQueue.validate(QuickActionEntry.mood(moodRaw: 5, dayKey: 20260820)))
        XCTAssertFalse(QuickActionQueue.validate(QuickActionEntry.mood(moodRaw: 6, dayKey: 20260820)))
        XCTAssertFalse(QuickActionQueue.validate(QuickActionEntry.mood(moodRaw: -1, dayKey: 20260820)))
    }

    func testFlowLevelBoundaries() {
        XCTAssertTrue(QuickActionQueue.validate(QuickActionEntry.period(flowRaw: 0, dayKey: 20260820)))
        XCTAssertTrue(QuickActionQueue.validate(QuickActionEntry.period(flowRaw: 3, dayKey: 20260820)))
        XCTAssertFalse(QuickActionQueue.validate(QuickActionEntry.period(flowRaw: -1, dayKey: 20260820)))
        XCTAssertFalse(QuickActionQueue.validate(QuickActionEntry.period(flowRaw: 4, dayKey: 20260820)))
    }

    // MARK: - Peek/Acknowledge 非破坏性读取

    func testPeekDoesNotRemoveEntries() {
        let groupID = tempDir.path
        let e1 = QuickActionEntry.period(flowRaw: 1, dayKey: 20260820)
        let e2 = QuickActionEntry.mood(moodRaw: 3, dayKey: 20260821)
        QuickActionQueue.append(e1, to: groupID)
        QuickActionQueue.append(e2, to: groupID)

        let peeked = QuickActionQueue.peek(from: groupID)
        XCTAssertEqual(peeked.count, 2)

        let afterPeek = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(afterPeek.count, 2)
    }

    func testAcknowledgeRemovesSpecificEntries() {
        let groupID = tempDir.path
        let e1 = QuickActionEntry.period(flowRaw: 1, dayKey: 20260820)
        let e2 = QuickActionEntry.mood(moodRaw: 3, dayKey: 20260821)
        QuickActionQueue.append(e1, to: groupID)
        QuickActionQueue.append(e2, to: groupID)

        QuickActionQueue.acknowledge([e1.id], from: groupID)
        let remaining = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, e2.id)
    }

    func testAcknowledgeEmptySetIsNoop() {
        let groupID = tempDir.path
        QuickActionQueue.append(QuickActionEntry.period(flowRaw: 1, dayKey: 20260820), to: groupID)
        QuickActionQueue.acknowledge([], from: groupID)
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(entries.count, 1)
    }

    func testClearRemovesAllEntriesAtomically() {
        let groupID = tempDir.path
        QuickActionQueue.append(QuickActionEntry.period(flowRaw: 1, dayKey: 20260820), to: groupID)
        QuickActionQueue.append(QuickActionEntry.mood(moodRaw: 4, dayKey: 20260821), to: groupID)

        XCTAssertTrue(QuickActionQueue.clear(from: groupID))
        XCTAssertTrue(QuickActionQueue.peek(from: groupID).isEmpty)
    }

    func testClearEmptyQueueSucceeds() {
        XCTAssertTrue(QuickActionQueue.clear(from: tempDir.path))
        XCTAssertTrue(QuickActionQueue.peek(from: tempDir.path).isEmpty)
    }

    func testClearFailsForInvalidGroupAndDoesNotClaimSuccess() {
        XCTAssertFalse(QuickActionQueue.clear(from: "com.nonexistent.invalid.group.id"))
    }

    func testClearFailsAndPreservesCorruptFile() throws {
        let groupID = tempDir.path
        let url = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.json")
        let lockURL = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.lock")
        FileManager.default.createFile(atPath: lockURL.path, contents: nil, attributes: nil)
        let corruptJSON = "not json"
        try corruptJSON.data(using: .utf8)?.write(to: url, options: [.atomic])

        XCTAssertFalse(QuickActionQueue.clear(from: groupID))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), corruptJSON)
    }

    // MARK: - Append 失败时返回 false

    func testAppendReturnsFalseForNilContainerURL() {
        let entry = QuickActionEntry.period(flowRaw: 2, dayKey: 20260820)
        // 故意使用无效的 App Group 标识符(不存在的群组),append 应返回 false
        let result = QuickActionQueue.append(entry, to: "com.nonexistent.invalid.group.id")
        XCTAssertFalse(result)
    }

    // MARK: - 并发追加(10 个独立合法条目)

    func testConcurrentAppendDoesNotLoseEntries() {
        let groupID = tempDir.path
        let count = 10
        let expectation = XCTestExpectation(description: "All concurrent appends complete")
        expectation.expectedFulfillmentCount = count

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        var appendResults = [Bool](repeating: false, count: count)
        let lock = NSLock()

        for i in 0..<count {
            queue.async {
                let entry = QuickActionEntry.period(flowRaw: i % 4, dayKey: 20260820 + i)
                let ok = QuickActionQueue.append(entry, to: groupID)
                lock.lock()
                appendResults[i] = ok
                lock.unlock()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // 断言:每次 append 都成功
        for i in 0..<count {
            XCTAssertTrue(appendResults[i], "Append \(i) should succeed")
        }

        // 断言:恰好 10 个不同条目,且 UUID 和 dayKey 均唯一
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(entries.count, count, "Exactly \(count) distinct entries should remain")
        let ids = Set(entries.map(\.id))
        XCTAssertEqual(ids.count, count, "All \(count) UUIDs must be unique")
        let dayKeys = Set(entries.map(\.dayKey))
        XCTAssertEqual(dayKeys.count, count, "All \(count) dayKeys must be unique")
    }

    // MARK: - 损坏 JSON 文件保留与 append 失败

    /// 验证:队列文件存在但 JSON 无效时,append 返回 false 且原文件被保留(不被覆盖)。
    func testAppendFailsAndPreservesCorruptFile() throws {
        let groupID = tempDir.path
        let url = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.json")
        let lockURL = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.lock")

        // 先创建锁文件(避免 openLockFD 失败)
        FileManager.default.createFile(atPath: lockURL.path, contents: nil, attributes: nil)

        // 写入损坏的 JSON
        let corruptJSON = "{ not valid json }"
        try corruptJSON.data(using: .utf8)?.write(to: url, options: [.atomic])

        // 此时文件存在且损坏
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // 尝试 append:应返回 false(文件损坏)
        let entry = QuickActionEntry.period(flowRaw: 2, dayKey: 20260820)
        let result = QuickActionQueue.append(entry, to: groupID)
        XCTAssertFalse(result, "Append should fail when queue file is corrupt")

        // 原文件应被保留(内容未变)
        let preserved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(preserved, corruptJSON, "Corrupt file must be preserved, not overwritten")

        // peek/read 也应返回空、不崩溃
        let peeked = QuickActionQueue.peek(from: groupID)
        XCTAssertTrue(peeked.isEmpty, "Peek should return empty for corrupt file")

        let read = QuickActionQueue.read(from: groupID)
        XCTAssertTrue(read.isEmpty, "Read should return empty for corrupt file")
    }

    /// 验证:队列文件不存在时(首次使用),append 成功、创建有效文件。
    func testAppendSucceedsWhenFileMissing() {
        let groupID = tempDir.path
        let url = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.json")

        // 确保文件不存在
        try? FileManager.default.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        // append 应成功
        let entry = QuickActionEntry.period(flowRaw: 2, dayKey: 20260820)
        let result = QuickActionQueue.append(entry, to: groupID)
        XCTAssertTrue(result, "Append should succeed when queue file is missing (first use)")

        // 文件应被创建且可读
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let entries = QuickActionQueue.read(from: groupID)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.flowRaw, 2)
    }

    /// 验证:损坏文件下 acknowledge 也返回 false、保留原文件。
    func testAcknowledgeFailsAndPreservesCorruptFile() throws {
        let groupID = tempDir.path
        let url = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.json")
        let lockURL = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.lock")

        FileManager.default.createFile(atPath: lockURL.path, contents: nil, attributes: nil)
        let corruptJSON = "[{ invalid }]"
        try corruptJSON.data(using: .utf8)?.write(to: url, options: [.atomic])

        let ids = Set([UUID()])
        let result = QuickActionQueue.acknowledge(ids, from: groupID)
        XCTAssertFalse(result, "Acknowledge should fail when queue file is corrupt")

        let preserved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(preserved, corruptJSON, "Corrupt file must be preserved on acknowledge failure")
    }

    /// 验证:损坏文件下 pendingTodayCount 返回 0、不崩溃。
    func testPendingTodayCountReturnsZeroForCorruptFile() throws {
        let groupID = tempDir.path
        let url = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.json")
        let lockURL = URL(fileURLWithPath: groupID).appendingPathComponent("quickaction.queue.lock")

        FileManager.default.createFile(atPath: lockURL.path, contents: nil, attributes: nil)
        let corruptJSON = "not json"
        try corruptJSON.data(using: .utf8)?.write(to: url, options: [.atomic])

        let count = QuickActionQueue.pendingTodayCount(for: groupID, todayKey: QuickActionQueue.todayKey())
        XCTAssertEqual(count, 0, "Pending count should be 0 for corrupt file")
    }
}
