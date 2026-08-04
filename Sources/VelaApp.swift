import SwiftUI
import SwiftData

@main
struct VelaApp: App {
    /// 本地优先:仅存本机(SwiftData 本地库)。CloudKit 同步作为 V2 可选开关,默认不开。
    /// 我们的服务器永不接触健康数据 —— 这里没有任何网络层。
    let container: ModelContainer
    /// 本地库打不开时降级为「仅内存」模式:宁可这一次进不了历史数据,
    /// 也不能让用户永远打不开 app(健康数据丢不起,但崩溃更留不住人)。
    let storeFailed: Bool

    init() {
        let schema = Schema([PeriodDay.self, DailyLog.self,
                             CustomSymptom.self, Medication.self, MedicationIntake.self])
        // 默认纯本地。只有「用户显式开启同步」且「构建已配好 iCloud capability」时才走 CloudKit
        // 私有库(数据仍在用户自己的 iCloud,我们的服务器不接触)。详见 CloudSync 的说明。
        let config = CloudSync.makeConfiguration(schema: schema)
        if let c = try? ModelContainer(for: schema, configurations: config) {
            container = c
            storeFailed = false
        } else {
            // 兜底:内存容器。用户仍可使用 app,并会看到明确提示。
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
            storeFailed = true
        }
        #if DEBUG
        DemoSeed.runIfRequested(container)
        DemoSeed.seedDuplicates(container)
        #endif
        // CloudKit 多端同步可能在同 dayKey 产生重复记录;启动折叠一次(无重复则 no-op)。
        DedupSweep.run(in: container)
        // 注入给手表连接层,让它收到记录后能直接落库(不依赖任何视图存活)。
        // 同步赋值:VelaApp.init 在主线程执行,此时 WCSession 尚未激活,
        // 手表消息最早也在 RootView.onAppear 的 activate() 之后才可能到达,
        // 所以这里不会出现「消息到了但 container 还是 nil」的竞态。
        PhoneConnectivity.container = container
        // 异步校验 CloudKit 账户状态(登录/退出 iCloud 会影响「iCloud 同步」开关的可用性)。
        Task { @MainActor in await CloudSync.refreshConfiguredStatus() }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailed: storeFailed)
        }
        .modelContainer(container)
    }
}
