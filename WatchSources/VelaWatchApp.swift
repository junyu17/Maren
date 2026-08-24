import SwiftUI

@main
struct VelaWatchApp: App {
    @StateObject private var conn = WatchConnectivityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(conn)
                .onAppear {
                    conn.activate()
                    conn.drainWatchQueue()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        conn.drainWatchQueue()
                    }
                }
                // Widget deep link: watch complications/widgetURL 点击后打开 app。
                // marenwatch://log → 打开 app,现有根视图已提供快速记录入口。
                .onOpenURL { _ in
                    // 无需特定路由处理:WatchRootView 已包含快速记录入口。
                }
        }
    }
}
