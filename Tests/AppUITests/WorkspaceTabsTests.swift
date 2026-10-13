@testable import AppUI
import Foundation
import GitKit
import Testing

/// One tab per repository: its worktrees share the tab.
@MainActor
@Suite("Repository tabs")
struct WorkspaceTabsTests {
    @Test func worktreesOfOneRepositoryShareItsTab() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()

        await session.open(fixture.url("a"))
        await session.open(fixture.url("b"))
        await session.open(fixture.url("a-agent"))

        #expect(session.tabs.map(\.name) == ["a", "b"])
        // The worktree sits with its repository, not after b.
        #expect(session.repositories.compactMap(\.root) == [fixture.url("a"), fixture.url("a-agent"), fixture.url("b")])
        let tab = try #require(session.tabs.first)
        #expect(tab.members.compactMap(\.root) == [fixture.url("a"), fixture.url("a-agent")])
        #expect(tab.active.root == fixture.url("a-agent"))
        #expect(session.selectedTabID == tab.id)
    }

    @Test func aTabReturnsToTheWorktreeYouLeftItOn() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("a"))
        await session.open(fixture.url("a-agent"))
        await session.open(fixture.url("b"))

        try session.selectTab(#require(session.tabs.first).id)

        #expect(session.selectedRepository?.root == fixture.url("a-agent"))
    }

    @Test func closingTheShownWorktreeShowsAnotherOfTheSameRepository() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("a"))
        await session.open(fixture.url("b"))
        await session.open(fixture.url("a-agent"))

        // Such as an agent removing its worktree.
        try session.close(#require(session.selectedRepository).id)

        #expect(session.selectedRepository?.root == fixture.url("a"))
        #expect(session.tabs.count == 2)
    }

    @Test func closingATabClosesEveryWorktreeInIt() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("a"))
        await session.open(fixture.url("a-agent"))
        await session.open(fixture.url("b"))
        try session.selectTab(#require(session.tabs.first).id)

        try session.closeTab(#require(session.tabs.first).id)

        #expect(session.repositories.compactMap(\.root) == [fixture.url("b")])
        #expect(session.selectedRepository?.root == fixture.url("b"))
    }

    @Test func movingATabMovesItsWorktreesWithIt() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("a"))
        await session.open(fixture.url("a-agent"))
        await session.open(fixture.url("b"))
        let tabs = session.tabs

        session.moveTab(tabs[1].id, toPlaceOf: tabs[0].id)

        #expect(session.repositories.compactMap(\.root) == [fixture.url("b"), fixture.url("a"), fixture.url("a-agent")])
        #expect(session.tabs.map(\.name) == ["b", "a"])
    }

    /// The workspace saved before tabs were grouped, with the worktree last,
    /// comes back with it in its repository's tab.
    @Test func aSavedWorkspaceComesBackGrouped() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let paths = ["a", "b", "a-agent"].map { fixture.url($0).path }
        let saved = try JSONSerialization.data(withJSONObject: ["paths": paths, "selectedPath": fixture.url("a-agent").path])
        fixture.defaults.set(saved, forKey: "avi.workspaceSession")

        let session = fixture.session()
        await session.restore()

        #expect(session.tabs.map(\.name) == ["a", "b"])
        #expect(session.tabs.first?.members.count == 2)
        #expect(session.selectedRepository?.root == fixture.url("a-agent"))
    }

    @MainActor
    private final class Fixture {
        let git = Fixtures.clean()
        let defaults: UserDefaults
        let root: URL
        private let suite = "avi-tab-tests-\(UUID().uuidString)"
        private var sessions: [WorkspaceSession] = []

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).resolvingSymlinksInPath()
            for name in ["a", "a-agent", "b"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            // a-agent is a linked worktree of a: it shares a's common dir.
            git.commonDirs[url("a-agent").path] = url("a").appendingPathComponent(".git")
        }

        func url(_ name: String) -> URL {
            root.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        }

        func session() -> WorkspaceSession {
            let session = WorkspaceSession(git: git, defaults: defaults)
            sessions.append(session)
            return session
        }

        func close() {
            for session in sessions {
                for repository in session.repositories {
                    repository.stopBackgroundObservation()
                }
            }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
