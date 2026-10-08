import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Clicks on a folder row of the Unstaged list: the chevron only opens and
/// closes the folder, and a click on the name never reaches it. Selecting the
/// folder's row selects the folder and its files.
///
/// The selection goes through the table, as in ChangesArrowKeysTests. A real
/// click on the name selects through the row's drag gesture, but on the CI
/// runner a synthetic click there selects nothing, however it is delivered.
final class FolderRowClickTests: XCTestCase {
    func testChevronTogglesAndSelectingTheFolderSelectsItsFiles() throws {
        try MainActor.assumeIsolated {
            guard ConfigStore.shared.config.appearance.fileListMode == "tree" else {
                throw XCTSkip("Folder rows show in tree mode only.")
            }
            let fixture = try Fixture()
            defer { fixture.close() }
            let table = try XCTUnwrap(fixture.unstagedTable)
            // Rows: 0 "Sources/App", 1 a.swift, 2 b.swift, 3 README.md.
            XCTAssertEqual(table.numberOfRows, 4)

            fixture.click(table, row: 0, atX: 13)
            XCTAssertFalse(fixture.store.expandedFolders.contains("Sources/App"), "the chevron collapses the folder")
            XCTAssertTrue(table.selectedRowIndexes.isEmpty, "the chevron does not select")

            fixture.click(table, row: 0, atX: 13)
            XCTAssertTrue(fixture.store.expandedFolders.contains("Sources/App"), "the chevron expands it again")

            fixture.select(table, row: 0)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([0, 1, 2]), "the folder's row selects the folder and its files")
            XCTAssertTrue(fixture.store.expandedFolders.contains("Sources/App"), "selecting leaves the folder open")

            fixture.select(table, row: 3)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([3]), "a file's row selects just that file")

            fixture.select(table, row: 0)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([0, 1, 2]), "selecting the folder after a file takes its files, not the file")

            fixture.click(table, row: 0, atX: 90)
            XCTAssertTrue(fixture.store.expandedFolders.contains("Sources/App"), "a click on the name leaves the folder open")
        }
    }

    @MainActor
    private final class Fixture {
        let store: RepositoryStore
        let window: NSWindow
        let host: NSHostingView<ChangeListView>
        /// Numbers the clicks: a mouse-down and its mouse-up share a number,
        /// as they do from the window server.
        private var clicks = 0

        init() throws {
            _ = NSApplication.shared
            let provider = FakeGitProvider(status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: "a1"),
                entries: [
                    FileStatus(path: "Sources/App/a.swift", index: .unmodified, worktree: .modified),
                    FileStatus(path: "Sources/App/b.swift", index: .unmodified, worktree: .modified),
                    FileStatus(path: "README.md", index: .unmodified, worktree: .modified)
                ]
            ))
            store = RepositoryStore(git: provider)
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("avi-folder-click-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = store
            let opened = XCTestExpectation(description: "repository opened")
            Task { @MainActor in
                await store.open(root)
                opened.fulfill()
            }
            XCTAssertEqual(XCTWaiter().wait(for: [opened], timeout: 5), .completed)
            store.stopBackgroundObservation()

            host = NSHostingView(rootView: ChangeListView(store: store))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            waitUntil { self.unstagedTable?.numberOfRows == 4 }
        }

        /// The Unstaged list: the topmost table.
        var unstagedTable: NSTableView? {
            tables(in: host).max { frameInWindow($0).maxY < frameInWindow($1).maxY }
        }

        /// A click delivered the way the window server delivers one: the
        /// mouse-down and its later mouse-up both wait in the event queue, and
        /// NSApp dispatches them in order. A mouse-down that tracks the mouse
        /// finds its mouse-up waiting, so the click cannot hang.
        func click(_ table: NSTableView, row: Int, atX x: CGFloat) {
            let rect = table.convert(table.rect(ofRow: row), to: nil)
            let point = NSPoint(x: rect.minX + x, y: rect.midY)
            clicks += 1
            NSApp.postEvent(event(.leftMouseDown, at: point), atStart: false)
            NSApp.postEvent(event(.leftMouseUp, at: point), atStart: false)
            while let next = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(next)
            }
            settle()
        }

        /// Selects `row` through the table, as the row's drag gesture does on a
        /// real click; the list then widens a folder to its files.
        func select(_ table: NSTableView, row: Int) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            settle()
        }

        func close() {
            window.close()
        }

        private func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: clicks, clickCount: 1, pressure: 1
            )!
        }

        private func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
        }

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
