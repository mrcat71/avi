import AppKit
import SwiftUI

/// A panel that opens under a view while the pointer rests on it, like a menu
/// that needs no click, and stays open while the pointer moves into it.
/// It is a separate panel that never becomes key, so it opens over whatever
/// you are typing in without taking the keyboard from it.
@MainActor
final class HoverPanel {
    /// How long the pointer rests on a view before the panel opens, so
    /// passing over it on the way elsewhere opens nothing.
    static let openDelay: Duration = .milliseconds(350)
    /// How long the panel waits once the pointer left, so it can cross the
    /// gap between the view and the panel.
    static let closeDelay: Duration = .milliseconds(250)

    private var panel: NSPanel?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// Who the panel is open for, such as a tab's id.
    private(set) var ownerID: String?
    private var pointerInPanel = false

    var isOpen: Bool {
        panel?.isVisible == true
    }

    /// The pointer came onto `anchor`. The panel opens after a moment, or at
    /// once when it is already open for a neighbor, as a menu bar does.
    func pointerEntered(_ ownerID: String, anchor: NSView, content: @escaping () -> AnyView) {
        hideTask?.cancel()
        showTask?.cancel()
        if isOpen {
            if self.ownerID != ownerID {
                show(ownerID, anchor: anchor, content: content())
            }
            return
        }
        showTask = Task { [weak self, weak anchor] in
            try? await Task.safeSleep(for: Self.openDelay)
            guard !Task.isCancelled, let self, let anchor else { return }
            show(ownerID, anchor: anchor, content: content())
        }
    }

    func pointerExited() {
        showTask?.cancel()
        scheduleHide()
    }

    /// Reported by the panel's content, so moving into it keeps it open.
    func pointerInPanel(_ inside: Bool) {
        pointerInPanel = inside
        if inside {
            hideTask?.cancel()
        } else {
            scheduleHide()
        }
    }

    func hide() {
        showTask?.cancel()
        hideTask?.cancel()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        ownerID = nil
        pointerInPanel = false
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.safeSleep(for: Self.closeDelay)
            guard !Task.isCancelled, let self, !pointerInPanel else { return }
            hide()
        }
    }

    private func show(_ ownerID: String, anchor: NSView, content: AnyView) {
        guard let window = anchor.window else { return }
        let panel = panel ?? Self.makePanel()
        self.panel = panel
        let hosting = FirstClickHostingView(rootView: content)
        panel.contentView = hosting
        let size = hosting.fittingSize
        let anchorFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var origin = NSPoint(x: anchorFrame.minX, y: anchorFrame.minY - size.height - 2)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
        self.ownerID = ownerID
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }
}

/// Takes the click that lands on it even though its panel is never key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}

/// Hands the NSView under a SwiftUI view to `found`, for anchoring a panel.
struct AnchorView: NSViewRepresentable {
    let found: (NSView) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = PassThroughView()
        DispatchQueue.main.async { found(view) }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class PassThroughView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}
