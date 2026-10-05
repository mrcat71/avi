import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

/// Drives the real branch and changed-file context menus, so their contents
/// can be checked against Fork's without launching the app.
final class ContextMenuTests: XCTestCase {
    func testBranchMenuMatchesForksLayout() throws {
        try MainActor.assumeIsolated {
            let fixture = try MenuFixture(provider: Self.provider())
            defer { fixture.close() }
            let stable = try XCTUnwrap(fixture.store.refs.localBranches.first { $0.name == "stable" })
            try fixture.host(LocalBranchRow(ref: stable, store: fixture.store, isSelected: false, select: {}, checkout: {}))

            let menu = try fixture.menu()

            XCTAssertEqual(menu.items.map(\.title), [
                "Checkout…", "Checkout as Worktree…", "",
                "Fast-Forward to 'origin/stable'", "Push to 'origin'…", "Create Pull Request on 'origin'", "",
                "Merge into 'INFRA-15647-wrong-alerts-tg'…", "Rebase on 'stable'…", "Interactively Rebase on 'stable'…", "",
                "New Branch…", "New Tag…", "",
                "Tracking", "Rename…", "Delete…", "",
                "Copy Branch Name"
            ])
            XCTAssertTrue(try fixture.item("Fast-Forward to 'origin/stable'", in: menu).isEnabled)
            try fixture.assertShortcut("New Branch…", "b", [.command, .shift], in: menu)
            try fixture.assertShortcut("New Tag…", "g", [.command, .shift], in: menu)
            try fixture.assertShortcut("Copy Branch Name", "c", [.command], in: menu)
            XCTAssertFalse(try fixture.item("Delete…", in: menu).keyEquivalent.isEmpty, "Delete shows ⌫")

            let tracking = try XCTUnwrap(try fixture.item("Tracking", in: menu).submenu)
            XCTAssertEqual(tracking.items.map(\.title), ["origin/stable", "", "Other Remote Branch…", "Stop Tracking"])
            XCTAssertEqual(tracking.items.first?.state, .on)
        }
    }

    func testBranchMenuActionsReachTheSidebar() throws {
        try MainActor.assumeIsolated {
            let fixture = try MenuFixture(provider: Self.provider())
            defer { fixture.close() }
            let stable = try XCTUnwrap(fixture.store.refs.localBranches.first { $0.name == "stable" })
            let recorder = ActionRecorder()
            try fixture.host(LocalBranchRow(
                ref: stable, store: fixture.store, isSelected: false, select: {}, checkout: {},
                perform: { recorder.actions.append($0) }
            ))

            for title in ["Merge into 'INFRA-15647-wrong-alerts-tg'…", "Interactively Rebase on 'stable'…", "Checkout as Worktree…", "Delete…"] {
                try fixture.choose(title)
            }

            XCTAssertEqual(recorder.actions, [.merge, .interactiveRebase, .checkoutAsWorktree, .delete])
        }
    }

    func testTheCurrentBranchCannotBeMergedIntoItselfOrDeleted() throws {
        try MainActor.assumeIsolated {
            let fixture = try MenuFixture(provider: Self.provider())
            defer { fixture.close() }
            let current = try XCTUnwrap(fixture.store.refs.localBranches.first(where: \.isCurrent))
            try fixture.host(LocalBranchRow(ref: current, store: fixture.store, isSelected: false, select: {}, checkout: {}))

            let menu = try fixture.menu()

            XCTAssertFalse(menu.items.contains { $0.title.hasPrefix("Merge into") || $0.title.hasPrefix("Rebase on") })
            XCTAssertFalse(try fixture.item("Checkout…", in: menu).isEnabled)
            XCTAssertFalse(try fixture.item("Checkout as Worktree…", in: menu).isEnabled)
            XCTAssertFalse(try fixture.item("Delete…", in: menu).isEnabled)
        }
    }

    func testGitLabRemotesGetAMergeRequest() throws {
        try MainActor.assumeIsolated {
            let provider = Self.provider()
            provider.remotes = [GitRemote(name: "origin", fetchURL: "git@gitlab.com:org/repo.git", pushURL: "git@gitlab.com:org/repo.git")]
            let fixture = try MenuFixture(provider: provider)
            defer { fixture.close() }
            let stable = try XCTUnwrap(fixture.store.refs.localBranches.first { $0.name == "stable" })
            try fixture.host(LocalBranchRow(ref: stable, store: fixture.store, isSelected: false, select: {}, checkout: {}))

            XCTAssertTrue(try fixture.menu().items.contains { $0.title == "Create Merge Request on 'origin'" })
        }
    }

    func testChangedFileMenuMatchesForksLayout() throws {
        try MainActor.assumeIsolated {
            let file = FileStatus(path: "proxmox-vm/README.md", index: .unmodified, worktree: .modified)
            let provider = Self.provider()
            provider.status = WorkingCopyStatus(branch: provider.status.branch, entries: [file])
            let fixture = try MenuFixture(provider: provider)
            defer { fixture.close() }
            try fixture.host(ChangeRow(
                file: file, staged: false, store: fixture.store,
                onStage: { _ in }, onUnstage: { _ in }, onDiscard: { _ in },
                moveMenu: AnyView(MoveToMenu(store: fixture.store, paths: [file.path], current: .unstaged))
            ))

            let menu = try fixture.menu()

            XCTAssertEqual(menu.items.map(\.title), [
                "Open", "Open With", "External Diff", "Show in Finder", "",
                "Blame/Timeline…", "History…", "",
                "Stage", "Discard Changes…", "Move To", "",
                "Stage All", "",
                "Ignore", "",
                "Stash 1 File…", "Save as Patch…", "",
                "Copy Path", "Copy Full Path"
            ])
            try fixture.assertShortcut("Open", "o", [.command, .option, .shift], in: menu)
            try fixture.assertShortcut("External Diff", "d", [.command], in: menu)
            try fixture.assertShortcut("Stage", "s", [.command], in: menu)
            try fixture.assertShortcut("Discard Changes…", "d", [.command, .shift], in: menu)
            try fixture.assertShortcut("Copy Path", "c", [.command], in: menu)

            let ignore = try XCTUnwrap(try fixture.item("Ignore", in: menu).submenu).items.map(\.title)
            XCTAssertEqual(Array(ignore.prefix(3)), ["Ignore 'README.md'", "Ignore All '*.md' Files", "Ignore Folder 'proxmox-vm/'"])
            XCTAssertTrue(ignore.contains("Ignore Locally"))
            XCTAssertTrue(ignore.contains("Git keeps tracking files it already tracks"))
        }
    }

    func testANewFileHasNoHistoryOrExternalDiff() throws {
        try MainActor.assumeIsolated {
            let file = FileStatus(path: "new.txt", index: .unmodified, worktree: .untracked)
            let fixture = try MenuFixture(provider: Self.provider())
            defer { fixture.close() }
            try fixture.host(ChangeRow(
                file: file, staged: false, store: fixture.store,
                onStage: { _ in }, onUnstage: { _ in }, onDiscard: { _ in }
            ))

            let menu = try fixture.menu()

            for title in ["External Diff", "Blame/Timeline…", "History…"] {
                XCTAssertFalse(try fixture.item(title, in: menu).isEnabled, "\(title) needs a committed version")
            }
            XCTAssertFalse(try XCTUnwrap(try fixture.item("Ignore", in: menu).submenu).items.contains { $0.title.hasPrefix("Git keeps") })
        }
    }

    private static func provider() -> FakeGitProvider {
        let current = "INFRA-15647-wrong-alerts-tg"
        return FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: current, oid: String(repeating: "a", count: 40)), entries: []),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: current, fullName: "refs/heads/\(current)", oid: String(repeating: "a", count: 40),
                                 kind: .localBranch, isCurrent: true),
                    GitReference(name: "stable", fullName: "refs/heads/stable", oid: String(repeating: "b", count: 40),
                                 kind: .localBranch, upstream: "origin/stable", behind: 3)
                ],
                remoteBranches: [
                    GitReference(name: "origin/stable", fullName: "refs/remotes/origin/stable", oid: String(repeating: "c", count: 40), kind: .remoteBranch)
                ],
                tags: []
            ),
            remotes: [GitRemote(name: "origin", fetchURL: "git@github.com:org/repo.git", pushURL: "git@github.com:org/repo.git")]
        )
    }
}

@MainActor
private final class ActionRecorder {
    var actions: [BranchMenuAction] = []
}

/// Hosts one view in a window, opened on a store backed by a fake provider,
/// and reads the context menu SwiftUI builds for it.
@MainActor
private final class MenuFixture {
    let store: RepositoryStore
    private let window: NSWindow
    private var hostView: NSView?

    init(provider: FakeGitProvider) throws {
        _ = NSApplication.shared
        store = RepositoryStore(git: provider)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-menus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let opened = Flag()
        let store = store
        Task {
            await store.open(root)
            store.stopBackgroundObservation()
            opened.value = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !opened.value, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(opened.value, "The store did not open in time")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }

    func host(_ view: some View) throws {
        let host = NSHostingView(rootView: view.frame(width: 400, height: 40).frame(maxWidth: .infinity, maxHeight: .infinity))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        hostView = host
        settle()
    }

    func menu() throws -> NSMenu {
        let host = try XCTUnwrap(hostView)
        // Over the name: a row's spacer has no content to hit.
        let point = NSPoint(x: host.bounds.minX + 40, y: host.bounds.midY)
        let hit = try XCTUnwrap(host.hitTest(point))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        let menu = try XCTUnwrap(hit.menu(for: event))
        menu.update()
        return menu
    }

    func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(menu.items.first { $0.title == title }, "\(title) is missing from \(menu.items.map(\.title))")
    }

    func assertShortcut(_ title: String, _ key: String, _ modifiers: NSEvent.ModifierFlags, in menu: NSMenu) throws {
        let item = try item(title, in: menu)
        XCTAssertEqual(item.keyEquivalent.lowercased(), key, title)
        XCTAssertEqual(item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]), modifiers, title)
    }

    func choose(_ title: String) throws {
        let menu = try menu()
        let index = menu.indexOfItem(withTitle: title)
        XCTAssertGreaterThanOrEqual(index, 0, "\(title) is missing from \(menu.items.map(\.title))")
        guard index >= 0 else { return }
        menu.performActionForItem(at: index)
        settle()
    }

    func close() {
        window.close()
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        hostView?.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class Flag {
    var value = false
}
