@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Tag deletion")
@MainActor
struct TagDeletionTests {
    @Test func deletingATagLeavesTheRemoteCopyAlone() async throws {
        let fake = provider()
        let store = try await openStore(provider: fake)

        await store.deleteTag(named: "v0.2.2")

        #expect(fake.deleteTagCalls == ["v0.2.2"])
        #expect(store.refs.tags.map(\.name) == ["v0.2.1"])
        // Deleting locally must never reach for the remote.
        #expect(fake.deleteRemoteTagCalls.isEmpty)
        #expect(fake.pushTagCalls.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test func deletingATagOnTheRemoteTooRemovesBothCopies() async throws {
        let fake = provider()
        let store = try await openStore(provider: fake)

        await store.deleteTag(named: "v0.2.2", remote: "origin")

        #expect(fake.deleteRemoteTagCalls.map(\.name) == ["v0.2.2"])
        #expect(fake.deleteRemoteTagCalls.map(\.remote) == ["origin"])
        #expect(fake.deleteTagCalls == ["v0.2.2"])
        #expect(store.refs.tags.map(\.name) == ["v0.2.1"])
        #expect(store.errorMessage == nil)
    }

    @Test func aRefusedRemoteDeleteKeepsTheLocalTagToRetryFrom() async throws {
        let fake = provider()
        fake.protectedRemoteTags = ["v0.2.2"]
        let store = try await openStore(provider: fake)

        await store.deleteTag(named: "v0.2.2", remote: "origin")

        #expect(fake.deleteRemoteTagCalls.map(\.name) == ["v0.2.2"])
        #expect(fake.deleteTagCalls.isEmpty)
        #expect(store.refs.tags.map(\.name) == ["v0.2.2", "v0.2.1"])
        let message = try #require(store.errorMessage)
        #expect(message.contains("protected tag"))
    }

    private func provider() -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "a1"), entries: []),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: "main", fullName: "refs/heads/main", oid: "a1", kind: .localBranch, isCurrent: true)
                ],
                remoteBranches: [],
                tags: [
                    GitReference(name: "v0.2.2", fullName: "refs/tags/v0.2.2", oid: "t1", kind: .tag),
                    GitReference(name: "v0.2.1", fullName: "refs/tags/v0.2.1", oid: "t0", kind: .tag)
                ]
            ),
            remotes: [GitRemote(name: "origin")]
        )
    }

    private func openStore(provider: FakeGitProvider) async throws -> RepositoryStore {
        let store = RepositoryStore(git: provider)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-tag-deletion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }
}
