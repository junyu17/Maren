import SwiftUI
import UIKit

/// 包一层 UIActivityViewController,供 SwiftUI 弹出系统分享面板(导出 CSV 用)。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
