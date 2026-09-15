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

    @Test func reportsRefusedBranchesWithoutSkippingTheRest() async throws {
        let fake = provider()
        fake.unmergedBranches = ["merged"]
        let store = try await openStore(provider: fake)

        await store.deleteGoneBranches()

        // The refusal must not stop the loop: both branches are still attempted.
        #expect(fake.deleteBranchCalls == ["merged", "squashed"])
        #expect(store.refs.localBranches.map(\.name).contains("merged"))
        let message = try #require(store.errorMessage)
        #expect(message.contains("merged"))
        #expect(message.contains("not fully merged"))
        #expect(!message.contains("squashed"))
    }

    @Test func deletingATagLeavesTheRemoteCopyAlone() async throws {
        let fake = FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "a1"), entries: []),
            refs: RepositoryRefs(
                localBranches: [branch("main", isCurrent: true)],
                remoteBranches: [],
                tags: [
                    GitReference(name: "v0.2.2", fullName: "refs/tags/v0.2.2", oid: "t1", kind: .tag),
                    GitReference(name: "v0.2.1", fullName: "refs/tags/v0.2.1", oid: "t0", kind: .tag)
                ]
            )
        )
        let store = try await openStore(provider: fake)

        await store.deleteTag(named: "v0.2.2")

        #expect(fake.deleteTagCalls == ["v0.2.2"])
        #expect(store.refs.tags.map(\.name) == ["v0.2.1"])
        // Deleting locally must never reach for the remote.
        #expect(fake.pushTagCalls.isEmpty)
        #expect(store.errorMessage == nil)
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
