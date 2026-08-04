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

    private static let store = HKHealthStore()

    /// 用户是否开启了 Apple 健康同步(本机开关)。
    private static let syncKey = "health.syncEnabled"
    static var syncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncKey) }
    }

    /// 设备支持 HealthKit 且 app 已获得 HealthKit 能力时为 true。
    /// 没配 capability 时这里是 false,全部调用会安全地空转,不会崩。
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 当前经期数据的写入授权状态(用户在系统设置里撤销后这里会变)。
    static var sharingStatus: HKAuthorizationStatus {
        guard let type = menstrualType else { return .notDetermined }
        return store.authorizationStatus(for: type)
    }

    private static var menstrualType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .menstrualFlow)
    }

    /// 请求读写经期数据的授权。未配置 capability 时会失败,调用方需容错。
    static func requestAuthorization() async -> Bool {
        guard isAvailable, let type = menstrualType else { return false }
        do {
            try await store.requestAuthorization(toShare: [type], read: [type])
            return true
        } catch {
            return false
        }
    }

    /// 把一天的经期流量写进 Apple Health(幂等:先删本 app 当天已写的旧样本再写,避免重复累积)。
    /// - Parameter isCycleStart:该天是否为某个连续经期段的**第一天**。
    ///   Apple Health 用 `HKMetadataKeyMenstrualCycleStart` 识别周期起点;
    ///   全部写 false 会导致健康侧无法识别任何周期,其他 App 的预测全错。
    static func writePeriodDay(_ day: PeriodDay, isCycleStart: Bool = false) async {
        guard isAvailable, let type = menstrualType else { return }
        // 用户在系统设置里撤销写入授权后,写入会静默失败;这里显式跳过,
        // 避免每次经期标记都白跑一次 HKHealthStore.save。
        guard sharingStatus == .sharingAuthorized else { return }
        // 用 HKCategoryValueMenstrualFlow(iOS 13+);iOS 18 才改名 VaginalBleeding,
        // 我们的部署目标是 iOS 17,必须用旧名。
        let value: HKCategoryValueMenstrualFlow
        switch day.flow {
        case .spotting: value = .unspecified
        case .light:    value = .light
        case .medium:   value = .medium
        case .heavy:    value = .heavy
        }
        let start = Cal.startOfDay(day.date)
        let end = Cal.current.date(byAdding: .day, value: 1, to: start) ?? start
        // 幂等:先删除本 app 当天已写入的样本,再保存新样本(只删本 app 的,不动别处记录)。
        await deletePeriodDay(day.date)
        let sample = HKCategorySample(type: type, value: value.rawValue,
                                      start: start, end: end,
                                      metadata: [HKMetadataKeyMenstrualCycleStart: isCycleStart])
        try? await store.save(sample)
    }

    /// 从 Apple Health 删除某一天由本 app 写入的经期样本(用户在 Maren 里清除时调用)。
    static func deletePeriodDay(_ date: Date) async {
        guard isAvailable, let type = menstrualType else { return }
        let start = Cal.startOfDay(date)
        let end = Cal.current.date(byAdding: .day, value: 1, to: start) ?? start
        // 只删本 app 写入的样本(source = 本 app),不动用户在别处记的。
        let inDay = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [inDay, mine])
        _ = try? await store.deleteObjects(of: type, predicate: predicate)
    }

    /// 一次性把 Maren 已有的经期全部写回 Apple Health(连接时的「导出」)。
    /// 按连续段计算 `isCycleStart`:每段第一天写 true,其余 false —— 让健康侧能正确识别周期。
    /// 幂等:writePeriodDay 内部先删后写,重复连接不会累积重复样本。
    static func exportAll(_ periodDays: [PeriodDay]) async {
        let sorted = periodDays.sorted { $0.dayKey < $1.dayKey }
        var previous: PeriodDay? = nil
        for day in sorted {
            let isCycleStart: Bool
            if let prev = previous {
                // 与前一天连续(相差 1 天)则不是新周期;出现断档(>1 天)视为新一段。
                isCycleStart = Cal.daysBetween(prev.date, day.date) > 1
            } else {
                isCycleStart = true
            }
            await writePeriodDay(day, isCycleStart: isCycleStart)
            previous = day
        }
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
                    let flow: FlowLevel
                    switch HKCategoryValueMenstrualFlow(rawValue: s.value) {
                    case .light:  flow = .light
                    case .medium: flow = .medium
                    case .heavy:  flow = .heavy
                    default:      flow = .spotting
                    }
                    return (Cal.startOfDay(s.startDate), flow)
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
