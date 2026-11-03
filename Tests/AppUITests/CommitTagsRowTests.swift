import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

final class CommitTagsRowTests: XCTestCase {
    func testAddTagIsAvailableBeforeTheCommitHasAnyTags() throws {
        try XCTSkipUnless(OnScreenTests.enabled, OnScreenTests.skipMessage)
        MainActor.assumeIsolated {
            // Numbers the clicks: a mouse-down and its mouse-up share a
            // number, as they do from the window server.
            var clicks = 0
            for planned in [false, true] {
                let store = RepositoryStore(git: Fixtures.clean())
                let draft = CommitDraft(message: "chore(release): 0.10.1", files: ["version.swift"], source: .manual)
                store.commitPlan = planned ? CommitPlan(drafts: [draft]) : CommitPlan()
                let target: TagEditRequest.Target = planned ? .draft(draft.id) : .stagedCommit
                _ = NSApplication.shared
                let host = NSHostingView(rootView: CommitTagsRow(store: store, target: target).frame(width: 340, height: 40))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 40),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                defer { window.close() }
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                host.layoutSubtreeIfNeeded()
                // Delivered the way the window server delivers a click: the
                // mouse-down and its mouse-up both wait in the event queue and
                // NSApp dispatches them in order. A synchronous sendEvent of the
                // mouse-down hung CI: where the button tracks the mouse, the
                // tracker waits for its mouse-up, which had not been posted yet
                // (see FolderRowClickTests).
                clicks += 1
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    NSApp.postEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 310, y: 20), modifierFlags: [],
                                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                       context: nil, eventNumber: clicks, clickCount: 1, pressure: 1)!, atStart: false)
                }
                while let next = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date(), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(next)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                XCTAssertEqual(store.tagEditRequest?.target, target)
                XCTAssertNil(store.tagEditRequest?.original)
                XCTAssertTrue(store.tags(for: target).isEmpty, "Opening the editor must not create a tag")
            }
        }
    }
}
