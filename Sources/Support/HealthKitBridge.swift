import Foundation
import HealthKit

/// 层级 4 · Apple Health 双向同步(F 已启用)。
///
/// 需要构建配置(已在 project.yml 配好):HealthKit capability(entitlement)+
/// `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`。
/// 真机需你的 Apple 账号在该 App ID 上勾 HealthKit;模拟器可直接跑。
///
/// 双向:连接时把「健康」里的经期读进 Maren(导入),并把 Maren 已有经期写回「健康」(导出);
/// 之后每次标记/清除经期都会同步到「健康」。
///
/// 铁律遵守:HealthKit 数据**仅本地使用**,不外传、不用于广告 —— 与隐私政策 §4 一致。
enum HealthKitBridge {

    /// HealthKit does not provide transactional replacement for a day's
    /// samples.  Serialize every Maren-owned write/delete sequence so two
    /// rapid calendar edits cannot interleave delete/write operations and
    /// leave cycle-start metadata from the wrong revision.
    private actor WriteCoordinator {
        private var tail: Task<Void, Never>?

        func enqueue<T: Sendable>(
            _ operation: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            let previous = tail
            let current = Task<T, Error> {
                await previous?.value
                return try await operation()
            }
            tail = Task {
                _ = try? await current.value
            }
            return try await current.value
        }
    }

    private static let store = HKHealthStore()
    private static let ownSourceIdentifier = HKSource.default().bundleIdentifier
    private static let writeCoordinator = WriteCoordinator()

    private struct DailyLogSnapshot: Sendable {
        let date: Date
        let healthImportedFields: Set<String>
        let weight: Double?
        let basalBodyTemperatureCelsius: Double?
        let spotting: Bool?

        init(_ log: DailyLog) {
            date = log.date
            healthImportedFields = Set(log.healthImportedFields)
            weight = log.weight
            basalBodyTemperatureCelsius = log.basalBodyTemperatureCelsius
            spotting = log.spotting
        }
    }

    /// A value-only period write captured before entering the HealthKit
    /// coordinator.  Keeping SwiftData models out of the queued operation
    /// prevents a later view refresh from changing the revision being
    /// written.
    struct PeriodWriteSnapshot: Equatable, Sendable {
        let date: Date
        let flowRaw: Int
        let isCycleStart: Bool

        init(date: Date, flowRaw: Int, isCycleStart: Bool) {
            self.date = date
            self.flowRaw = flowRaw
            self.isCycleStart = isCycleStart
        }
    }

    enum PeriodRevisionOperation: Equatable, Sendable {
        case delete(Date)
        case write(PeriodWriteSnapshot)
    }

    struct PeriodRevisionPlan: Equatable, Sendable {
        let deleteDate: Date?
        let writes: [PeriodWriteSnapshot]

        var operations: [PeriodRevisionOperation] {
            var result: [PeriodRevisionOperation] = []
            if let deleteDate {
                result.append(.delete(deleteDate))
            }
            result.append(contentsOf: writes.map(PeriodRevisionOperation.write))
            return result
        }
    }

    static func makePeriodRevisionPlan(
        deleteDate: Date?,
        writes: [PeriodWriteSnapshot]
    ) -> PeriodRevisionPlan {
        PeriodRevisionPlan(deleteDate: deleteDate, writes: writes)
    }

    private static func dayRange(for date: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    private static func ensureWriteAuthorized(_ type: SyncType) throws {
        guard sharingStatus(for: type) == .sharingAuthorized else { throw BridgeError.writeNotAuthorized }
    }

    enum BridgeError: LocalizedError {
        case healthUnavailable
        case noTypesSelected
        case unsupportedType
        case writeNotAuthorized
        case invalidValue

        var errorDescription: String? {
            switch self {
            case .healthUnavailable: return String(localized: "设备不支持 HealthKit")
            case .noTypesSelected: return String(localized: "未选择同步类型")
            case .unsupportedType: return String(localized: "不支持的同步类型")
            case .writeNotAuthorized: return String(localized: "未获得 HealthKit 写入授权")
            case .invalidValue: return String(localized: "要同步的健康数值无效,本机记录未修改")
            }
        }
    }

    /// 用户是否开启了 Apple 健康同步(本机开关)。
    private static let syncKey = "health.syncEnabled"
    static var syncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncKey) }
    }

    enum SyncType: String, CaseIterable, Identifiable, Sendable {
        case menstrualFlow
        case bodyMass
        case sleepAnalysis
        case basalBodyTemperature
        case spotting
        case stepCount
        case appleExerciseTime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .menstrualFlow:       return String(localized: "经期流量")
            case .bodyMass:            return String(localized: "体重")
            case .sleepAnalysis:       return String(localized: "睡眠分析")
            case .basalBodyTemperature: return String(localized: "基础体温")
            case .spotting:            return String(localized: "点滴出血")
            case .stepCount:           return String(localized: "步数")
            case .appleExerciseTime:   return String(localized: "锻炼时间")
            }
        }

        static func localizedTitleList(for types: [Self]) -> String {
            titleList(types.map(\.title))
        }

        static func titleList(_ titles: [String], locale: Locale = .current) -> String {
            let separator = locale.language.languageCode?.identifier == "zh" ? "、" : ", "
            return titles.joined(separator: separator)
        }

        var objectType: HKObjectType? {
            switch self {
            case .menstrualFlow:       return HKObjectType.categoryType(forIdentifier: .menstrualFlow)
            case .bodyMass:            return HKObjectType.quantityType(forIdentifier: .bodyMass)
            case .sleepAnalysis:       return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
            case .basalBodyTemperature: return HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)
            case .spotting:            return HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding)
            case .stepCount:           return HKObjectType.quantityType(forIdentifier: .stepCount)
            case .appleExerciseTime:   return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
            }
        }

        var isWritable: Bool {
            switch self {
            case .sleepAnalysis, .stepCount, .appleExerciseTime: return false
            default:               return true
            }
        }

        var isSelected: Bool {
            HealthKitBridge.selectedTypes.contains(self)
        }

        var sampleType: HKSampleType? {
            objectType as? HKSampleType
        }
    }

    struct PeriodImport {
        let dayKey: Int
        let flow: FlowLevel
    }

    struct DailyImport {
        let dayKey: Int
        var sleepHours: Double?
        var weight: Double?
        var basalBodyTemperatureCelsius: Double?
        var spotting: Bool?
        var steps: Int?
        var exerciseMinutes: Int?
    }

    struct ImportPayload {
        let periods: [PeriodImport]
        let daily: [DailyImport]
    }

    /// Outcome of the destructive HealthKit cleanup.  A missing write grant
    /// is a meaningful partial result, not an empty success, because HealthKit
    /// intentionally does not reveal the user's read/write decisions through
    /// the authorization prompt.
    struct DeleteAllResult: Equatable, Sendable {
        struct Failure: Equatable, Sendable {
            let type: SyncType
            let message: String
        }

        let deleted: [SyncType]
        let skipped: [SyncType]
        let failed: [Failure]

        var isComplete: Bool { skipped.isEmpty && failed.isEmpty }

        /// Localized, user-facing summary used by Settings.  It intentionally
        /// does not expose raw HealthKit error text or any other data.
        var userFacingIssueDescription: String {
            var lines: [String] = []
            if !skipped.isEmpty {
                let names = SyncType.localizedTitleList(for: skipped)
                lines.append(String(localized: "以下类型未能清理,因为 Maren 没有 HealthKit 写入权限: \(names)。请在「健康」App 中检查权限。"))
            }
            if !failed.isEmpty {
                let names = SyncType.localizedTitleList(for: failed.map(\.type))
                lines.append(String(localized: "以下类型清理失败: \(names)。你可以稍后重试;其他来源的 Health 数据不会被删除。"))
            }
            return lines.joined(separator: "\n")
        }
    }

    private static let selectionKey = "health.selectedTypes"
    static var selectedTypes: Set<SyncType> {
        get {
            let saved = UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: Bool]
            let ids = HealthKitPlanners.selectionMigration(
                saved: saved,
                oldSyncEnabled: syncEnabled,
                menstrualIdentifier: SyncType.menstrualFlow.rawValue,
                supported: Set(SyncType.allCases.map(\.rawValue))
            )
            return Set(ids.compactMap(SyncType.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(
                Dictionary(uniqueKeysWithValues: SyncType.allCases.map { ($0.rawValue, newValue.contains($0)) }),
                forKey: selectionKey
            )
        }
    }

    /// 设备支持 HealthKit 且 app 已获得 HealthKit 能力时为 true。
    /// 没配 capability 时这里是 false,全部调用会安全地空转,不会崩。
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 当前经期数据的写入授权状态(用户在系统设置里撤销后这里会变)。
    static var sharingStatus: HKAuthorizationStatus {
        guard let type = menstrualType else { return .notDetermined }
        return store.authorizationStatus(for: type)
    }

    /// 返回指定同步类型的写入授权状态。
    static func sharingStatus(for type: SyncType) -> HKAuthorizationStatus {
        guard let sampleType = type.sampleType else { return .notDetermined }
        return store.authorizationStatus(for: sampleType)
    }

    private static var menstrualType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .menstrualFlow)
    }

    /// 为选定的同步类型请求 HealthKit 授权。
    static func requestAuthorization(for selected: Set<SyncType>) async throws {
        guard isAvailable else { throw BridgeError.healthUnavailable }
        guard !selected.isEmpty else { throw BridgeError.noTypesSelected }

        let objectTypes = selected.compactMap { $0.objectType }
        guard objectTypes.count == selected.count else { throw BridgeError.unsupportedType }

        let read = Set(objectTypes)
        let share = Set(selected.filter { $0.isWritable }.compactMap { $0.objectType as? HKSampleType })

        try await store.requestAuthorization(toShare: share, read: read)
    }

    /// 请求读写经期数据的授权。未配置 capability 时会失败,调用方需容错。
    static func requestAuthorization() async -> Bool {
        do {
            try await requestAuthorization(for: selectedTypes)
            return true
        } catch {
            return false
        }
    }

    /// 删除本 app 在指定时间范围内写入的特定类型样本。
    private static func deleteOwnSamples(of sampleType: HKSampleType, start: Date, end: Date) async throws {
        let inDay = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [inDay, mine])
        try await store.deleteObjects(of: sampleType, predicate: predicate)
    }

    /// 写入/同步单日经期到 HealthKit(会抛出错误供调用方处理)。
    /// - Parameter day:要写入的经期记录(必须非 importedFromHealth)。
    /// - Parameter isCycleStart:该天是否为某个连续经期段的**第一天**。
    static func syncPeriodDay(_ day: PeriodDay, isCycleStart: Bool = false) async throws {
        let date = day.date
        let flowRaw = day.flowRaw
        let importedFromHealth = day.importedFromHealth
        guard !importedFromHealth else { return }
        try await syncPeriodRevision(
            deleteDate: nil,
            writes: [PeriodWriteSnapshot(
                date: date,
                flowRaw: flowRaw,
                isCycleStart: isCycleStart
            )]
        )
    }

    /// Applies one HealthKit period revision as one coordinator transaction.
    /// The optional delete is performed first, followed by every replacement
    /// write.  Failures are remembered but later neighbors are still
    /// attempted, preserving the previous best-effort resync behavior without
    /// allowing another revision to interleave between delete and writes.
    static func syncPeriodRevision(
        deleteDate: Date?,
        writes: [PeriodWriteSnapshot]
    ) async throws {
        let plan = makePeriodRevisionPlan(deleteDate: deleteDate, writes: writes)
        guard !plan.operations.isEmpty else { return }
        try await runPeriodRevisionPlan(plan) { operation in
            switch operation {
            case .delete(let date):
                try await deletePeriodDayUncoordinated(date)
            case .write(let snapshot):
                try await syncPeriodDayUncoordinated(
                    date: snapshot.date,
                    flowRaw: snapshot.flowRaw,
                    isCycleStart: snapshot.isCycleStart
                )
            }
        }
    }

    /// Test-only seam for exercising the exact coordinator batch without
    /// HealthKit authorization or a real HKHealthStore.  Production callers
    /// use `syncPeriodRevision`, which supplies the uncoordinated operations.
    static func _runPeriodRevisionPlanForTesting(
        _ plan: PeriodRevisionPlan,
        operation: @escaping @Sendable (PeriodRevisionOperation) async throws -> Void
    ) async throws {
        guard !plan.operations.isEmpty else { return }
        try await runPeriodRevisionPlan(plan, operation: operation)
    }

    private static func runPeriodRevisionPlan(
        _ plan: PeriodRevisionPlan,
        operation: @escaping @Sendable (PeriodRevisionOperation) async throws -> Void
    ) async throws {
        try await writeCoordinator.enqueue {
            var firstError: Error?
            for item in plan.operations {
                do {
                    try await operation(item)
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if let firstError { throw firstError }
        }
    }

    private static func syncPeriodDayUncoordinated(
        date: Date,
        flowRaw: Int,
        isCycleStart: Bool
    ) async throws {
        guard isAvailable else { throw BridgeError.healthUnavailable }
        guard selectedTypes.contains(.menstrualFlow) else { throw BridgeError.noTypesSelected }
        guard let type = menstrualType else { throw BridgeError.unsupportedType }
        guard sharingStatus(for: .menstrualFlow) == .sharingAuthorized else { throw BridgeError.writeNotAuthorized }

        let value: HKCategoryValueMenstrualFlow
        switch FlowLevel(rawValue: flowRaw) ?? .medium {
        case .spotting: value = .unspecified
        case .light:    value = .light
        case .medium:   value = .medium
        case .heavy:    value = .heavy
        }

        let start = Cal.startOfDay(date)
        let end = Cal.current.date(byAdding: .day, value: 1, to: start) ?? start

        try await deleteOwnSamples(of: type, start: start, end: end)

        let sample = HKCategorySample(type: type, value: value.rawValue,
                                      start: start, end: end,
                                      metadata: [HKMetadataKeyMenstrualCycleStart: isCycleStart])
        try await store.save(sample)
    }

    /// 同步一天的 DailyLog 到 Apple Health(体重、基础体温、点滴出血)。
    /// - Parameter log: 要同步的每日记录(healthImportedFields 内的字段将被跳过,不做 auth/delete/write)。
    static func syncDailyLog(_ log: DailyLog) async throws {
        let snapshot = DailyLogSnapshot(log)
        try await writeCoordinator.enqueue {
            try await syncDailyLogUncoordinated(snapshot)
        }
    }

    private static func syncDailyLogUncoordinated(_ log: DailyLogSnapshot) async throws {
        guard isAvailable else { throw BridgeError.healthUnavailable }

        let calendar = Cal.current

        let syncTypes: [SyncType] = [.bodyMass, .basalBodyTemperature, .spotting]
        var firstError: Error?

        for type in syncTypes {
            do {
                // 若该字段已标记为从 HealthKit 导入,则完全跳过(不做 auth/delete/write)
                let fieldKey: String
                switch type {
                case .bodyMass:        fieldKey = HealthKitPlanners.FieldKey.weight.rawValue
                case .basalBodyTemperature: fieldKey = HealthKitPlanners.FieldKey.basalBodyTemperature.rawValue
                case .spotting:        fieldKey = HealthKitPlanners.FieldKey.spotting.rawValue
                default: continue
                }

                if log.healthImportedFields.contains(fieldKey) { continue }

                // 仅处理已选中的类型
                guard selectedTypes.contains(type) else { continue }

                try ensureWriteAuthorized(type)

                let (dayStart, dayEnd) = dayRange(for: log.date, calendar: calendar)

                guard let sampleType = type.sampleType else { continue }

                // 根据类型保存对应的手动值
                switch type {
                case .bodyMass:
                    guard let quantityType = sampleType as? HKQuantityType else { continue }
                    guard let weightKg = log.weight else {
                        try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
                        continue
                    }
                    guard HealthKitPlanners.isValidWeight(weightKg) else {
                        throw BridgeError.invalidValue
                    }
                    // Validate before deletion so malformed imported/backup
                    // data cannot erase a previously valid Health sample.
                    try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
                    let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weightKg)
                    let start = dayStart
                    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                    let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: start, end: end, metadata: nil)
                    try await store.save(sample)

                case .basalBodyTemperature:
                    guard let quantityType = sampleType as? HKQuantityType else { continue }
                    guard let tempC = log.basalBodyTemperatureCelsius else {
                        try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
                        continue
                    }
                    guard HealthKitPlanners.isValidBasalBodyTemperature(tempC) else {
                        throw BridgeError.invalidValue
                    }
                    try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
                    let quantity = HKQuantity(unit: HKUnit.degreeCelsius(), doubleValue: tempC)
                    let start = dayStart
                    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                    let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: start, end: end, metadata: nil)
                    try await store.save(sample)

                case .spotting:
                    guard let categoryType = sampleType as? HKCategoryType else { continue }
                    if log.spotting == true {
                        try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
                        let value = HKCategoryValue.notApplicable.rawValue
                        let start = dayStart
                        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                        let sample = HKCategorySample(type: categoryType, value: value, start: start, end: end, metadata: nil)
                        try await store.save(sample)
                    } else {
                        // nil/false means the user cleared the field.  There
                        // is no replacement sample, so deletion is the desired
                        // durable HealthKit state.
                        try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
                    }
                default: continue
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError { throw firstError }
    }

    /// 删除本 app 写入的某一天所有 daily 样本。
    static func deleteDailySamples(_ date: Date) async throws {
        try await writeCoordinator.enqueue {
            try await deleteDailySamplesUncoordinated(date)
        }
    }

    private static func deleteDailySamplesUncoordinated(_ date: Date) async throws {
        guard isAvailable else { throw BridgeError.healthUnavailable }
        let calendar = Cal.current
        let (dayStart, dayEnd) = dayRange(for: date, calendar: calendar)
        let writableTypes: [SyncType] = [.bodyMass, .basalBodyTemperature, .spotting]
        var firstError: Error?

        for type in writableTypes {
            do {
                // 只在当前类型已获得写入授权时删除,不要求该类型当前处于选择状态。
                guard let sampleType = type.sampleType else { continue }
                guard sharingStatus(for: type) == .sharingAuthorized else { continue }
                try await deleteOwnSamples(of: sampleType, start: dayStart, end: dayEnd)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError { throw firstError }
    }

    /// 删除本 app 写入的所有 HealthKit 样本,不受当前类型选择限制。
    static func deleteAllMarenSamples() async throws -> DeleteAllResult {
        try await writeCoordinator.enqueue {
            try await deleteAllMarenSamplesUncoordinated()
        }
    }

    private static func deleteAllMarenSamplesUncoordinated() async throws -> DeleteAllResult {
        guard isAvailable else { throw BridgeError.healthUnavailable }
        // An explicit destructive request must never be followed by an
        // automatic import that resurrects the just-deleted local records.
        syncEnabled = false

        let types = SyncType.allCases.filter(\.isWritable)
        let predicate = HKQuery.predicateForObjects(from: HKSource.default())
        var deleted: [SyncType] = []
        var skipped: [SyncType] = []
        var failed: [DeleteAllResult.Failure] = []

        for type in types {
            guard let sampleType = type.sampleType else {
                failed.append(.init(type: type,
                                    message: String(localized: "不支持的 HealthKit 类型")))
                continue
            }
            guard sharingStatus(for: type) == .sharingAuthorized else {
                skipped.append(type)
                continue
            }
            do {
                try await store.deleteObjects(of: sampleType, predicate: predicate)
                deleted.append(type)
            } catch {
                failed.append(.init(type: type, message: error.localizedDescription))
            }
        }

        return DeleteAllResult(deleted: deleted, skipped: skipped, failed: failed)
    }

    /// 删除本 app 写入的某一天经期样本(抛出版本)。
    static func deletePeriodDayThrowing(_ date: Date) async throws {
        try await syncPeriodRevision(deleteDate: date, writes: [])
    }

    private static func deletePeriodDayUncoordinated(_ date: Date) async throws {
        guard isAvailable else { throw BridgeError.healthUnavailable }
        guard selectedTypes.contains(.menstrualFlow) else { throw BridgeError.noTypesSelected }
        guard let type = menstrualType else { throw BridgeError.unsupportedType }
        guard sharingStatus(for: .menstrualFlow) == .sharingAuthorized else { throw BridgeError.writeNotAuthorized }

        let start = Cal.startOfDay(date)
        let end = Cal.current.date(byAdding: .day, value: 1, to: start) ?? start
        try await deleteOwnSamples(of: type, start: start, end: end)
    }

    /// 把一天的经期流量写进 Apple Health(幂等:先删本 app 当天已写的旧样本再写,避免重复累积)。
    /// - Parameter isCycleStart:该天是否为某个连续经期段的**第一天**。
    ///   Apple Health 用 `HKMetadataKeyMenstrualCycleStart` 识别周期起点;
    ///   全部写 false 会导致健康侧无法识别任何周期,其他 App 的预测全错。
    static func writePeriodDay(_ day: PeriodDay, isCycleStart: Bool = false) async {
        do {
            try await syncPeriodDay(day, isCycleStart: isCycleStart)
        } catch {
            // 保持原有非抛出签名的静默失败行为
        }
    }

    /// 从 Apple Health 删除某一天由本 app 写入的经期样本(用户在 Maren 里清除时调用)。
    static func deletePeriodDay(_ date: Date) async {
        do {
            try await deletePeriodDayThrowing(date)
        } catch {
            // 保持原有非抛出签名的静默失败行为
        }
    }

    /// 一次性把 Maren 已有的经期全部写回 Apple Health(连接时的「导出」)。
    /// 按连续段计算 `isCycleStart`:每段第一天写 true,其余 false —— 让健康侧能正确识别周期。
    /// 幂等:writePeriodDay 内部先删后写,重复连接不会累积重复样本。
    /// 仅导出本地记录(importedFromHealth == false),避免将 Health 回写的数据再次写回 Health 造成循环。
    static func exportAll(_ periodDays: [PeriodDay]) async {
        let localDays = periodDays.filter { !$0.importedFromHealth }.sorted { $0.dayKey < $1.dayKey }
        let cycleStarts = HealthKitPlanners.cycleStartFlags(
            for: localDays.map(\.dayKey),
            calendar: Cal.gregorian
        )
        let writes = localDays.map { day in
            PeriodWriteSnapshot(
                date: day.date,
                flowRaw: day.flowRaw,
                isCycleStart: cycleStarts[day.dayKey] ?? true
            )
        }
        do {
            try await syncPeriodRevision(deleteDate: nil, writes: writes)
        } catch {
            // Preserve this legacy non-throwing export signature.
        }
    }

    /// 一次性把本地经期和 DailyLog 写回 Apple Health。
    static func exportAll(periodDays: [PeriodDay], logs: [DailyLog]) async throws {
        let localDays = periodDays.filter { !$0.importedFromHealth }.sorted { $0.dayKey < $1.dayKey }
        let cycleStarts = HealthKitPlanners.cycleStartFlags(
            for: localDays.map(\.dayKey),
            calendar: Cal.gregorian
        )
        var firstError: Error?

        let writes = localDays.map { day in
            PeriodWriteSnapshot(
                date: day.date,
                flowRaw: day.flowRaw,
                isCycleStart: cycleStarts[day.dayKey] ?? true
            )
        }
        do {
            try await syncPeriodRevision(deleteDate: nil, writes: writes)
        } catch {
            if firstError == nil { firstError = error }
        }

        for log in logs.sorted(by: { $0.dayKey < $1.dayKey }) {
            do {
                try await syncDailyLog(log)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if let firstError { throw firstError }
    }

    /// 从 Apple Health 读回最近的经期记录(供导入)。
    static func readRecentPeriodDays(days: Int = 180) async -> [(date: Date, flow: FlowLevel)] {
        guard isAvailable, let type = menstrualType else { return [] }
        let start = Cal.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let result: [(Date, FlowLevel)] = (samples as? [HKCategorySample] ?? []).compactMap { s in
                    // Never surface our own writes as import candidates. This
                    // legacy read path is still public within the app and
                    // must obey the same anti-loop rule as fetchRecentImports.
                    guard s.sourceRevision.source.bundleIdentifier != ownSourceIdentifier else {
                        return nil
                    }
                    switch HKCategoryValueMenstrualFlow(rawValue: s.value) {
                    case .some(.unspecified): return (Cal.startOfDay(s.startDate), .spotting)
                    case .some(.light):       return (Cal.startOfDay(s.startDate), .light)
                    case .some(.medium):      return (Cal.startOfDay(s.startDate), .medium)
                    case .some(.heavy):       return (Cal.startOfDay(s.startDate), .heavy)
                    case .some(HKCategoryValueMenstrualFlow.none): return nil
                    case Optional.none:                           return nil
                    @unknown default:         return nil
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func samples(
        of sampleType: HKSampleType,
        start: Date,
        end: Date
    ) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    private static func fetchPeriodImports(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [PeriodImport] {
        guard let menstrualType = menstrualType else { return [] }
        guard selectedTypes.contains(.menstrualFlow) else { return [] }

        let samples = try await samples(of: menstrualType, start: start, end: end)

        var latestPerDay: [Int: (date: Date, flow: FlowLevel)] = [:]

        for sample in samples {
            guard let categorySample = sample as? HKCategorySample else { continue }
            guard categorySample.sourceRevision.source.bundleIdentifier != ownSourceIdentifier else { continue }

            guard let flowValue = HKCategoryValueMenstrualFlow(rawValue: categorySample.value) else { continue }

            let flow: FlowLevel
            switch flowValue {
            case .unspecified: flow = .spotting
            case .light:       flow = .light
            case .medium:      flow = .medium
            case .heavy:       flow = .heavy
            case .none:        continue
            @unknown default:  continue
            }

            let dayKey = HealthKitPlanners.dayKey(for: categorySample.startDate, calendar: calendar)
            let sampleDate = categorySample.startDate

            if let existing = latestPerDay[dayKey] {
                if sampleDate > existing.date {
                    latestPerDay[dayKey] = (sampleDate, flow)
                }
            } else {
                latestPerDay[dayKey] = (sampleDate, flow)
            }
        }

        return latestPerDay
            .map { PeriodImport(dayKey: $0.key, flow: $0.value.flow) }
            .sorted { $0.dayKey < $1.dayKey }
    }

    private static func fetchLatestQuantityValues(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        validator: @escaping (Double) -> Bool
    ) async throws -> [Int: Double] {
        let samples = try await samples(of: type, start: start, end: end)

        var datedValues: [HealthKitPlanners.DatedValue] = []
        for sample in samples {
            guard let quantitySample = sample as? HKQuantitySample else { continue }
            let value = quantitySample.quantity.doubleValue(for: unit)
            let sourceId = quantitySample.sourceRevision.source.bundleIdentifier
            datedValues.append(HealthKitPlanners.DatedValue(
                date: quantitySample.startDate,
                value: value,
                sourceIdentifier: sourceId
            ))
        }

        return HealthKitPlanners.latestValidValuesByDay(
            datedValues,
            calendar: calendar,
            excludingSourceIdentifier: ownSourceIdentifier,
            isValid: validator
        )
    }

    /// Reads a cumulative quantity into calendar-day buckets.  Step count and
    /// exercise time are cumulative HealthKit quantities, so selecting the
    /// latest sample would undercount days with multiple samples.  A single
    /// statistics collection query uses the supplied calendar-day interval,
    /// including 23/25-hour DST days.
    private static func fetchCumulativeQuantityValues(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        normalize: @escaping (Double) -> Int?
    ) async throws -> [Int: Int] {
        guard start < end else { return [:] }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        var intervalComponents = DateComponents()
        intervalComponents.day = 1
        intervalComponents.calendar = calendar
        let anchorDate = calendar.startOfDay(for: start)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[Int: Int], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: anchorDate,
                intervalComponents: intervalComponents
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var result: [Int: Int] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    // `to` is treated as inclusive by some HealthKit releases;
                    // keep the import range explicitly half-open.
                    guard statistics.startDate < end else { return }
                    guard let total = statistics.sumQuantity()?.doubleValue(for: unit),
                          let normalized = normalize(total) else { return }
                    let key = HealthKitPlanners.dayKey(for: statistics.startDate, calendar: calendar)
                    result[key] = normalized
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func fetchStepValues(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [Int: Int] {
        guard selectedTypes.contains(.stepCount),
              let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return [:]
        }
        return try await fetchCumulativeQuantityValues(
            type: type,
            unit: HKUnit.count(),
            start: start,
            end: end,
            calendar: calendar,
            normalize: HealthKitPlanners.normalizedSteps
        )
    }

    private static func fetchExerciseValues(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [Int: Int] {
        guard selectedTypes.contains(.appleExerciseTime),
              let type = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) else {
            return [:]
        }
        return try await fetchCumulativeQuantityValues(
            type: type,
            unit: HKUnit.minute(),
            start: start,
            end: end,
            calendar: calendar,
            normalize: HealthKitPlanners.normalizedExerciseMinutes
        )
    }

    private static func fetchSleepValues(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [Int: Double] {
        guard selectedTypes.contains(.sleepAnalysis) else { return [:] }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }

        let samples = try await samples(of: sleepType, start: start, end: end)

        let validValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        var intervals: [HealthKitPlanners.Interval] = []
        for sample in samples {
            guard let categorySample = sample as? HKCategorySample else { continue }
            guard categorySample.sourceRevision.source.bundleIdentifier != ownSourceIdentifier else { continue }
            guard validValues.contains(categorySample.value) else { continue }

            let interval = HealthKitPlanners.Interval(start: categorySample.startDate, end: categorySample.endDate)
            intervals.append(interval)
        }

        let merged = HealthKitPlanners.unionSleepIntervals(intervals)
        let perDay = HealthKitPlanners.splitSleepIntervalsByDay(merged, calendar: calendar)
        return perDay.filter { HealthKitPlanners.isValidSleepHours($0.value) }
    }

    private static func fetchSpottingDays(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> Set<Int> {
        guard selectedTypes.contains(.spotting) else { return [] }
        guard let spottingType = HKObjectType.categoryType(forIdentifier: .intermenstrualBleeding) else { return [] }

        let samples = try await samples(of: spottingType, start: start, end: end)

        var dayKeys: Set<Int> = []
        for sample in samples {
            guard let categorySample = sample as? HKCategorySample else { continue }
            guard categorySample.sourceRevision.source.bundleIdentifier != ownSourceIdentifier else { continue }
            guard categorySample.value == HKCategoryValue.notApplicable.rawValue else { continue }

            let dayKey = HealthKitPlanners.dayKey(for: categorySample.startDate, calendar: calendar)
            dayKeys.insert(dayKey)
        }
        return dayKeys
    }

    public static func fetchRecentImports(
        days: Int = 730,
        calendar: Calendar = .current
    ) async throws -> ImportPayload {
        guard isAvailable else { throw BridgeError.healthUnavailable }

        let (start, end) = HealthKitPlanners.importDateRange(now: Date(), requestedDays: days, calendar: calendar)

        let periodImports = try await fetchPeriodImports(start: start, end: end, calendar: calendar)
        let sleepValues = try await fetchSleepValues(start: start, end: end, calendar: calendar)
        let spottingDays = try await fetchSpottingDays(start: start, end: end, calendar: calendar)
        let stepValues = try await fetchStepValues(start: start, end: end, calendar: calendar)
        let exerciseValues = try await fetchExerciseValues(start: start, end: end, calendar: calendar)

        let weightValues: [Int: Double]
        if selectedTypes.contains(.bodyMass),
           let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            weightValues = try await fetchLatestQuantityValues(
                type: bodyMassType,
                unit: HKUnit.gramUnit(with: .kilo),
                start: start,
                end: end,
                calendar: calendar,
                validator: HealthKitPlanners.isValidWeight
            )
        } else {
            weightValues = [:]
        }

        let bbtValues: [Int: Double]
        if selectedTypes.contains(.basalBodyTemperature),
           let bbtType = HKObjectType.quantityType(forIdentifier: .basalBodyTemperature) {
            bbtValues = try await fetchLatestQuantityValues(
                type: bbtType,
                unit: HKUnit.degreeCelsius(),
                start: start,
                end: end,
                calendar: calendar,
                validator: HealthKitPlanners.isValidBasalBodyTemperature
            )
        } else {
            bbtValues = [:]
        }

        let allDayKeys = Set(sleepValues.keys)
            .union(weightValues.keys)
            .union(bbtValues.keys)
            .union(spottingDays)
            .union(stepValues.keys)
            .union(exerciseValues.keys)

        let dailyImports: [DailyImport] = allDayKeys.map { key in
            DailyImport(
                dayKey: key,
                sleepHours: sleepValues[key],
                weight: weightValues[key],
                basalBodyTemperatureCelsius: bbtValues[key],
                spotting: spottingDays.contains(key) ? true : nil,
                steps: stepValues[key],
                exerciseMinutes: exerciseValues[key]
            )
        }.sorted { $0.dayKey < $1.dayKey }

        let sortedPeriods = periodImports.sorted { $0.dayKey < $1.dayKey }

        return ImportPayload(periods: sortedPeriods, daily: dailyImports)
    }
}
