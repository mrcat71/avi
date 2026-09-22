@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Discard targets")
struct DiscardTargetsTests {
    private func modified(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .unmodified, worktree: .modified)
    }

    /// The row a destructive action started from, the selection at that moment,
    /// and the files the action must actually touch.
    struct Case: Sendable {
        let name: String
        let row: String
        let selection: Set<String>
        let expected: [String]
    }

    @Test(arguments: [
        Case(
            name: "row outside the selection acts on itself only",
            row: "c.txt",
            selection: ["a.txt", "b.txt"],
            expected: ["c.txt"]
        ),
        Case(
            name: "row is the only selected file",
            row: "a.txt",
            selection: ["a.txt"],
            expected: ["a.txt"]
        ),
        Case(
            name: "row inside a multi-selection takes the whole selection in list order",
            row: "c.txt",
            selection: ["c.txt", "a.txt"],
            expected: ["a.txt", "c.txt"]
        ),
        Case(
            name: "folder ids from tree mode never become discard targets",
            row: "a.txt",
            selection: ["a.txt", "Sources", "Sources/Views"],
            expected: ["a.txt"]
        ),
        Case(
            name: "selected paths missing from the pane are ignored",
            row: "b.txt",
            selection: ["b.txt", "staged-only.txt"],
            expected: ["b.txt"]
        ),
        Case(
            name: "empty selection falls back to the row",
            row: "b.txt",
            selection: [],
            expected: ["b.txt"]
        )
    ])
    func resolvesTargets(_ testCase: Case) throws {
        let entries = ["a.txt", "b.txt", "c.txt"].map(modified)
        let row = try #require(entries.first { $0.path == testCase.row })

        let resolved = DiscardTargets.resolve(row: row, selection: testCase.selection, entries: entries)

        #expect(resolved.map(\.path) == testCase.expected, "\(testCase.name)")
    }
}

@Suite("Discard batching")
@MainActor
struct DiscardBatchingTests {
    @Test func discardsEverySelectedFileInOneCall() async throws {
        let fake = FakeGitProvider(status: WorkingCopyStatus(branch: BranchInfo(name: "main"), entries: [
            FileStatus(path: "a.txt", index: .unmodified, worktree: .modified),
            FileStatus(path: "b.txt", index: .unmodified, worktree: .modified),
            FileStatus(path: "c.txt", index: .unmodified, worktree: .untracked)
        ]))
        let store = try await openStore(provider: fake)
        let files = store.unstagedEntries.filter { $0.path != "b.txt" }

        await store.discard(files, advancingFrom: store.unstagedEntries.map(\.path))

        #expect(fake.discardCalls == [["a.txt", "c.txt"]])
        #expect(store.errorMessage == nil)
    }

    @Test func discardingNothingNeverReachesGit() async throws {
        let fake = FakeGitProvider(status: WorkingCopyStatus(branch: BranchInfo(name: "main"), entries: []))
        let store = try await openStore(provider: fake)

        await store.discard([], advancingFrom: [])

        #expect(fake.discardCalls.isEmpty)
    }

    private func openStore(provider: FakeGitProvider) async throws -> RepositoryStore {
        let store = RepositoryStore(git: provider)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-discard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }
}
