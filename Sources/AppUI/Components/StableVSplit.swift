import AppKit
import SwiftUI

/// Two panes, one above the other, with a divider you drag. Unlike
/// `VSplitView`, the divider moves only when you drag it: the bottom pane keeps
/// the height you gave it while the panes' contents change, when switching
/// tabs or views rebuilds it, and across launches. It gives way only while the
/// window is too short for both panes, and comes back once it is tall again.
struct StableVSplit<Top: View, Bottom: View>: View {
    /// The bottom pane's height as you left it. Back it with `@AppStorage`.
    @Binding var bottomHeight: Double
    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    private let top: Top
    private let bottom: Bottom

    /// The bottom pane's height when the drag began.
    @State private var dragStart: CGFloat?

    static var dividerThickness: CGFloat {
        5
    }

    init(
        bottomHeight: Binding<Double>,
        minTopHeight: CGFloat,
        minBottomHeight: CGFloat,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        _bottomHeight = bottomHeight
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.top = top()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { proxy in
            let total = proxy.size.height
            let shown = Self.shownBottomHeight(bottomHeight, total: total, minTop: minTopHeight, minBottom: minBottomHeight)
            VStack(spacing: 0) {
                top
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                divider(shown: shown, total: total)
                    .zIndex(1)
                bottom
                    .frame(maxWidth: .infinity)
                    .frame(height: shown)
            }
        }
    }

    /// The height the bottom pane gets: the one you chose, unless that leaves
    /// the top pane under its minimum; never under the bottom's own minimum.
    static func shownBottomHeight(_ wanted: Double, total: CGFloat, minTop: CGFloat, minBottom: CGFloat) -> CGFloat {
        let room = total - dividerThickness - minTop
        return max(minBottom, min(CGFloat(wanted), room))
    }

    /// A hairline like `VSplitView`'s, on a strip of the panes' own color that
    /// is wide enough to grab.
    private func divider(shown: CGFloat, total: CGFloat) -> some View {
        Rectangle()
            .fill(DS.Palette.surfaceRaised)
            .frame(height: Self.dividerThickness)
            .overlay {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
            }
            .background(ResizeCursorArea())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? shown
                        if dragStart == nil {
                            dragStart = start
                        }
                        let room = total - Self.dividerThickness - minTopHeight
                        bottomHeight = Double(max(minBottomHeight, min(start - value.translation.height, room)))
                    }
                    .onEnded { _ in
                        dragStart = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Pane divider")
            .accessibilityValue("\(Int(shown)) points")
            .accessibilityAdjustableAction { direction in
                let room = total - Self.dividerThickness - minTopHeight
                let step: CGFloat = direction == .increment ? 20 : -20
                bottomHeight = Double(max(minBottomHeight, min(shown + step, room)))
            }
    }
}

/// Shows the up-down resize pointer over its frame. A cursor rect, so the
/// pointer stays right however the views under it set theirs, and it never
/// takes a click: the divider's drag gesture gets those.
private struct ResizeCursorArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> CursorView {
        CursorView()
    }

    func updateNSView(_: CursorView, context _: Context) {}

    final class CursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeUpDown)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
