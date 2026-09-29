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
            fixture.press(.down, expecting: ["Sources/App/a.swift", "Sources/App/b.swift", "Sources/Kit/c.swift", "Sources/Kit/c.swift"])
            fixture.press(.up, expecting: ["Sources/App/b.swift", "Sources/App/a.swift", "Sources/App/a.swift"])
            XCTAssertEqual(fixture.store.selectedDiffSource, .unstaged)
        }
    }

    func testArrowsStepThroughStagedAndPlannedFilesAndSkipHeadings() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            fixture.focus(fixture.stackList)
            // In a tree, the docs/notes folder sits between x.md and z.md.
            fixture.press(.down, expecting: ["docs/guide/x.md", "docs/notes/z.md", "docs/y.md", "LICENSE"])
            XCTAssertEqual(fixture.store.selectedDiffSource, .staged)
            XCTAssertNil(fixture.store.selectedDraftID, "a staged file belongs to Commit 1")

            // Past the planned commit's heading, straight to its file.
            fixture.press(.down, expecting: ["README.md", "README.md"])
            XCTAssertEqual(fixture.store.selectedDraftID, fixture.draftID)

            fixture.press(.up, expecting: ["LICENSE", "docs/y.md", "docs/notes/z.md", "docs/guide/x.md", "docs/guide/x.md"])
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
            // The first render in a cold process can take longer than a settle.
            waitUntil { self.tables(in: self.host).count == 2 }
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

        /// Presses `direction` once per entry in `expected` and checks that each
        /// press selects that file. SwiftUI handles the key a few run loop turns
        /// after `sendEvent`, and the store follows in a task, so a cold CI runner
        /// can take longer than a settle: each press waits for its file instead.
        func press(_ direction: ArrowDirection, expecting expected: [String], file: StaticString = #filePath, line: UInt = #line) {
            let selected = expected.map { path -> String? in
                window.sendEvent(keyDown(direction))
                settle()
                waitUntil { self.store.selectedPath == path }
                return store.selectedPath
            }
            XCTAssertEqual(selected, expected.map(Optional.some), file: file, line: line)
        }

        func close() {
            window.close()
        }

        private func keyDown(_ direction: ArrowDirection) -> NSEvent {
            let code: UInt16 = direction == .down ? 125 : 126
            let scalar = UnicodeScalar(direction == .down ? NSDownArrowFunctionKey : NSUpArrowFunctionKey)!
            let characters = String(Character(scalar))
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code
            )!
        }

        private func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
        }

        /// Runs the main run loop until `condition` holds or `timeout` passes.
        private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
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
