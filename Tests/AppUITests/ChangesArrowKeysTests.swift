import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Presses the arrow keys on the real Changes lists. Each list gives its
/// files in the same order flat and as a tree, so this holds in either mode.
final class ChangesArrowKeysTests: XCTestCase {
    func testArrowsStepThroughUnstagedFilesAndSkipFolders() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            fixture.focus(fixture.unstagedList)
            XCTAssertEqual(fixture.press(.down, times: 4), ["Sources/App/a.swift", "Sources/App/b.swift", "Sources/Kit/c.swift", "Sources/Kit/c.swift"])
            XCTAssertEqual(fixture.press(.up, times: 3), ["Sources/App/b.swift", "Sources/App/a.swift", "Sources/App/a.swift"])
            XCTAssertEqual(fixture.store.selectedDiffSource, .unstaged)
        }
    }

    func testArrowsStepThroughStagedAndPlannedFilesAndSkipHeadings() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            fixture.focus(fixture.stackList)
            // In a tree, the docs/notes folder sits between x.md and z.md.
            XCTAssertEqual(fixture.press(.down, times: 4), ["docs/guide/x.md", "docs/notes/z.md", "docs/y.md", "LICENSE"])
            XCTAssertEqual(fixture.store.selectedDiffSource, .staged)
            XCTAssertNil(fixture.store.selectedDraftID, "a staged file belongs to Commit 1")

            // Past the planned commit's heading, straight to its file.
            XCTAssertEqual(fixture.press(.down, times: 2), ["README.md", "README.md"])
            XCTAssertEqual(fixture.store.selectedDraftID, fixture.draftID)

            XCTAssertEqual(fixture.press(.up, times: 5), ["LICENSE", "docs/y.md", "docs/notes/z.md", "docs/guide/x.md", "docs/guide/x.md"])
        }
    }

    @MainActor
    private final class Fixture {
        let store: RepositoryStore
        let draftID: UUID
        let window: NSWindow
        let host: NSHostingView<ChangeListView>

        init() throws {
            _ = NSApplication.shared
            // Listed in the order a tree shows them, so flat and tree mode agree.
            let provider = FakeGitProvider(status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: "a1"),
                entries: [
                    FileStatus(path: "Sources/App/a.swift", index: .unmodified, worktree: .modified),
                    FileStatus(path: "Sources/App/b.swift", index: .unmodified, worktree: .modified),
                    FileStatus(path: "Sources/Kit/c.swift", index: .unmodified, worktree: .modified),
                    FileStatus(path: "README.md", index: .unmodified, worktree: .modified),
                    FileStatus(path: "docs/guide/x.md", index: .modified, worktree: .unmodified),
                    FileStatus(path: "docs/notes/z.md", index: .modified, worktree: .unmodified),
                    FileStatus(path: "docs/y.md", index: .added, worktree: .unmodified),
                    FileStatus(path: "LICENSE", index: .modified, worktree: .unmodified)
                ]
            ))
            store = RepositoryStore(git: provider)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("avi-arrow-keys-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = store
            let opened = XCTestExpectation(description: "repository opened")
            Task { @MainActor in
                await store.open(root)
                opened.fulfill()
            }
            XCTAssertEqual(XCTWaiter().wait(for: [opened], timeout: 5), .completed)
            store.stopBackgroundObservation()
            store.moveFiles(["README.md"], to: .newDraft)
            draftID = try XCTUnwrap(store.commitPlan.drafts.first?.id)
            store.selectStagedCommit()

            host = NSHostingView(rootView: ChangeListView(store: store))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 820),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        /// The Unstaged list sits above the commit stack.
        var unstagedList: NSTableView {
            lists[0]
        }

        var stackList: NSTableView {
            lists[1]
        }

        private var lists: [NSTableView] {
            let found = tables(in: host).sorted { frameInWindow($0).maxY > frameInWindow($1).maxY }
            XCTAssertEqual(found.count, 2, "expected the Unstaged list and the commit stack")
            return found
        }

        func focus(_ table: NSTableView) {
            XCTAssertTrue(window.makeFirstResponder(table))
            settle()
        }

        /// Presses `key` `times` times and returns the selected file after each press.
        func press(_ direction: ArrowDirection, times: Int) -> [String?] {
            (0 ..< times).map { _ in
                let code: UInt16 = direction == .down ? 125 : 126
                let scalar = UnicodeScalar(direction == .down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)!
                let characters = String(Character(scalar))
                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code
                )!
                window.sendEvent(event)
                settle()
                return store.selectedPath
            }
        }

        func close() {
            window.close()
        }

        private func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
        }

        private func tables(in view: NSView) -> [NSTableView] {
            ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap { tables(in: $0) }
        }

        private func frameInWindow(_ table: NSTableView) -> NSRect {
            let view: NSView = table.enclosingScrollView ?? table
            return view.convert(view.bounds, to: nil)
        }
    }
}
