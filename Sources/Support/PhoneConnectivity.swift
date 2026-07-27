import Foundation
import SwiftData
import WatchConnectivity

/// 层级 4 · 手机侧的手表连接。把快照推给手表,并接收手表发来的快速记录。
/// 纯设备间通信,不经过任何服务器。
///
/// 设计要点:**收到记录后直接落库,不依赖任何 SwiftUI 视图**。
/// WatchConnectivity 可能在 app 处于后台时投递,那时没有视图在监听;
/// 若把落库挂在视图的 onChange 上,后台送达的记录就会丢。
final class PhoneConnectivity: NSObject, ObservableObject {
    static let shared = PhoneConnectivity()

    /// 由 App 启动时注入,供收到记录时直接写库。
    @MainActor static var container: ModelContainer?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// 最近一次快照。会话尚未激活时先存下来,激活完成后补推 ——
    /// 否则 app 启动瞬间「推送」早于「激活完成」,这一次推送会被静默丢弃,手表一直显示占位符。
    private var lastSnapshot: WidgetSnapshot?

    /// 把最新快照推给手表(只保留最新一份,旧的会被覆盖)。
    func push(_ snapshot: WidgetSnapshot) {
        lastSnapshot = snapshot
        guard let session, session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext([WatchKeys.snapshot: data])
    }

    /// 激活完成后补推一次,填上激活期间错过的快照。
    fileprivate func flushSnapshot() {
        guard let snapshot = lastSnapshot else { return }
        push(snapshot)
    }

    /// 统一落库入口。三条通道(sendMessage / transferUserInfo / applicationContext)都走这里。
    /// `QuickLogApplier` 是按 dayKey 的幂等 upsert,所以同一条记录重复到达也不会出问题。
    fileprivate func ingest(_ payload: [String: Any]) {
        var logs: [QuickLog] = []
        // 单条:sendMessage / transferUserInfo
        if let data = payload[WatchKeys.quickLog] as? Data,
           let log = try? JSONDecoder().decode(QuickLog.self, from: data) {
            logs.append(log)
        }
        // 批量:applicationContext 只保留最新一份且会互相覆盖,
        // 所以手表放的是「最近若干条」的数组,靠幂等重放补齐。
        if let data = payload[WatchKeys.quickLogBatch] as? Data,
           let batch = try? JSONDecoder().decode([QuickLog].self, from: data) {
            logs.append(contentsOf: batch)
        }
        guard !logs.isEmpty else { return }

        Task { @MainActor in
            guard let container = PhoneConnectivity.container else { return }
            // 用 mainContext 写入,@Query 能立刻把变化反映到界面。
            QuickLogApplier.apply(logs, context: container.mainContext)
        }
    }
}

extension PhoneConnectivity: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        guard state == .activated else { return }
        flushSnapshot()
        // 激活时兜一遍手表已发布的 context,避免错过激活前送达的记录。
        ingest(session.receivedApplicationContext)
    }

    // iOS 端必须实现这两个,否则切换手表时会话会失效。
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// 即时通道(两端都在前台时)。
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingest(message)
    }

    /// 排队通道(真机上的主力:手机不在旁边也会排队,不丢)。
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        ingest(userInfo)
    }

    /// 冗余通道:手表把「最近若干条记录」作为 context 发布,幂等重放。
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        ingest(context)
    }
}
