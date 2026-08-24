import Foundation

/// 无节点的快速操作队列。小组件/App Shortcuts 写入,主 app/手表 app 消费。
///
/// 设计要点:
///   - 基于 App Group 容器的 JSON 文件存储,原子写入;
///   - `.completeFileProtection` 文件保护(仅设备解锁时可读写);
///   - 有界队列(最多 `maxEntries` 条),防止无限增长;
///   - 幂等消费:peek + acknowledge 模式,已确认的条目不重复处理;
///   - 不暴露笔记文本或详细健康数据,仅存 kind + raw 值 + dayKey;
///   - 跨进程协调:用 POSIX flock 保证读写互斥;
///     LOCK_SH 用于 peek/read(共享),LOCK_EX 用于 append/acknowledge(排他)。
///   - 写时校验 flock 返回值,失败即返回 false,不损坏现有文件;
///   - 读取时区分「文件不存在」(合法空队列)与「文件存在但无法解码」(损坏,保留原文件、返回空并记录错误)。
struct QuickActionEntry: Codable, Equatable, Identifiable {
    let id: UUID
    /// "period" 或 "mood"。
    let kind: String
    /// 流量原始值(period 时使用,0-3)。
    var flowRaw: Int?
    /// 心情原始值(mood 时使用,1-5)。
    var moodRaw: Int?
    /// 目标日期 yyyymmdd 整数。
    let dayKey: Int
    /// 入队时刻,用于排序与去重。
    let createdAt: Date

    static func period(flowRaw: Int, dayKey: Int) -> QuickActionEntry {
        QuickActionEntry(id: UUID(), kind: "period", flowRaw: flowRaw, moodRaw: nil,
                         dayKey: dayKey, createdAt: Date())
    }
    static func mood(moodRaw: Int, dayKey: Int) -> QuickActionEntry {
        QuickActionEntry(id: UUID(), kind: "mood", flowRaw: nil, moodRaw: moodRaw,
                         dayKey: dayKey, createdAt: Date())
    }
}

enum QuickActionQueue {
    static let maxEntries = 20
    private static let fileName = "quickaction.queue.json"
    private static let lockFileName = "quickaction.queue.lock"

    /// Darwin 通知名:append 成功时发,主 app 活跃时可立即消费。
    static let appendedNotification = "cd.cc.vela.quickaction.appended"

    /// 进程内互斥锁,保护所有队列操作。flock 只对跨进程互斥有效,
    /// 同一进程内多线程打开不同 fd 后 flock 不互斥,需要用 NSLock 补上。
    private static let processLock = NSLock()

    // MARK: - 路径

    static func queueURL(for groupID: String) -> URL? {
        if groupID.hasPrefix("/") {
            return URL(fileURLWithPath: groupID).appendingPathComponent(fileName)
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(fileName)
    }

    private static func lockURL(for groupID: String) -> URL? {
        if groupID.hasPrefix("/") {
            return URL(fileURLWithPath: groupID).appendingPathComponent(lockFileName)
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(lockFileName)
    }

    // MARK: - POSIX flock 协调读写

    /// 打开锁文件并返回文件描述符;失败返回 -1。
    private static func openLockFD(for groupID: String) -> Int32 {
        let lockPath: String
        if let lock = lockURL(for: groupID) {
            lockPath = lock.path
        } else if let url = queueURL(for: groupID) {
            lockPath = url.deletingLastPathComponent()
                .appendingPathComponent(lockFileName).path
        } else {
            return -1
        }
        return open(lockPath, O_CREAT | O_RDWR, 0o600)
    }

    /// 读取队列文件内容。调用方须确保在共享锁(LOCK_SH)保护下执行。
    /// 返回 (entries, isCorrupt)。isCorrupt=true 表示文件存在但无法解码(需保留原文件、不覆盖)。
    /// 文件不存在视为合法空队列,返回 ([], false)。
    private static func readFromURL(_ url: URL) -> ([QuickActionEntry], Bool) {
        // 先检查文件是否存在:不存在即首次使用,合法空队列
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ([], false)
        }
        // 文件存在但读取失败(权限、磁盘错误等):视为损坏
        guard let data = try? Data(contentsOf: url) else {
            return ([], true)
        }
        // 文件存在但 JSON 无效:视为损坏,保留原文件
        if let entries = try? JSONDecoder().decode([QuickActionEntry].self, from: data) {
            return (entries, false)
        }
        return ([], true)
    }

    /// 将条目数组写入队列文件。使用 Data.write(to:options:) 原子写入,
    /// 不预删旧文件。.completeFileProtection 保证文件加密到设备解锁后才可读。
    /// 调用方须确保在排他锁(LOCK_EX)保护下执行。
    private static func writeToURL(_ url: URL, entries: [QuickActionEntry]) -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// 排他锁包裹的读-改-写。processLock 保证进程内互斥,flock 保证跨进程互斥。
    /// 锁顺序:processLock → flock,确保一致。
    /// 返回 (success, corruptionDetected)。corruptionDetected=true 表示发现损坏文件且未修改。
    private static func exclusiveModify(
        for groupID: String,
        _ modify: (inout [QuickActionEntry]) -> Bool
    ) -> (Bool, Bool) {
        processLock.lock()
        defer { processLock.unlock() }
        let fd = openLockFD(for: groupID)
        guard fd >= 0 else { return (false, false) }
        let lockResult = flock(fd, LOCK_EX)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        guard lockResult == 0 else { return (false, false) }
        guard let url = queueURL(for: groupID) else { return (false, false) }
        let (entries, isCorrupt) = readFromURL(url)
        if isCorrupt {
            // 发现损坏文件:不修改、不覆盖、直接返回失败并标记
            return (false, true)
        }
        var mutableEntries = entries
        guard modify(&mutableEntries) else { return (false, false) }
        let writeOK = writeToURL(url, entries: mutableEntries)
        return (writeOK, false)
    }

    /// 共享锁包裹的读取。processLock 保证进程内互斥,flock 保证跨进程互斥。
    /// 返回 (entries, corruptionDetected)。corruptionDetected=true 表示文件损坏、返回空数组。
    private static func sharedRead(for groupID: String) -> ([QuickActionEntry], Bool) {
        processLock.lock()
        defer { processLock.unlock() }
        let fd = openLockFD(for: groupID)
        guard fd >= 0 else { return ([], false) }
        let lockResult = flock(fd, LOCK_SH)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        guard lockResult == 0 else { return ([], false) }
        guard let url = queueURL(for: groupID) else { return ([], false) }
        let (entries, isCorrupt) = readFromURL(url)
        return (entries, isCorrupt)
    }

    // MARK: - 读取(共享锁)

    static func read(from groupID: String) -> [QuickActionEntry] {
        let (entries, _) = sharedRead(for: groupID)
        return entries
    }

    // MARK: - 入队(排他锁)

    /// 追加一条已验证的快速操作。返回是否成功(队列满、验证失败、持久化失败、文件损坏均返回 false)。
    /// 文件损坏时保留原文件不覆盖。
    @discardableResult
    static func append(_ entry: QuickActionEntry, to groupID: String) -> Bool {
        guard validate(entry) else { return false }

        let (succeeded, corruptionDetected) = exclusiveModify(for: groupID) { entries in
            // 按 (kind, dayKey) 去重:同一天同类型只保留最新。
            entries.removeAll { $0.kind == entry.kind && $0.dayKey == entry.dayKey }
            entries.append(entry)
            // 有界:只保留最近 maxEntries 条(按 createdAt 排序)。
            if entries.count > maxEntries {
                entries = Array(entries.sorted(by: { $0.createdAt < $1.createdAt }).suffix(maxEntries))
            }
            return true
        }

        if corruptionDetected {
            // 损坏文件被保留,append 失败
            return false
        }
        if succeeded {
            notifyAppended()
        }
        return succeeded
    }

    // MARK: - 消费(peek + acknowledge)

    /// 非破坏性读取:返回当前队列条目,不清除。用于 peek/snapshot 语义。
    /// 文件损坏时返回空数组、保留原文件。
    static func peek(from groupID: String) -> [QuickActionEntry] {
        let (entries, _) = sharedRead(for: groupID)
        return entries.sorted(by: { $0.createdAt < $1.createdAt })
    }

    /// 按条目 ID 从队列中移除已成功处理的条目。仅在持久化成功后调用。
    /// 返回是否全部成功移除。文件损坏时返回 false、保留原文件。
    @discardableResult
    static func acknowledge(_ ids: Set<UUID>, from groupID: String) -> Bool {
        guard !ids.isEmpty else { return true }
        let (succeeded, corruptionDetected) = exclusiveModify(for: groupID) { entries in
            entries.removeAll { ids.contains($0.id) }
            return true
        }
        return !corruptionDetected && succeeded
    }

    /// Atomically discard all currently pending quick actions.
    ///
    /// This is used after the phone has successfully deleted its five local
    /// models.  It intentionally operates only on the iOS App Group queue;
    /// WatchConnectivity outbox/applicationContext values are handled by the
    /// receiver-side replay cutoff in `QuickLogApplier` because the phone
    /// cannot delete storage on the Watch.  A corrupt queue is preserved and
    /// reported as failure rather than being overwritten.
    @discardableResult
    static func clear(from groupID: String) -> Bool {
        let (succeeded, corruptionDetected) = exclusiveModify(for: groupID) { entries in
            entries.removeAll(keepingCapacity: false)
            return true
        }
        return !corruptionDetected && succeeded
    }

    // MARK: - 待处理状态

    /// 当前队列中属于今天(dayKey)的条目数,供小组件显示。
    /// 文件损坏时返回 0。
    static func pendingTodayCount(for groupID: String, todayKey: Int) -> Int {
        let (entries, _) = sharedRead(for: groupID)
        return entries.filter { $0.dayKey == todayKey }.count
    }

    // MARK: - 日期工具

    /// 当天的 yyyymmdd 整数键(公历,当前时区)。与 DayKey.today 等价,但不依赖 Sources/ 模块。
    static func todayKey() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 1970) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    // MARK: - 校验

    static func validate(_ entry: QuickActionEntry) -> Bool {
        let year = entry.dayKey / 10_000
        let month = (entry.dayKey / 100) % 100
        let day = entry.dayKey % 100
        guard (2000...2100).contains(year) else { return false }
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        guard comps.isValidDate(in: Calendar(identifier: .gregorian)) else { return false }
        switch entry.kind {
        case "period":
            guard let flow = entry.flowRaw, (0...3).contains(flow) else { return false }
            guard entry.moodRaw == nil else { return false }
            return true
        case "mood":
            guard let mood = entry.moodRaw, (1...5).contains(mood) else { return false }
            guard entry.flowRaw == nil else { return false }
            return true
        default:
            return false
        }
    }

    // MARK: - Darwin 通知

    /// 发送 Darwin 通知,告知主 app 有新条目入队。
    private static func notifyAppended() {
        guard let center = CFNotificationCenterGetDarwinNotifyCenter() else { return }
        let name = appendedNotification as CFString
        CFNotificationCenterPostNotification(center, CFNotificationName(name), nil, nil, true)
    }
}
