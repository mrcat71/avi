@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Gone branch cleanup")
@MainActor
struct GoneBranchCleanupTests {
    @Test func listsOnlyGoneBranchesAndNeverTheCurrentOne() async throws {
        let store = try await openStore(provider: provider())
        #expect(store.goneBranches.map(\.name) == ["merged", "squashed"])
    }

    @Test func deletesEveryGoneBranchAndLeavesTheRestAlone() async throws {
        let fake = provider()
        let store = try await openStore(provider: fake)

        await store.deleteGoneBranches()

        #expect(fake.deleteBranchCalls == ["merged", "squashed"])
        #expect(store.refs.localBranches.map(\.name) == ["main", "tracked", "local-only", "gone-current"])
        #expect(store.errorMessage == nil)
    }

    @Test func forcesOnlyTheBranchesGitRefusedAndAsksNothingFurther() async throws {
        let fake = provider()
        fake.unmergedBranches = ["squashed"]
        let store = try await openStore(provider: fake)

        await store.deleteGoneBranches()

        // "merged" went through the safe delete; only the refused one was forced.
        #expect(fake.deleteBranchCalls == ["merged", "squashed", "squashed (forced)"])
        #expect(store.refs.localBranches.map(\.name) == ["main", "tracked", "local-only", "gone-current"])
        #expect(store.errorMessage == nil)
    }

    @Test func aGoneBranchIsNeverDeletedOnTheRemote() async throws {
        let fake = provider()
        fake.unmergedBranches = ["merged", "squashed"]
        let store = try await openStore(provider: fake)

        await store.deleteGoneBranches()

        #expect(store.refs.localBranches.map(\.name) == ["main", "tracked", "local-only", "gone-current"])
        // Deleting locally must not reach for the remote in any form.
        #expect(fake.pushCalls.isEmpty)
        #expect(fake.pushTagCalls.isEmpty)
        #expect(fake.deleteRemoteTagCalls.isEmpty)
    }

    @Test func realFailuresStayErrorsAndNameOneReasonPerBranch() async throws {
        let fake = provider()
        fake.brokenBranches = ["squashed"]
        let store = try await openStore(provider: fake)

        await store.deleteGoneBranches()

        // A failure forcing cannot fix is never retried with force.
        #expect(!fake.deleteBranchCalls.contains("squashed (forced)"))
        let message = try #require(store.errorMessage)
        #expect(message.contains("squashed"))
        #expect(message.contains("worktree is dirty"))
        // A header plus one line per failed branch, not Git's repeated hint block.
        #expect(message.split(separator: "\n").count == 2)
        #expect(!message.contains("hint:"))
    }

    @Test func doesNothingWhenNoUpstreamIsGone() async throws {
        let fake = FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "a1"), entries: []),
            refs: RepositoryRefs(
                localBranches: [branch("main", isCurrent: true)],
                remoteBranches: [],
                tags: []
            )
        )
        let store = try await openStore(provider: fake)

        await store.deleteGoneBranches()

        #expect(fake.deleteBranchCalls.isEmpty)
        #expect(store.errorMessage == nil)
    }

    private func provider() -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "gone-current", oid: "a1"), entries: []),
            refs: RepositoryRefs(
                localBranches: [
                    branch("main"),
                    branch("tracked", upstream: "origin/tracked"),
                    branch("merged", upstream: "origin/merged", isUpstreamGone: true),
                    branch("local-only"),
                    branch("squashed", upstream: "origin/squashed", isUpstreamGone: true),
                    // A checked-out branch is skipped: git refuses to delete it.
                    branch("gone-current", upstream: "origin/gone-current", isCurrent: true, isUpstreamGone: true)
                ],
                remoteBranches: [],
                tags: []
            )
        )
    }

    private func branch(
        _ name: String,
        upstream: String? = nil,
        isCurrent: Bool = false,
        isUpstreamGone: Bool = false
    ) -> GitReference {
        GitReference(
            name: name,
            fullName: "refs/heads/\(name)",
            oid: String(repeating: "a", count: 40),
            kind: .localBranch,
            upstream: upstream,
            isCurrent: isCurrent,
            isUpstreamGone: isUpstreamGone
        )
    }

    private func openStore(provider: FakeGitProvider) async throws -> RepositoryStore {
        let store = RepositoryStore(git: provider)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-gone-branches-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }
}
