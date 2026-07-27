import SwiftUI

@main
struct VelaWatchApp: App {
    @StateObject private var conn = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(conn)
                .onAppear { conn.activate() }
        }
    }
}
