import SwiftUI

/// 自适应流式布局:每个子视图按**自身内容宽度**排布,一行排不下就换行。
///
/// 为什么不用 LazyVGrid:固定列宽会把长词(如 "Headache"、"Tender breasts")
/// 挤成两行甚至断词,中英文切换时尤其难看。流式布局让短标签紧凑、长标签完整,
/// 整体更整齐,也天然避免截断。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    /// 计算每个子视图的相对位置与整体尺寸。
    private func arrange(sizes: [CGSize], maxWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for size in sizes {
            // 当前行放不下(且不是行首)→ 换行。
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (positions, CGSize(width: usedWidth, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = arrange(sizes: sizes, maxWidth: maxWidth)
        // 宽度撑满可用空间,保证父容器左对齐稳定。
        return CGSize(width: proposal.width ?? result.size.width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = arrange(sizes: sizes, maxWidth: bounds.width)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x,
                            y: bounds.minY + result.positions[index].y),
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }
}
