import Foundation
import WatchConnectivity

/// 层级 4 · 手表侧连接。接收手机推来的快照,把快速记录送回手机。
///
/// 投递用三条通道叠加,任何一条通就能到:
///   1. `sendMessage`         —— 手机可达时立即送达;
///   2. `transferUserInfo`    —— 排队投递,手机不在旁边也不丢(真机主力);
///   3. `applicationContext`  —— 发布「最近若干条」,靠幂等重放兜底。
/// 手机侧落库是按 dayKey 的 upsert,重复到达不会产生重复数据。
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var snapshot: WidgetSnapshot = .placeholder
    /// 最近一次发送时间(用于给用户「已记录」的反馈)。
    @Published var lastSent: Date?

    private let cacheKey = "vela.watch.snapshot"
    private let recentKey = "vela.watch.recentLogs"

    /// 会话激活前发起的记录。未激活时投递会静默失败,
    /// 用户刚打开手表 app 就点击的话记录会凭空消失,所以先攒着,激活后补发。
    private var outbox: [QuickLog] = []
    /// 最近发出的记录(用于 applicationContext 冗余通道)。
    private var recent: [QuickLog] = []

    override init() {
        super.init()
        // 冷启动先用上次缓存,避免一片空白。
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            snapshot = s
        }
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let r = try? JSONDecoder().decode([QuickLog].self, from: data) {
            recent = r
        }
    }

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        // 拉一次已有的 applicationContext(手机可能在手表 app 打开前就推过了)。
        applyContext(session.receivedApplicationContext)
    }

    /// 发送一条快速记录。
    func send(_ log: QuickLog) {
        guard let session else { return }
        Task { @MainActor in self.lastSent = Date() }

        guard session.activationState == .activated else {
            outbox.append(log)   // 还没激活,先攒着
            activate()
            return
        }
        deliver(log, via: session)
    }

    /// 激活完成后把攒下的记录补发出去。
    private func flushOutbox() {
        guard let session, session.activationState == .activated, !outbox.isEmpty else { return }
        let queued = outbox
        outbox.removeAll()
        for log in queued { deliver(log, via: session) }
    }

    private func deliver(_ log: QuickLog, via session: WCSession) {
        guard let data = try? JSONEncoder().encode(log) else { return }

        if session.isReachable {
            // 通道 1:立即送达。
            session.sendMessage([WatchKeys.quickLog: data], replyHandler: nil) { _ in
                session.transferUserInfo([WatchKeys.quickLog: data])  // 失败退回排队
            }
        } else {
            // 通道 2:排队投递。
            session.transferUserInfo([WatchKeys.quickLog: data])
        }

        // 通道 3:把最近若干条作为 context 发布,幂等重放兜底。
        recent.append(log)
        recent = Array(recent.suffix(20))
        if let batch = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(batch, forKey: recentKey)
            try? session.updateApplicationContext([WatchKeys.quickLogBatch: batch])
        }
    }

    private func applyContext(_ context: [String: Any]) {
        guard let data = context[WatchKeys.snapshot] as? Data,
              let s = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        Task { @MainActor in self.snapshot = s }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        applyContext(session.receivedApplicationContext)
        flushOutbox()
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        applyContext(context)
    }
    // 注:sessionDidBecomeInactive / sessionDidDeactivate 是 iOS 专有的,
    // watchOS 上不可用,只在手机侧 PhoneConnectivity 实现。
}
