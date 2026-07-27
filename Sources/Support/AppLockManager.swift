import Foundation
import LocalAuthentication

/// 层级 3 · 应用锁。后 Dobbs 时代,美国用户最担心的就是「别人翻我的经期数据」,
/// 生物识别锁是主打隐私定位的必配。纯本地,`LocalAuthentication`,不联网。
@MainActor
final class AppLockManager: ObservableObject {
    /// 当前是否已解锁(本次前台会话内有效)。
    @Published var unlocked = false
    /// 上次鉴权是否失败(用于在锁屏上提示重试)。
    @Published var failed = false
    /// 正在鉴权中。防止 `LockView.onAppear` 与 `RootView.scenePhase=.active`
    /// 在冷启动时同时触发两次 `evaluatePolicy`,导致系统弹窗闪两次 / 互相取消。
    private var isAuthenticating = false

    func authenticate() {
        // 已解锁或正在鉴权 -> 不重复弹系统验证。
        guard !unlocked, !isAuthenticating else { return }
        let ctx = LAContext()
        var err: NSError?
        // 用 deviceOwnerAuthentication:优先生物识别,不可用时回落到设备密码。
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // 设备没有任何鉴权方式(如模拟器未设密码)→ 不把用户锁死,直接放行。
            unlocked = true
            return
        }
        isAuthenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: String(localized: "解锁 Maren 查看你的记录")) { ok, _ in
            Task { @MainActor in
                self.isAuthenticating = false
                self.unlocked = ok
                self.failed = !ok
            }
        }
    }

    /// 进入后台时上锁,下次回前台需要重新鉴权。
    func lock() {
        unlocked = false
        failed = false
        isAuthenticating = false
    }
}
