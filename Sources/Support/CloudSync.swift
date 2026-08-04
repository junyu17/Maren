import Foundation
import SwiftData
import CloudKit

/// 层级 4 · CloudKit 私有库同步(V2,已接通)。
///
/// **当前状态:代码与 entitlement 已就位,默认关闭,由用户在「设置」显式开启。**
///
/// 已就位:
///   - 5 个模型的 `@Attribute(.unique)` 全部移除(CloudKit 不支持),去重改由写入路径
///     「先查后写」手动完成(`CalendarView.upsertPeriod` / `DailyLogView.save` /
///     `DailyLogView.toggleMed` / `QuickLogApplier`)。
///   - entitlements 已加 `iCloud.cd.cc.vela` 容器 + CloudKit 服务(见 `project.yml`)。
///   - 设置页有「iCloud 同步」开关,写入 `sync.cloudKitEnabled`。
///
/// 仍需 Billy(涉及 Apple 账号 / 真机):
///   1. Vela target -> Signing & Capabilities -> 填 Team(真机签名);
///   2. 首次真机运行开启同步后,CloudKit 会自动把 schema 部署到开发环境;
///      上线前在 CloudKit Dashboard「Deploy to Production」;
///   3. (可选)勾 Background Modes -> Remote notifications,让同步由推送即时触发;
///      不勾也能同步,只是时机改为 app 启动/前台时。
///
/// ⚠️ 已知限制:CloudKit 镜像会直接插入远端记录,绕过 app 写入逻辑。若两台设备在
/// 同步传播前各自写入同一天(dayKey),同步后可能出现两条同 dayKey 记录。单人多设备
/// 串行使用基本不会触发;真发生时由写入路径的「先查后写」在下次本地写入时合并。
///
/// ⚠️ 切换开关需重启 app:`ModelContainer` 在启动时按当时的配置创建一次,改开关后
/// 下次打开 Maren 才生效(设置页有提示)。
///
/// 隐私铁律:CloudKit **私有库** = 数据存在**用户自己的 iCloud**,开发者无法访问,
/// 与「我们的服务器永不接触健康数据」不冲突。默认关闭,由用户显式开启。
enum CloudSync {

    static let containerIdentifier = "iCloud.cd.cc.vela"
    /// 用户是否开启了同步(默认关闭 -- 本地优先)。
    static let storageKey = "sync.cloudKitEnabled"

    static var isEnabledByUser: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    /// 当前构建是否具备 CloudKit 能力(容器 entitlement 配好 **且** 用户已登录 iCloud)。
    /// 没配 / 未登录时返回 false,app 继续以纯本地模式运行,不受影响。
    ///
    /// ⚠️ 不能用 `FileManager.default.ubiquityIdentityToken`:它只对「iCloud Documents /
    /// ubiquity container」有保证,CloudKit-only entitlement 下可能恒为 nil,
    /// 导致「明明配了 CloudKit 却永远显示不可用」。改用 `CKContainer.accountStatus()`。
    /// 注意 `accountStatus` 是异步的,这里返回的是**上次校验的缓存**;启动时由
    /// `refreshConfiguredStatus()` 刷新一次。
    private(set) static var isConfigured: Bool = {
        // 乐观默认:启动瞬间尚未校验完时按「已配置」处理(用户开启就尝试 CloudKit,
        // 未登录的镜像会自然挂起但不崩,设置页在校验完成后给出准确状态)。
        true
    }()

    /// 异步校验 iCloud 账户状态并缓存结果。启动时调用一次;
    /// 用户登录/退出 iCloud 后重新进入设置页也应刷新。
    @MainActor
    static func refreshConfiguredStatus() async {
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            isConfigured = (status == .available)
        } catch {
            isConfigured = false
        }
    }

    /// 生成 ModelConfiguration。启用同步需要同时满足:用户开启 + 构建已配置。
    /// 两者任一不满足都回落到纯本地,行为与未开同步完全一致。
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
