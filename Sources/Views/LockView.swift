import SwiftUI

/// 层级 3 · 锁屏遮罩。App 锁开启且未解锁时,盖在全部内容之上。
struct LockView: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        ZStack {
            // 不透明背景,确保锁定时看不到任何记录内容。
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(FlowLevel.medium.tint)
                Text("Maren 已锁定").font(.title3.weight(.semibold))
                if lock.deviceAuthUnavailable {
                    Text("这台设备没有设置密码、Face ID 或 Touch ID,无法验证身份。你可以前往「设置」为设备设置密码,或选择仍然进入。")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button {
                        lock.forceUnlock()
                    } label: {
                        Label("仍然进入", systemImage: "lock.open")
                            .padding(.horizontal, 24).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FlowLevel.medium.tint)
                } else {
                    Text("你的记录只在这台设备上。验证身份后即可查看。")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button {
                        lock.authenticate()
                    } label: {
                        Label(lock.failed ? String(localized: "重试") : String(localized: "解锁"),
                              systemImage: "faceid")
                            .padding(.horizontal, 24).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FlowLevel.medium.tint)
                }
            }
        }
        .onAppear { lock.authenticate() }
    }
}
