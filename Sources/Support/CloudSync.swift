import Foundation
import SwiftData

/// 层级 4 · CloudKit 私有库同步(骨架)。
///
/// **当前状态:默认关闭,且启用前有一个必须先做的架构改动 —— 见下。**
///
/// 需要你(Billy)在 Xcode 里做的(涉及你的 Apple 账号,我做不了):
///   1. Vela target → Signing & Capabilities → 填 Team;
///   2. “+ Capability” 添加 **iCloud**,勾选 **CloudKit**,新建容器 `iCloud.cd.cc.vela`;
///   3. 同时勾选 **Background Modes → Remote notifications**(同步推送需要)。
///
/// ⚠️ **架构前提(必须先改代码,否则一开同步就崩)**:
///   SwiftData + CloudKit **不支持 `@Attribute(.unique)`**。
///   我们四个模型(PeriodDay / DailyLog / CustomSymptom / Medication / MedicationIntake)
///   现在都靠唯一约束做「一天一条」的去重。开同步前要把唯一约束去掉,
///   改成写入前先 fetch 同 dayKey 再决定 insert/update(即手动去重)。
///   `QuickLogApplier` 里已经是这种「先查后写」的写法,可以作为改造样板。
///
/// 隐私铁律:CloudKit **私有库**意味着数据存在**用户自己的 iCloud**,
/// 开发者无法访问 —— 与「我们的服务器永不接触健康数据」不冲突。默认关闭,由用户显式开启。
enum CloudSync {

    static let containerIdentifier = "iCloud.cd.cc.vela"
    /// 用户是否开启了同步(默认关闭 —— 本地优先)。
    static let storageKey = "sync.cloudKitEnabled"

    static var isEnabledByUser: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    /// 当前构建是否具备 CloudKit 能力(配了 Team + iCloud capability 后为 true)。
    /// 没配时返回 false,app 继续以纯本地模式运行,不受影响。
    static var isConfigured: Bool {
        // 有 iCloud 容器 entitlement 时,FileManager 能拿到 ubiquity token。
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// 生成 ModelConfiguration。启用同步需要同时满足:用户开启 + 构建已配置。
    /// 目前两者任一不满足都回落到纯本地,行为与现在完全一致。
    static func makeConfiguration(schema: Schema) -> ModelConfiguration {
        guard isEnabledByUser, isConfigured else {
            return ModelConfiguration(schema: schema,
                                      isStoredInMemoryOnly: false,
                                      cloudKitDatabase: .none)
        }
        return ModelConfiguration(schema: schema,
                                  isStoredInMemoryOnly: false,
                                  cloudKitDatabase: .private(containerIdentifier))
    }
}
