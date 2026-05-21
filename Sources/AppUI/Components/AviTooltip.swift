import SwiftUI

/// View modifier that shows a rich popover after a hover delay. Standardizes the timing
/// and dismiss behavior of branch / tag / ref popovers across the app.
struct AviTooltipModifier<Tooltip: View>: ViewModifier {
    let delay: Duration
    let arrowEdge: Edge
    @ViewBuilder let tooltip: () -> Tooltip

    @State private var isHovering = false
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    Task {
                        try? await Task.sleep(for: delay)
                        if isHovering { isShown = true }
                    }
                } else {
                    isShown = false
                }
            }
            .popover(isPresented: $isShown, arrowEdge: arrowEdge) {
                tooltip()
            }
    }
}

extension View {
    func aviTooltip<T: View>(
        delay: Duration = .milliseconds(400),
        arrowEdge: Edge = .bottom,
        @ViewBuilder content: @escaping () -> T
    ) -> some View {
        modifier(AviTooltipModifier(delay: delay, arrowEdge: arrowEdge, tooltip: content))
    }
}
