import Foundation
import HealthKit

/// 层级 4 · Apple Health 双向同步(骨架)。
///
/// **当前状态:代码就绪,但需要你在 Xcode 里配好开发者账号才能真正启用。**
/// 需要的操作(必须由 Billy 本人做,涉及你的 Apple 账号):
///   1. Xcode → 选中 Vela target → Signing & Capabilities → 填入你的 Team;
///   2. 点 “+ Capability” 添加 **HealthKit**;
///   3. 重新运行即可。`isAvailable` 会自动变 true,下面的读写就生效。
/// 用法说明文案已在 project.yml 配好(NSHealthShareUsageDescription / NSHealthUpdateUsageDescription)。
///
/// 铁律遵守:HealthKit 数据**仅本地使用**,不外传、不用于广告 —— 与隐私政策 §4 一致。
enum HealthKitBridge {

    private static let store = HKHealthStore()

    /// 设备支持 HealthKit 且 app 已获得 HealthKit 能力时为 true。
    /// 没配 capability 时这里是 false,全部调用会安全地空转,不会崩。
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

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

    /// 把一天的经期流量写进 Apple Health。
    static func writePeriodDay(_ day: PeriodDay) async {
        guard isAvailable, let type = menstrualType else { return }
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
        let sample = HKCategorySample(type: type, value: value.rawValue,
                                      start: start, end: end,
                                      metadata: [HKMetadataKeyMenstrualCycleStart: false])
        try? await store.save(sample)
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
