import SwiftUI
import SwiftData

@main
struct VelaApp: App {
    /// 本地优先:健康数据只存本机(SwiftData 本地库),绝不进入 iCloud / CloudKit。
    /// 我们的服务器永不接触健康数据 —— 这里没有任何网络层。
    let container: ModelContainer
    /// 本地库打不开时降级为「仅内存」模式:宁可这一次进不了历史数据,
    /// 也不能让用户永远打不开 app(健康数据丢不起,但崩溃更留不住人)。
    let storeFailed: Bool
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue
    @AppStorage(AppTextSizePreference.storageKey) private var textSizeRaw = AppTextSizePreference.standard.rawValue

    init() {
        let schema = Schema([PeriodDay.self, DailyLog.self,
                             CustomSymptom.self, Medication.self, MedicationIntake.self])
        // 纯本地 SwiftData 库:不启用 CloudKit / iCloud,遵从 App Review Guideline 5.1.3(ii)
        //(个人健康信息不得存入 iCloud)。健康数据永远只在这台设备的本地文件里。
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
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
        // 重复记录(异常导入 / 快速重复写入等)启动时折叠一次(无重复则 no-op)。
        DedupSweep.run(in: container)
        // 注入给手表连接层,让它收到记录后能直接落库(不依赖任何视图存活)。
        // 同步赋值:VelaApp.init 在主线程执行,此时 WCSession 尚未激活,
        // 手表消息最早也在 RootView.onAppear 的 activate() 之后才可能到达,
        // 所以这里不会出现「消息到了但 container 还是 nil」的竞态。
        PhoneConnectivity.container = container
        // 排空小组件/App Shortcuts 写入的快速操作队列(幂等,空队列无操作)。
        let ctx = container.mainContext
        Task { @MainActor in WidgetQuickDrain.drainIfNeeded(context: ctx) }
        // 安装 Darwin 通知监听:widget/App Shortcuts 入队成功时,若 Maren 已在前台,
        // 立即排空,不等下一次 scenePhase 变化。
        DarwinNotificationObserver.install(context: ctx)
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailed: storeFailed)
                .modifier(AppearanceModifier(
                    mode: AppAppearanceMode(rawValue: appearanceRaw) ?? .system,
                    textSize: AppTextSizePreference(rawValue: textSizeRaw) ?? .standard
                ))
        }
        .modelContainer(container)
    }
}

// MARK: - Darwin 通知(活跃时即时排空)

/// 跨进程 Darwin 通知监听器。使用静态方法避免 struct 不能做 observer 指针的问题。
/// 回调调度到主线程执行排空(SwiftData context 只能在主线程用)。
private enum DarwinNotificationObserver {
    static func install(context: ModelContext) {
        guard let center = CFNotificationCenterGetDarwinNotifyCenter() else { return }
        let name = QuickActionQueue.appendedNotification as CFString
        // 使用 opaque 指针传递 context;回调中不持有 self(无 retain cycle 风险)。
        let ctxBox = Unmanaged.passRetained(ContextBox(context: context)).toOpaque()
        CFNotificationCenterAddObserver(
            center, ctxBox,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<ContextBox>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    WidgetQuickDrain.drainIfNeeded(context: box.context)
                }
            },
            name, nil, .deliverImmediately
        )
    }
}

/// 持有 ModelContext 的引用类型容器,供 Darwin 通知回调跨指针传递。
private final class ContextBox {
    let context: ModelContext
    init(context: ModelContext) { self.context = context }
}

// MARK: - Appearance & text-size modifier

/// Applies the user's preferred display appearance and Dynamic Type adjustment.
/// Reads environment sizes and applies a relative offset so system accessibility
/// ranges remain intact.
private struct AppearanceModifier: ViewModifier {
    let mode: AppAppearanceMode
    let textSize: AppTextSizePreference
    @Environment(\.dynamicTypeSize) private var systemTypeSize

    func body(content: Content) -> some View {
        let adjusted = AppTextSizePreference.adjustedSize(systemTypeSize, preference: textSize)
        content
            .preferredColorScheme(mode.colorScheme)
            .environment(\.dynamicTypeSize, adjusted)
    }
}
