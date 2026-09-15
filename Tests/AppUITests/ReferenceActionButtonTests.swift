import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Drives the real native component with callbacks, never a repository or Git process.
final class ReferenceActionButtonTests: XCTestCase {
    func testPrimaryClickOnlyInspectsEveryRefKind() {
        MainActor.assumeIsolated {
            for kind in [GitReferenceKind.tag, .localBranch, .remoteBranch] {
                let fixture = Fixture(kind: kind)
                defer { fixture.close() }
                fixture.click()
                XCTAssertEqual(fixture.calls.selections, 1)
                XCTAssertTrue(fixture.calls.checkouts.isEmpty)
                XCTAssertNil(fixture.dialog)
            }
        }
    }

    func testShowCommitMenuOnlyInspects() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }
            try fixture.choose("Show Commit")
            XCTAssertEqual(fixture.calls.selections, 1)
            XCTAssertTrue(fixture.calls.checkouts.isEmpty)
            XCTAssertNil(fixture.dialog)
        }
    }

    func testTagCheckoutRequiresConfirmationAndCancelDoesNothing() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }
            try fixture.choose("Check Out Tag...")
            XCTAssertTrue(fixture.calls.checkouts.isEmpty)
            let dialog = try XCTUnwrap(fixture.dialog)
            let content = try XCTUnwrap(dialog.contentView)
            let message = fixture.text(in: content).joined(separator: "\n")
            XCTAssertTrue(message.contains("detach HEAD"))
            XCTAssertTrue(message.contains("You have local changes"))
            XCTAssertTrue(message.contains("will not stash or discard"))
            try XCTUnwrap(fixture.button(in: content, title: "Cancel")).performClick(nil)
            fixture.settle()
            XCTAssertTrue(fixture.calls.checkouts.isEmpty)
            XCTAssertEqual(fixture.calls.selections, 0)
        }
    }

    func testConfirmChecksOutOnce() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture(hasLocalChanges: false)
            defer { fixture.close() }
            try fixture.choose("Check Out Tag...")
            XCTAssertTrue(fixture.calls.checkouts.isEmpty)
            let content = try XCTUnwrap(fixture.dialog?.contentView)
            XCTAssertFalse(fixture.text(in: content).joined().contains("You have local changes"))
            try XCTUnwrap(fixture.button(in: content, title: "Check Out Tag")).performClick(nil)
            fixture.settle()
            XCTAssertEqual(fixture.calls.checkouts, [fixture.ref])
            XCTAssertEqual(fixture.calls.selections, 0)
        }
    }

    func testBranchCheckoutRemainsAnExplicitMenuAction() throws {
        try MainActor.assumeIsolated {
            for (kind, title) in [(GitReferenceKind.localBranch, "Check Out Branch"), (.remoteBranch, "Track Branch")] {
                let fixture = Fixture(kind: kind)
                defer { fixture.close() }
                try fixture.choose(title)
                XCTAssertEqual(fixture.calls.checkouts, [fixture.ref])
                XCTAssertEqual(fixture.calls.selections, 0)
                XCTAssertNil(fixture.dialog)
            }
        }
    }

    @MainActor
    private final class Fixture {
        final class Calls {
            var selections = 0
            var checkouts: [GitReference] = []
        }

        let ref: GitReference
        let calls = Calls()
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let existingWindows: Set<ObjectIdentifier>

        init(kind: GitReferenceKind = .tag, hasLocalChanges: Bool = true) {
            _ = NSApplication.shared
            existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
            ref = GitReference(name: "release", fullName: "refs/\(kind.rawValue)/release",
                               oid: String(repeating: "a", count: 40), kind: kind)
            let calls = calls
            let ref = ref
            host = NSHostingView(rootView: AnyView(
                HStack {
                    ReferenceActionButton(ref: ref, hasLocalChanges: hasLocalChanges,
                                          select: { calls.selections += 1 }, checkout: { calls.checkouts.append($0) }) {
                        Text("release").frame(width: 300, height: 40)
                    }
                }
                .contextMenu {
                    // History rows have their own menu; the ref menu must remain reachable.
                    Button("Row Action") { XCTFail("The parent menu must not replace ref actions") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        var dialog: NSWindow? {
            NSApp.windows.first { candidate in
                candidate !== window && !existingWindows.contains(ObjectIdentifier(candidate))
                    && candidate.isVisible
                    && candidate.contentView.map { button(in: $0, title: "Check Out Tag") != nil } == true
            }
        }

        func close() {
            if let content = dialog?.contentView {
                button(in: content, title: "Cancel")?.performClick(nil)
            }
            window.close()
        }

        func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()
        }

        func click() {
            window.sendEvent(event(.leftMouseDown))
            window.sendEvent(event(.leftMouseUp))
            settle()
        }

        func choose(_ title: String) throws {
            let hit = try XCTUnwrap(host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.midY)))
            let menu = try XCTUnwrap(hit.menu(for: event(.rightMouseDown)))
            let index = menu.indexOfItem(withTitle: title)
            XCTAssertGreaterThanOrEqual(index, 0)
            guard index >= 0 else { return }
            menu.performActionForItem(at: index)
            settle()
        }

        func button(in view: NSView, title: String) -> NSButton? {
            if let button = view as? NSButton, button.title == title {
                return button
            }
            return view.subviews.compactMap { button(in: $0, title: title) }.first
        }

        func text(in view: NSView) -> [String] {
            if let field = view as? NSTextField {
                return [field.stringValue]
            }
            return view.subviews.flatMap { text(in: $0) }
        }

        private func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: host.bounds.midX, y: host.bounds.midY),
                               modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                               clickCount: 1, pressure: 1)!
        }
    }
}
