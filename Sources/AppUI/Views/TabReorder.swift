import CoreGraphics

/// Where a tab dragged sideways in the tab bar belongs. It passes a neighbor
/// once its edge crosses the middle of that neighbor, as Safari's tabs do, and
/// it passes several at once when the pointer moves fast. Passing a neighbor
/// leaves the tab short of the middle it would cross going back, so it never
/// flips between two places.
///
/// - Parameters:
///   - index: the dragged tab's place now.
///   - offset: how far the pointer has moved the tab from that place.
///   - widths: every tab's width, in display order.
///   - spacing: the gap between tabs.
/// - Returns: the tab's new place, and its offset from that place, which keeps
///   it under the pointer once the tabs it passed move aside.
func tabDragTarget(index: Int, offset: CGFloat, widths: [CGFloat], spacing: CGFloat) -> (index: Int, offset: CGFloat) {
    var widths = widths
    var index = index
    var offset = offset
    while index + 1 < widths.count, offset > spacing + widths[index + 1] / 2 {
        offset -= widths[index + 1] + spacing
        widths.swapAt(index, index + 1)
        index += 1
    }
    while index > 0, offset < -(spacing + widths[index - 1] / 2) {
        offset += widths[index - 1] + spacing
        widths.swapAt(index, index - 1)
        index -= 1
    }
    return (index, offset)
}
