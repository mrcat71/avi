import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Drives the real ref button's menu, so "the action is missing" is answerable
/// without launching the app.
final class TagActionMenuTests: XCTestCase {
    func testTagMenuOffersPushAndDelete() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }

            let titles = try fixture.menuTitles()
            XCTAssertTrue(titles.contains("Delete Tag..."), titles.joined(separator: " | "))
            XCTAssertTrue(titles.contains("Push Tag to 'origin'..."), titles.joined(separator: " | "))
            XCTAssertTrue(titles.contains("Copy Tag Name"))
        }
    }

    func testDeleteAsksFirstAndCanStayLocal() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }

            try fixture.choose("Delete Tag...")
            XCTAssertTrue(fixture.calls.deleted.isEmpty, "Delete must be confirmed first")
            let content = try XCTUnwrap(fixture.dialog(button: "Delete Locally")?.contentView)
            XCTAssertTrue(fixture.text(in: content).joined().contains("leaves the pushed copy on 'origin'"))
            try XCTUnwrap(fixture.button(in: content, title: "Delete Locally")).performClick(nil)
            fixture.settle()

            XCTAssertEqual(fixture.calls.deleted, [.init(tag: fixture.ref, remote: nil)])
            XCTAssertTrue(fixture.calls.pushed.isEmpty)
        }
    }

    func testDeleteCanAlsoRemoveTheTagFromTheRemote() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }

            try fixture.choose("Delete Tag...")
            let title = "Delete Locally and from 'origin'"
            let content = try XCTUnwrap(fixture.dialog(button: title)?.contentView)
            try XCTUnwrap(fixture.button(in: content, title: title)).performClick(nil)
            fixture.settle()

            XCTAssertEqual(fixture.calls.deleted, [.init(tag: fixture.ref, remote: "origin")])
            XCTAssertTrue(fixture.calls.pushed.isEmpty)
        }
    }

    func testReturnNeverConfirmsADelete() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }

            try fixture.choose("Delete Tag...")
            let content = try XCTUnwrap(fixture.dialog(button: "Delete Locally")?.contentView)
            let deletes = fixture.buttons(in: content).filter { $0.title.hasPrefix("Delete") }
            XCTAssertEqual(deletes.count, 2)
            for button in deletes {
                XCTAssertNotEqual(button.keyEquivalent, "\r", "\(button.title) must be clicked, not confirmed with Return")
            }
        }
    }

    func testWithoutARemoteOnlyTheLocalDeleteIsOffered() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture(pushRemote: nil)
            defer { fixture.close() }

            XCTAssertFalse(try fixture.menuTitles().contains(where: { $0.hasPrefix("Push Tag") }))
            try fixture.choose("Delete Tag...")
            let content = try XCTUnwrap(fixture.dialog(button: "Delete Tag")?.contentView)
            XCTAssertFalse(fixture.buttons(in: content).contains { $0.title.contains("from '") })
            try XCTUnwrap(fixture.button(in: content, title: "Delete Tag")).performClick(nil)
            fixture.settle()

            XCTAssertEqual(fixture.calls.deleted, [.init(tag: fixture.ref, remote: nil)])
        }
    }

    func testBranchesHaveNoTagActions() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture(kind: .localBranch)
            defer { fixture.close() }

            let titles = try fixture.menuTitles()
            XCTAssertFalse(titles.contains("Delete Tag..."))
            XCTAssertFalse(titles.contains(where: { $0.hasPrefix("Push Tag") }))
        }
    }

    @MainActor
    private final class Fixture {
        struct Deletion: Equatable {
            let tag: GitReference
            let remote: String?
        }

        final class Calls {
            var pushed: [GitReference] = []
            var deleted: [Deletion] = []
        }

        let ref: GitReference
        let calls = Calls()
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let existingWindows: Set<ObjectIdentifier>

        init(kind: GitReferenceKind = .tag, pushRemote: String? = "origin") {
            _ = NSApplication.shared
            existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
            ref = GitReference(
                name: "v0.2.2", fullName: "refs/tags/v0.2.2",
                oid: String(repeating: "a", count: 40), kind: kind
            )
            let calls = calls
            let ref = ref
            host = NSHostingView(rootView: AnyView(
                ReferenceActionButton(
                    ref: ref, hasLocalChanges: false,
                    select: {}, checkout: { _ in },
                    pushRemote: pushRemote,
                    pushTag: { calls.pushed.append($0) },
                    deleteTag: { calls.deleted.append(Deletion(tag: $0, remote: $1)) }
                ) {
                    Text(ref.name).frame(width: 260, height: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        func menuTitles() throws -> [String] {
            let hit = try XCTUnwrap(host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.midY)))
            let menu = try XCTUnwrap(hit.menu(for: event(.rightMouseDown)))
            return menu.items.map(\.title)
        }

        func choose(_ title: String) throws {
            let hit = try XCTUnwrap(host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.midY)))
            let menu = try XCTUnwrap(hit.menu(for: event(.rightMouseDown)))
            let index = menu.indexOfItem(withTitle: title)
            XCTAssertGreaterThanOrEqual(index, 0, "\(title) is missing from \(menu.items.map(\.title))")
            guard index >= 0 else { return }
            menu.performActionForItem(at: index)
            settle()
        }

        func dialog(button title: String) -> NSWindow? {
            NSApp.windows.first { candidate in
                candidate !== window && !existingWindows.contains(ObjectIdentifier(candidate))
                    && candidate.isVisible
                    && candidate.contentView.map { button(in: $0, title: title) != nil } == true
            }
        }

        func close() {
            for name in ["Cancel"] {
                if let content = dialog(button: name)?.contentView {
                    button(in: content, title: name)?.performClick(nil)
                }
            }
            window.close()
        }

        func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()
        }

        func button(in view: NSView, title: String) -> NSButton? {
            if let button = view as? NSButton, button.title == title {
                return button
            }
            return view.subviews.compactMap { button(in: $0, title: title) }.first
        }

        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }

        func text(in view: NSView) -> [String] {
            if let field = view as? NSTextField {
                return [field.stringValue]
            }
            return view.subviews.flatMap { text(in: $0) }
        }

        private func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: NSPoint(x: host.bounds.midX, y: host.bounds.midY),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )!
        }
    }
}
