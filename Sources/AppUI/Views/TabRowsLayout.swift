import SwiftUI

/// Frames for tabs of `sizes` in rows `width` wide. Each tab goes after the
/// previous one, or starts the next row when it would not fit, so tabs that
/// fit keep one row. A tab wider than a row gets a row of its own.
func tabRowFrames(sizes: [CGSize], spacing: CGFloat, rowSpacing: CGFloat, width: CGFloat) -> [CGRect] {
    var frames: [CGRect] = []
    var x: CGFloat = 0
    var rowTop: CGFloat = 0
    var rowHeight: CGFloat = 0
    for size in sizes {
        if x > 0, x + size.width > width {
            rowTop += rowHeight + rowSpacing
            x = 0
            rowHeight = 0
        }
        frames.append(CGRect(origin: CGPoint(x: x, y: rowTop), size: size))
        x += size.width + spacing
        rowHeight = max(rowHeight, size.height)
    }
    return frames
}

/// Lays the tab bar's tabs out with `tabRowFrames`, filling the width it is
/// offered so the drag code can lay out the same rows.
struct TabRowsLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let used = frames(for: subviews, width: proposal.width).reduce(CGRect.null) { $0.union($1) }
        guard !used.isNull else { return CGSize(width: proposal.width ?? 0, height: 0) }
        return CGSize(width: proposal.width ?? used.maxX, height: used.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat?) -> [CGRect] {
        tabRowFrames(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            spacing: spacing,
            rowSpacing: rowSpacing,
            width: width ?? .infinity
        )
    }
}

/// Offers its content at most `maxHeight` and takes only the height the
/// content uses. `.frame(maxHeight:)` would grow to the maximum instead.
struct MaxHeightLayout: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: capped(proposal))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight))
    }
}
