import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Cmd+A selects every file of a Changes list only while that list has
/// keyboard focus. A button's shortcut answers anywhere in its window, before
/// the Edit menu, so an always-on one took Cmd+A from the commit message.
final class SelectAllShortcutTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(OnScreenTests.enabled, OnScreenTests.skipMessage)
    }

    /// The file rows' menus show Cmd+C and other shortcuts too; only an open
    /// menu may answer them.
    func testEditingKeysInTheCommitMessageAreLeftToTheEditMenu() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            let field = try XCTUnwrap(fixture.summaryField, "the commit summary field")
            fixture.focus(field)
            for key in ["a", "c", "v", "x", "z"] {
                XCTAssertFalse(fixture.pressCommand(key), "the Edit menu gets Cmd+\(key.uppercased())")
            }
            XCTAssertTrue(fixture.window.firstResponder is NSTextView, "the summary keeps the keyboard")
            XCTAssertTrue(fixture.unstagedList.selectedRowIndexes.isEmpty, "no files were selected")
            XCTAssertTrue(fixture.stackList.selectedRowIndexes.isEmpty, "no files were selected")
        }
    }

    func testCommandAInTheUnstagedListSelectsItsFiles() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            fixture.focus(fixture.unstagedList)
            XCTAssertTrue(fixture.pressCommand("a"))
            fixture.waitUntil { fixture.unstagedList.selectedRowIndexes.count == 2 }
            XCTAssertEqual(fixture.unstagedList.selectedRowIndexes.count, 2, "a.txt and b.txt")
            XCTAssertTrue(fixture.stackList.selectedRowIndexes.isEmpty)
        }
    }

    func testCommandAInTheCommitStackSelectsItsFiles() throws {
        try MainActor.assumeIsolated {
            let fixture = try Fixture()
            defer { fixture.close() }

            fixture.focus(fixture.stackList)
            XCTAssertTrue(fixture.pressCommand("a"))
            fixture.waitUntil { fixture.stackList.selectedRowIndexes.count == 2 }
            XCTAssertEqual(fixture.stackList.selectedRowIndexes.count, 2, "staged c.txt and planned README.md, no headings")
            XCTAssertTrue(fixture.unstagedList.selectedRowIndexes.isEmpty)
        }
    }

    /// The Changes column next to a commit message, as in the window.
    private struct Harness: View {
        let store: RepositoryStore

        var body: some View {
            HStack(spacing: 0) {
                ChangeListView(store: store)
                    .frame(width: 320)
                CommitMessageEditor(
                    summary: Binding(get: { store.commitSummary }, set: { store.commitSummary = $0 }),
                    messageBody: Binding(get: { store.commitBody }, set: { store.commitBody = $0 })
                )
                .frame(width: 300)
            }
        }
    }

    @MainActor
    private final class Fixture {
        static let summary = "fix(ui): keep select all in text fields"

        let store: RepositoryStore
        let window: NSWindow
        let host: NSHostingView<Harness>

        init() throws {
            _ = NSApplication.shared
            // Files at the top level, so flat and tree mode show the same rows.
            let provider = FakeGitProvider(status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: "a1"),
                entries: [
                    FileStatus(path: "a.txt", index: .unmodified, worktree: .modified),
                    FileStatus(path: "b.txt", index: .unmodified, worktree: .modified),
                    FileStatus(path: "README.md", index: .unmodified, worktree: .modified),
                    FileStatus(path: "c.txt", index: .modified, worktree: .unmodified)
                ]
            ))
            store = RepositoryStore(git: provider)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("avi-select-all-\(UUID().uuidString)", isDirectory: true)
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
            store.selectStagedCommit()
            store.commitSummary = Self.summary

            host = NSHostingView(rootView: Harness(store: store))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
            // The first render in a cold process can take longer than a settle.
            waitUntil { self.tables(in: self.host).count == 2 && self.summaryField != nil }
        }

        /// The Unstaged list sits above the commit stack.
        var unstagedList: NSTableView {
            lists[0]
        }

        var stackList: NSTableView {
            lists[1]
        }

        var summaryField: NSTextField? {
            textFields(in: host).first { $0.stringValue == Self.summary }
        }

        private var lists: [NSTableView] {
            let found = tables(in: host).sorted { frameInWindow($0).maxY > frameInWindow($1).maxY }
            XCTAssertEqual(found.count, 2, "expected the Unstaged list and the commit stack")
            return found
        }

        func focus(_ view: NSView) {
            XCTAssertTrue(window.makeFirstResponder(view))
            settle()
        }

        /// Offers Command and `key` to the window, the way AppKit does before
        /// the menus. Returns whether the window took it.
        func pressCommand(_ key: String) -> Bool {
            let keyCodes: [String: UInt16] = ["a": 0, "z": 6, "x": 7, "c": 8, "v": 9]
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: keyCodes[key]!
            )!
            let handled = window.performKeyEquivalent(with: event)
            settle()
            return handled
        }

        func close() {
            window.close()
        }

        func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
        }

        /// Runs the main run loop until `condition` holds or `timeout` passes.
        func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }

        private func tables(in view: NSView) -> [NSTableView] {
            ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap { tables(in: $0) }
        }

        private func textFields(in view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { textFields(in: $0) }
        }

        private func frameInWindow(_ table: NSTableView) -> NSRect {
            let view: NSView = table.enclosingScrollView ?? table
            return view.convert(view.bounds, to: nil)
        }
    }
}
