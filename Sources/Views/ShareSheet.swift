import SwiftUI
import UIKit

/// 包一层 UIActivityViewController,供 SwiftUI 弹出系统分享面板(导出 CSV 用)。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let temporaryURLs: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Self.cleanupTemporaryURLs(temporaryURLs)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    /// Only callers holding app-generated files in the system temporary directory may
    /// pass URLs here. The path guard prevents accidental deletion outside that scope.
    static func cleanupTemporaryURLs(_ urls: [URL]) {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let rootPrefix = temporaryRoot.hasSuffix("/") ? temporaryRoot : temporaryRoot + "/"

        for url in urls {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPrefix) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as NSError
                        where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                // Cleanup is idempotent when onDisappear runs after the completion handler.
            } catch {
                NSLog("Maren export cleanup failed for %@: %@", path, error.localizedDescription)
            }
        }
    }
}
