import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Opens the real discard confirmation the way Cmd+Shift+D does and answers it
/// from the keyboard, so Return keeps confirming and Escape keeps cancelling.
final class DiscardConfirmationKeyTests: XCTestCase {
    func testReturnConfirmsTheDiscard() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            let sheet = try XCTUnwrap(fixture.requestDiscard(), "Cmd+Shift+D opens the confirmation")
            sheet.sendEvent(fixture.key("\r", code: 36, in: sheet))
            fixture.waitUntil { !fixture.provider.discardCalls.isEmpty }

            XCTAssertEqual(fixture.provider.discardCalls, [["a.txt"]])
        }
    }

    func testEscapeCancelsTheDiscard() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            let sheet = try XCTUnwrap(fixture.requestDiscard(), "Cmd+Shift+D opens the confirmation")
            sheet.sendEvent(fixture.key("\u{1b}", code: 53, in: sheet))
            fixture.waitUntil { fixture.window.attachedSheet == nil }

            XCTAssertNil(fixture.window.attachedSheet)
            XCTAssertEqual(fixture.provider.discardCalls, [])
        }
    }

    @MainActor
    private final class Fixture {
        let provider: FakeGitProvider
        let store: RepositoryStore
        let window: NSWindow

        init() throws {
            _ = NSApplication.shared
            provider = FakeGitProvider(status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: "a1"),
                entries: [
                    FileStatus(path: "a.txt", index: .unmodified, worktree: .modified),
                    FileStatus(path: "b.txt", index: .unmodified, worktree: .modified)
                ]
            ))
            store = RepositoryStore(git: provider)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("avi-discard-keys-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = store
            let opened = XCTestExpectation(description: "repository opened")
            Task { @MainActor in
                await store.open(root)
                opened.fulfill()
            }
            XCTAssertEqual(XCTWaiter().wait(for: [opened], timeout: 5), .completed)
            store.stopBackgroundObservation()

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ChangeListView(store: store))
            window.makeKeyAndOrderFront(nil)
        }

        /// Selects a.txt in Unstaged and sends what Cmd+Shift+D sends. Returns
        /// the confirmation sheet once it is up.
        func requestDiscard() -> NSWindow? {
            guard let file = store.unstagedEntries.first(where: { $0.path == "a.txt" }) else { return nil }
            let selected = XCTestExpectation(description: "a.txt selected")
            Task { @MainActor in
                await self.store.select(file, source: .unstaged)
                selected.fulfill()
            }
            XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed)
            // The list picks up the store's selection on its next update.
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            NotificationCenter.default.post(name: .aviDiscardSelection, object: nil)
            waitUntil { self.window.attachedSheet != nil }
            // Let the sheet finish appearing before it takes keys.
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            return window.attachedSheet
        }

        func key(_ characters: String, code: UInt16, in target: NSWindow) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code
            )!
        }

        /// Runs the main run loop until `condition` holds or `timeout` passes.
        func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        func close() {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.close()
        }
    }
}
