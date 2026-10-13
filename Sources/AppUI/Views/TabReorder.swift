import CoreGraphics

/// Where a dragged tab belongs: the place in the order that would put it
/// nearest to where it is drawn under the pointer. Every place is tried with
/// the tab taken out and put back there, so the answer depends only on where
/// the tab is drawn and never flips back on the next move. On one row the tab
/// passes a neighbor once its edge crosses that neighbor's middle, as Safari's
/// tabs do; across rows it goes to the nearest spot, and the rows rewrap.
///
/// - Parameters:
///   - index: the dragged tab's place now.
///   - drawn: the dragged tab's frame as drawn under the pointer.
///   - sizes: every tab's size, in display order.
///   - spacing, rowSpacing, width: how `tabRowFrames` lays the rows out.
/// - Returns: the tab's new place.
func tabDropIndex(
    dragged index: Int,
    drawnAt drawn: CGRect,
    sizes: [CGSize],
    spacing: CGFloat,
    rowSpacing: CGFloat,
    width: CGFloat
) -> Int {
    guard sizes.indices.contains(index) else { return index }
    var others = sizes
    let dragged = others.remove(at: index)
    var best = index
    var bestDistance = CGFloat.infinity
    for place in 0 ... others.count {
        var order = others
        order.insert(dragged, at: place)
        let frame = tabRowFrames(sizes: order, spacing: spacing, rowSpacing: rowSpacing, width: width)[place]
        let dx = frame.midX - drawn.midX
        let dy = frame.midY - drawn.midY
        if dx * dx + dy * dy < bestDistance {
            bestDistance = dx * dx + dy * dy
            best = place
        }
    }
    return best
}
