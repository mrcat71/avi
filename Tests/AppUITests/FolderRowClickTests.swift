import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Real clicks on a folder row of the Unstaged list: the chevron only opens
/// and closes the folder; the rest of the row selects the folder and its files.
final class FolderRowClickTests: XCTestCase {
    func testChevronTogglesAndNameSelectsTheFolderWithItsFiles() throws {
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

            fixture.click(table, row: 0, atX: 90)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([0, 1, 2]), "the name selects the folder and its files")
            XCTAssertTrue(fixture.store.expandedFolders.contains("Sources/App"), "selecting leaves the folder open")

            fixture.click(table, row: 3, atX: 90)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([3]), "a file click selects just that file")

            fixture.click(table, row: 0, atX: 200)
            fixture.click(table, row: 0, atX: 200)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([0, 1, 2]), "clicking the selected folder again keeps its files")
        }
    }

    @MainActor
    private final class Fixture {
        let store: RepositoryStore
        let window: NSWindow
        let host: NSHostingView<ChangeListView>

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

        /// A click that cannot hang. When the window is key, as on a CI runner,
        /// NSTableView's mouse-down tracks the mouse until a mouse-up arrives in
        /// the event queue, so the mouse-up is queued before the mouse-down is
        /// sent. Where nothing tracked, it is still waiting and is sent after.
        func click(_ table: NSTableView, row: Int, atX x: CGFloat) {
            let rect = table.convert(table.rect(ofRow: row), to: nil)
            let point = NSPoint(x: rect.minX + x, y: rect.midY)
            NSApp.postEvent(event(.leftMouseUp, at: point), atStart: false)
            window.sendEvent(event(.leftMouseDown, at: point))
            if let pending = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                window.sendEvent(pending)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
        }

        func close() {
            window.close()
        }

        private func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )!
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
