import SwiftUI

extension View {
    func tabBarMinimizeOnScrollIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            return self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            return self
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    /// 本地数据库是否打开失败(降级为仅内存)。
    var storeFailed: Bool = false

    /// 允许通过启动参数选择初始标签页(便于自动化自测);默认日历。
    @State private var selection: Int = ScreenshotRoute.current?.tab
        ?? (ProcessInfo.processInfo.arguments.contains("--start-today") ? 1 : 0)
    @State private var showStoreAlert = false

    // 层级 3:首次引导 + 应用锁。
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage("lock.enabled") private var lockEnabled = false
    @StateObject private var lock = AppLockManager()
    // 层级 4:主题强调色。
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.rose.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .rose }
    // 层级 4:手表连接。手表发来的快速记录在这里落库。
    @StateObject private var watch = PhoneConnectivity.shared

    var body: some View {
        mainTabs
            .privacySensitive()  // 双保险:即便锁屏动画未及完成,快照也自动打码
            .fullScreenCover(isPresented: Binding(get: { !onboardingDone },
                                                  set: { onboardingDone = !$0 })) {
                OnboardingView { onboardingDone = true }
            }
            .fullScreenCover(isPresented: Binding(get: { lockEnabled && !lock.unlocked },
                                                  set: { _ in })) {
                // 用 fullScreenCover 而非 overlay:sheet 模态层会被 overlay 盖不住,
                // 开 sheet 时切后台再回前台,锁屏会被 sheet 压住,健康数据未解锁可见。
                LockView(lock: lock)
            }
            .onAppear { watch.activate() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                // .inactive 就上锁(而不是 .background):
                // App Switcher 的快照在进入后台时拍摄,等 .background 再锁会拍到完整健康数据。
                case .inactive, .background:
                    if lockEnabled { lock.lock() }
                case .active:
                    if lockEnabled && !lock.unlocked { lock.authenticate() }
                    // 切回前台时排空小组件队列,确保快速操作不遗漏。
                    WidgetQuickDrain.drainIfNeeded(context: context)
                default: break
                }
            }
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            CalendarView()
                .tabItem {
                    Label("日历", systemImage: "calendar")
                }
                .tag(0)

            DailyLogView()
                .tabItem {
                    Label("今天", systemImage: "heart.text.square")
                }
                .tag(1)

            TrendsView()
                .tabItem {
                    Label("趋势", systemImage: "chart.xyaxis.line")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(3)
        }
        .tint(theme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .tabBarMinimizeOnScrollIfAvailable()
        .onAppear {
            showStoreAlert = storeFailed
            // 把自定义症状快照加载进静态注册表,供导出/洞察等非 View 场景解析显示名。
            CustomSymptomStore.refresh(context)
        }
        .alert("暂时无法打开本地数据库", isPresented: $showStoreAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("这次启动的记录不会被保存。请重启 app 再试;如果仍有问题,请确认设备存储空间是否充足。你已保存的数据没有被删除。")
        }
        // widget deep link:点开 widget 进对应标签页。中尺寸 ->「今天」记录;小尺寸 ->「日历」。
        .onOpenURL { url in
            switch url.host {
            case "today":    selection = 1
            case "calendar": selection = 0
            default: break
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [PeriodDay.self, DailyLog.self], inMemory: true)
}
