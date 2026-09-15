@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Worktree state")
@MainActor
struct WorktreeStateTests {
    @Test func marksBranchesHeldByOtherWorktreesButNotThisOne() async throws {
        let store = try await openStore()

        let holders = store.branchHolders
        #expect(holders.keys.sorted() == ["feature", "release"])
        #expect(holders["feature"]?.path.lastPathComponent == "repo-feature")
        // The branch checked out here is not "held elsewhere".
        #expect(holders["main"] == nil)
        // A detached worktree holds no branch at all.
        #expect(holders["detached"] == nil)
    }

    @Test func identifiesTheWorktreeThisTabIsOpenOn() async throws {
        let store = try await openStore()
        #expect(store.currentWorktree?.branch == "main")
    }

    @Test func anOrdinaryRepositoryHasNoHeldBranches() async throws {
        let fake = FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "a1"), entries: []),
            refs: .empty
        )
        let root = try temporaryRoot()
        fake.worktrees = [Worktree(path: root, headOID: "a1", branch: "main")]
        let store = RepositoryStore(git: fake)
        await store.open(root)
        store.stopBackgroundObservation()

        #expect(store.branchHolders.isEmpty)
    }

    @Test func watchesTheCommonDirOnlyWhenItSitsOutsideTheWorkingTree() {
        let main = URL(fileURLWithPath: "/repo", isDirectory: true)

        // Ordinary repository: .git is inside the root, so nothing extra is watched.
        #expect(RepositoryWatcher.watchPaths(
            root: main,
            additional: [URL(fileURLWithPath: "/repo/.git", isDirectory: true)]
        ) == ["/repo"])

        // Linked worktree: its refs live in the main repository and need watching.
        #expect(RepositoryWatcher.watchPaths(
            root: URL(fileURLWithPath: "/repo-feature", isDirectory: true),
            additional: [URL(fileURLWithPath: "/repo/.git", isDirectory: true)]
        ) == ["/repo-feature", "/repo/.git"])

        // A path equal to the root, or repeated, is not watched twice.
        #expect(RepositoryWatcher.watchPaths(root: main, additional: [main, main]) == ["/repo"])
    }

    private func openStore() async throws -> RepositoryStore {
        let root = try temporaryRoot()
        let fake = FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "a1"), entries: []),
            refs: .empty
        )
        let siblings = root.deletingLastPathComponent()
        fake.worktrees = [
            Worktree(path: root, headOID: "a1", branch: "main"),
            Worktree(path: siblings.appendingPathComponent("repo-feature"), headOID: "b1", branch: "feature"),
            Worktree(path: siblings.appendingPathComponent("repo-release"), headOID: "c1", branch: "release"),
            Worktree(path: siblings.appendingPathComponent("repo-detached"), headOID: "d1", branch: nil)
        ]
        let store = RepositoryStore(git: fake)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-worktrees-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
