@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Diverged pulls and conflicts")
@MainActor
struct ConflictStoreTests {
    // MARK: Diverged pull

    /// The ansible repository's case: pull.ff=only, one commit on each side.
    @Test func aDivergedPullAsksInsteadOfFailing() async throws {
        let fake = provider(ahead: 1, behind: 1)
        let store = try await openStore(fake)

        await store.pull()

        let diverged = try #require(store.divergedPull)
        #expect(diverged.branch == "main")
        #expect(diverged.upstream == "origin/main")
        #expect(diverged.ahead == 1)
        #expect(diverged.behind == 1)
        #expect(fake.pullCalls == 0)
        #expect(fake.fetchCalls == [nil])
        #expect(store.errorMessage == nil)
    }

    struct Pull: Sendable, CustomTestStringConvertible {
        let ahead: Int
        let behind: Int
        let configured: Bool

        var testDescription: String {
            "ahead \(ahead), behind \(behind)\(configured ? ", pull.rebase set" : "")"
        }
    }

    @Test(arguments: [
        Pull(ahead: 0, behind: 2, configured: false),
        Pull(ahead: 1, behind: 1, configured: true),
        Pull(ahead: 3, behind: 0, configured: false)
    ])
    func aPullThatNeedsNoChoicePullsRightAway(_ item: Pull) async throws {
        let fake = provider(ahead: item.ahead, behind: item.behind)
        fake.pullReconcileConfigured = item.configured
        let store = try await openStore(fake)

        await store.pull()

        #expect(store.divergedPull == nil)
        #expect(fake.pullCalls == 1)
    }

    @Test func choosingRebaseRunsItAndAConflictOpensChanges() async throws {
        let fake = provider(ahead: 1, behind: 1)
        let store = try await openStore(fake)
        await store.pull()
        fake.integrationOutcome = .stopped("CONFLICT (content): Merge conflict in a.txt")

        await store.reconcileDivergedPull(.rebase)

        #expect(store.divergedPull == nil)
        #expect(fake.actionCalls == ["reconcile rebase"])
        #expect(store.operationNotice == "CONFLICT (content): Merge conflict in a.txt")
        #expect(store.workspaceSelection == .localChanges)
    }

    // MARK: Resolving

    private let conflicted = """
    top
    <<<<<<< HEAD
    mine
    =======
    theirs
    >>>>>>> feature
    middle
    <<<<<<< HEAD
    second mine
    =======
    second theirs
    >>>>>>> feature

    """

    @Test func resolvingOneConflictRewritesOnlyThatOne() async throws {
        let (store, file) = try await conflictedStore()

        let document = try #require(textConflict(store))
        await store.resolveConflict(at: 0, expected: document.conflicts[0], with: .incoming, in: file)

        let written = try String(contentsOf: #require(store.root).appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(written == "top\ntheirs\nmiddle\n<<<<<<< HEAD\nsecond mine\n=======\nsecond theirs\n>>>>>>> feature\n")
        #expect(try #require(textConflict(store)).conflicts.count == 1)
    }

    @Test func aFileEditedSinceYouLookedIsNotOverwritten() async throws {
        let (store, file) = try await conflictedStore()
        let seen = try #require(textConflict(store)).conflicts[0]
        let url = try #require(store.root).appendingPathComponent("a.txt")
        let edited = conflicted.replacingOccurrences(of: "theirs\n>>>>>>> feature\nmiddle", with: "theirs, edited\n>>>>>>> feature\nmiddle")
        try edited.write(to: url, atomically: true, encoding: .utf8)

        await store.resolveConflict(at: 0, expected: seen, with: .current, in: file)

        #expect(try String(contentsOf: url, encoding: .utf8) == edited)
        #expect(try #require(textConflict(store)).conflicts[0].incoming == ["theirs, edited"])
    }

    @Test func markingAFileWithMarkersLeftAsksFirst() async throws {
        let (store, file) = try await conflictedStore()
        let fake = try #require(store.git as? FakeGitProvider)

        await store.markResolved([file])

        #expect(store.pendingResolve?.withMarkers == ["a.txt"])
        #expect(fake.actionCalls.isEmpty)

        await store.markResolved([file], force: true)
        #expect(fake.actionCalls == ["resolved a.txt"])
    }

    @Test func markingAResolvedFileStagesItRightAway() async throws {
        let (store, file) = try await conflictedStore()
        let fake = try #require(store.git as? FakeGitProvider)
        try "top\nmine\nmiddle\nsecond theirs\n".write(to: #require(store.root).appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        await store.markResolved([file])

        #expect(store.pendingResolve == nil)
        #expect(fake.actionCalls == ["resolved a.txt"])
    }

    /// Stage All must not mark a conflict resolved with its markers still in.
    @Test func stageAllLeavesConflictedFilesOut() async throws {
        let fake = provider(ahead: 0, behind: 0)
        fake.status = WorkingCopyStatus(branch: fake.status.branch, entries: [
            FileStatus(path: "a.txt", index: .updatedButUnmerged, worktree: .updatedButUnmerged, isConflicted: true),
            FileStatus(path: "b.txt", index: .unmodified, worktree: .modified)
        ])
        let store = try await openStore(fake)

        await store.stageAll()

        #expect(fake.stagePathsCalls == [["b.txt"]])
    }

    /// A conflict where one side added the file is still nothing staged.
    @Test func aConflictedFileIsNeverStaged() {
        let bothAdded = FileStatus(path: "a.txt", index: .added, worktree: .added, isConflicted: true)
        let deletedByUs = FileStatus(path: "b.txt", index: .deleted, worktree: .updatedButUnmerged, isConflicted: true)
        #expect(!bothAdded.isStaged)
        #expect(!deletedByUs.isStaged)
        #expect(bothAdded.hasUnstagedChanges)
        #expect(deletedByUs.hasUnstagedChanges)
    }

    // MARK: Helpers

    private func textConflict(_ store: RepositoryStore) -> ConflictDocument? {
        guard case let .text(document)? = store.selectedConflict?.content else { return nil }
        return document
    }

    private func conflictedStore() async throws -> (RepositoryStore, FileStatus) {
        let fake = provider(ahead: 0, behind: 0)
        let file = FileStatus(path: "a.txt", index: .updatedButUnmerged, worktree: .updatedButUnmerged, isConflicted: true)
        fake.status = WorkingCopyStatus(branch: fake.status.branch, entries: [file])
        let store = try await openStore(fake)
        try conflicted.write(to: #require(store.root).appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        await store.select(file)
        return (store, file)
    }

    private func provider(ahead: Int, behind: Int) -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: String(repeating: "a", count: 40), upstream: "origin/main", ahead: ahead, behind: behind),
                entries: []
            ),
            remotes: [GitRemote(name: "origin", fetchURL: "https://example.com/a.git", pushURL: "https://example.com/a.git")]
        )
    }

    private func openStore(_ fake: FakeGitProvider) async throws -> RepositoryStore {
        let store = RepositoryStore(git: fake)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-conflicts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }
}

@Suite("Merge tool choice")
@MainActor
struct MergeToolCatalogTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let mergeTool: String
        var command = ""
        var path = ""
        /// What a lookup on this Mac finds, for any preset.
        var found: String?
        let expected: MergeToolLaunch?
        var fails = false

        var testDescription: String {
            mergeTool.isEmpty ? "Git's merge.tool" : mergeTool
        }
    }

    @Test(arguments: [
        Case(mergeTool: "", expected: nil),
        Case(mergeTool: "filemerge", found: "/usr/bin/opendiff", expected: MergeToolLaunch(name: "opendiff", path: "/usr/bin/opendiff")),
        Case(mergeTool: "vscode", path: "/opt/code", expected: MergeToolLaunch(name: "vscode", path: "/opt/code")),
        Case(
            mergeTool: "goland", found: "/Applications/GoLand.app/Contents/MacOS/goland",
            expected: MergeToolLaunch(
                name: "avi-goland",
                command: #"'/Applications/GoLand.app/Contents/MacOS/goland' merge "$LOCAL" "$REMOTE" "$BASE" "$PWD/$MERGED""#
            )
        ),
        Case(mergeTool: "custom", command: #"my-tool "$MERGED""#, expected: MergeToolLaunch(name: "avi-custom", command: #"my-tool "$MERGED""#)),
        Case(mergeTool: "custom", expected: nil, fails: true),
        Case(mergeTool: "goland", expected: nil, fails: true),
        Case(mergeTool: "no-such-tool", expected: nil, fails: true)
    ])
    func launchFollowsTheChosenTool(_ item: Case) throws {
        let config = ExternalToolsConfig(mergeToolPath: item.path, mergeTool: item.mergeTool, mergeToolCommand: item.command)
        if item.fails {
            #expect(throws: MergeToolCatalog.Unavailable.self) {
                _ = try MergeToolCatalog.launch(for: config) { _ in item.found }
            }
        } else {
            #expect(try MergeToolCatalog.launch(for: config) { _ in item.found } == item.expected)
        }
    }

    @Test func everyPresetHasAUniqueIDAndAWayToFindIt() {
        let ids = MergeToolCatalog.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(MergeToolCatalog.customID))
        #expect(MergeToolCatalog.presets.allSatisfy { !$0.bundles.isEmpty || !$0.paths.isEmpty })
    }
}
