@testable import AppUI
import Foundation
import GitKit
import Testing

/// A tab on a folder deleted underneath Avi, such as a worktree an agent or
/// another app removed, closes instead of alerting on every refresh.
@MainActor
@Suite("Deleted folders")
struct FolderRemovalTests {
    @Test func aTabWhoseWorktreeIsDeletedClosesWithoutAnAlert() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("main"))
        await session.open(fixture.url("agent"))
        let agent = try #require(session.repositories.last)
        #expect(session.selectedRepository?.id == agent.id)

        try FileManager.default.removeItem(at: fixture.url("agent"))
        fixture.git.statusError = GitError.missingFolder(fixture.url("agent").path)
        await agent.refresh()

        #expect(agent.isFolderRemoved)
        #expect(agent.errorMessage == nil)
        #expect(session.repositories.compactMap(\.root) == [fixture.url("main")])
        #expect(session.selectedRepository?.root == fixture.url("main"))
        #expect(session.errorMessage == nil)
    }

    @Test func aWorktreeLosingItsGitFileFirstClosesToo() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("agent"))
        let agent = try #require(session.repositories.first)

        // Removing a worktree can delete its .git file before the rest.
        try FileManager.default.removeItem(at: fixture.url("agent").appendingPathComponent(".git"))
        fixture.git.statusError = GitError.commandFailed(
            command: "git status",
            exitCode: 128,
            stderr: "fatal: not a git repository (or any of the parent directories): .git"
        )
        await agent.refresh()

        #expect(agent.errorMessage == nil)
        #expect(session.repositories.isEmpty)
    }

    @Test(arguments: [
        GitError.commandFailed(command: "git status", exitCode: 128, stderr: "fatal: not a git repository: /elsewhere/.git/worktrees/x"),
        GitError.missingFolder("/elsewhere/agent-2"),
        GitError.commandFailed(command: "git status", exitCode: 128, stderr: "fatal: bad object HEAD")
    ])
    func failuresInARepositoryThatIsStillThereAreShown(_ error: GitError) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let session = fixture.session()
        await session.open(fixture.url("main"))
        let main = try #require(session.repositories.first)

        fixture.git.statusError = error
        await main.refresh()

        #expect(main.errorMessage == error.localizedDescription)
        #expect(!main.isFolderRemoved)
        #expect(session.repositories.count == 1)
    }

    /// Folders with an empty `.git` inside, which is where the fake Git
    /// provider says each one keeps its Git data.
    @MainActor
    private final class Fixture {
        let git = Fixtures.clean()
        let root: URL
        private let suite = "avi-folder-removal-tests-\(UUID().uuidString)"
        private let defaults: UserDefaults
        private var sessions: [WorkspaceSession] = []

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).resolvingSymlinksInPath()
            for name in ["main", "agent"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent("\(name)/.git"), withIntermediateDirectories: true)
            }
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
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Unable to clean up the folder removal fixture: \(error)")
            }
        }
    }
}
