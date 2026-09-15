import AppKit
@testable import AppUI
import SwiftUI
import Testing

@Suite("History layout")
@MainActor
struct HistoryLayoutTests {
    @Test func emptySelectionFillsWorkspaceAfterResize() throws {
        _ = NSApplication.shared
        // Do not open a repository: no Git commands, watchers, or saved workspace changes.
        let store = RepositoryStore()
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            Text("Toolbar").frame(maxWidth: .infinity).frame(height: 40)
            HistoryWorkspaceView(store: store)
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1500, height: 950),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }

        for width in [1500.0, 760.0, 1500.0] {
            window.setContentSize(NSSize(width: width, height: 950))
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            let split = try #require(verticalStack(in: host))
            #expect(abs(split.bounds.width - host.bounds.width) < 1)
            #expect(split.arrangedSubviews.count == 2)
            for pane in split.arrangedSubviews {
                #expect(abs(pane.frame.width - host.bounds.width) < 1)
            }
        }
    }

    private func verticalStack(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, !split.isVertical {
            return split
        }
        return view.subviews.compactMap { verticalStack(in: $0) }.first
    }
}
