import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

final class CommitTagsRowTests: XCTestCase {
    func testAddTagIsAvailableBeforeTheCommitHasAnyTags() throws {
        try XCTSkipUnless(OnScreenTests.enabled, OnScreenTests.skipMessage)
        MainActor.assumeIsolated {
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
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 310, y: 20), modifierFlags: [],
                                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                XCTAssertEqual(store.tagEditRequest?.target, target)
                XCTAssertNil(store.tagEditRequest?.original)
                XCTAssertTrue(store.tags(for: target).isEmpty, "Opening the editor must not create a tag")
            }
        }
    }
}
