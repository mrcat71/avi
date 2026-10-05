@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Detached HEAD and worktrees")
@MainActor
struct WorktreeStoreTests {
    private let head = String(repeating: "d", count: 40)

    @Test func aDetachedHeadNamesItsCommitAndTheBranchesThere() async throws {
        let fake = detachedProvider()
        let store = try await openStore(fake)

        let detached = try #require(store.detachedHead)
        #expect(detached.oid == head)
        #expect(detached.shortOID == "dddddddd")
        #expect(detached.unreferencedCount == 0)
        #expect(detached.branchesHere == ["here"])
    }

    @Test func leavingUnbranchedCommitsWaitsForYou() async throws {
        let fake = detachedProvider()
        fake.unreferencedCommits = 2
        let store = try await openStore(fake)
        let main = try #require(store.refs.localBranches.first { $0.name == "main" })

        await store.checkout(main)

        let pending = try #require(store.pendingCheckout)
        #expect(pending.leftBehind == 2)
        #expect(!fake.actionCalls.contains("checkout main"))

        await store.checkoutLeavingCommits(pending)

        #expect(fake.actionCalls.contains("checkout main"))
        #expect(store.pendingCheckout == nil)
    }

    @Test func nothingIsAskedWhenEveryCommitIsOnABranch() async throws {
        let fake = detachedProvider()
        let store = try await openStore(fake)
        let main = try #require(store.refs.localBranches.first { $0.name == "main" })

        await store.checkout(main)

        #expect(store.pendingCheckout == nil)
        #expect(fake.actionCalls == ["checkout main"])
    }

    @Test func aWorktreeWithChangesIsRemovedOnlyWhenForced() async throws {
        let fake = detachedProvider()
        let root = try temporaryRoot()
        let agent = Worktree(path: root.deletingLastPathComponent().appendingPathComponent("agent-1"), headOID: head)
        fake.worktrees = [Worktree(path: root, headOID: head), agent]
        fake.dirtyWorktrees = ["agent-1"]
        let store = try await openStore(fake, root: root)

        #expect(await store.removeWorktree(agent, force: false) == .needsForce)
        #expect(store.errorMessage == nil)
        #expect(await store.removeWorktree(agent, force: true) == .removed)

        #expect(fake.actionCalls == ["remove worktree agent-1", "remove worktree agent-1 forced"])
        #expect(store.worktrees.count == 1)
    }

    @Test func worktreesInsideTheRepositoryAreHiddenAndNeverStaged() async throws {
        let fake = detachedProvider()
        let root = try temporaryRoot()
        // What an agent's worktree inside the repository looks like to Git.
        let agent = root.appendingPathComponent(".claude/worktrees/agent", isDirectory: true)
        try FileManager.default.createDirectory(at: agent, withIntermediateDirectories: true)
        try "gitdir: \(root.path)/.git/worktrees/agent\n".write(to: agent.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        // A clone of something else in the folder is not ours and stays listed.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("vendor/tool/.git"), withIntermediateDirectories: true)
        fake.status = WorkingCopyStatus(branch: BranchInfo(name: "main", oid: head), entries: [
            FileStatus(path: ".claude/worktrees/agent/", index: .unmodified, worktree: .untracked),
            FileStatus(path: "vendor/tool/", index: .unmodified, worktree: .untracked),
            FileStatus(path: "README.md", index: .unmodified, worktree: .modified)
        ])
        let store = try await openStore(fake, root: root)

        #expect(store.entries.map(\.path) == ["vendor/tool/", "README.md"])
        #expect(store.hiddenWorktreeCount == 1)

        await store.stageAll()

        // Explicit paths, so `git add --all` never embeds the hidden worktree.
        #expect(fake.stagePathsCalls == [["vendor/tool/", "README.md"]])
    }

    // MARK: Helpers

    private func detachedProvider() -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: nil, oid: head), entries: []),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: "here", fullName: "refs/heads/here", oid: head, kind: .localBranch),
                    GitReference(name: "main", fullName: "refs/heads/main", oid: String(repeating: "a", count: 40), kind: .localBranch)
                ],
                remoteBranches: [],
                tags: []
            )
        )
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-worktrees-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git/worktrees"), withIntermediateDirectories: true)
        return root
    }

    private func openStore(_ fake: FakeGitProvider, root: URL? = nil) async throws -> RepositoryStore {
        let store = RepositoryStore(git: fake)
        try await store.open(root ?? temporaryRoot())
        store.stopBackgroundObservation()
        return store
    }
}
