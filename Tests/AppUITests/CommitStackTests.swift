@testable import AppUI
import Foundation
import GitKit
import Testing

/// Changes is one stack of commits: Commit 1 is the staged files, planned
/// commits follow, and Commit All makes them in that order.
@MainActor
@Suite("Commit stack")
struct CommitStackTests {
    private func store(_ entries: [FileStatus], drafts: [CommitDraft] = []) async -> (RepositoryStore, FakeGitProvider) {
        let git = Fixtures.clean()
        git.status = WorkingCopyStatus(branch: git.status.branch, entries: entries)
        git.appliesStaging = true
        let store = RepositoryStore(git: git)
        await store.open(URL(fileURLWithPath: "/tmp/avi-stack", isDirectory: true))
        store.stopBackgroundObservation()
        store.commitPlan = CommitPlan(drafts: drafts)
        return (store, git)
    }

    private func staged(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .modified, worktree: .unmodified)
    }

    private func unstaged(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .unmodified, worktree: .modified)
    }

    @Test func commitOneIsTheStagedFilesNoPlannedCommitHolds() async {
        let draft = CommitDraft(message: "two", files: ["b", "d"], source: .manual)
        let (store, _) = await store([staged("a"), staged("b"), unstaged("c"), unstaged("d")], drafts: [draft])

        #expect(store.stagedCommitEntries.map(\.path) == ["a"])
        #expect(store.unplannedUnstagedEntries.map(\.path) == ["c"])
        #expect(store.showsStagedCommit)
        #expect(store.stackCount == 2)
        #expect(store.stackNumber(ofDraft: draft.id) == 2)
        #expect(store.stackOrder == [nil, draft.id])
    }

    @Test func anEmptyCommitOneStepsAsideForPlannedCommits() async {
        let draft = CommitDraft(message: "one", files: ["a"], source: .manual)
        let (store, _) = await store([unstaged("a"), unstaged("b")], drafts: [draft])

        #expect(!store.showsStagedCommit)
        #expect(store.stackCount == 1)
        #expect(store.stackNumber(ofDraft: draft.id) == 1)
        // With nothing else to show, the composer edits the planned commit.
        #expect(store.composerDraft?.id == draft.id)

        store.amend = true
        #expect(store.showsStagedCommit)
        #expect(store.stackNumber(ofDraft: draft.id) == 2)
    }

    @Test func withNothingPlannedCommitOneIsTheWholeStack() async {
        let (store, _) = await store([unstaged("a")])
        #expect(store.showsStagedCommit)
        #expect(store.stackCount == 1)
        #expect(store.composerDraft == nil)
    }

    @Test func movingIntoCommitOneStagesAndMovingOutUnstages() async {
        let draft = CommitDraft(message: "two", files: ["c"], source: .manual)
        let (store, git) = await store([staged("a"), unstaged("b"), unstaged("c")], drafts: [draft])

        await store.move(["b"], to: .staged)
        #expect(git.stagePathsCalls == [["b"]])
        #expect(store.stagedCommitEntries.map(\.path) == ["a", "b"])

        await store.move(["a"], to: .unstaged)
        #expect(git.unstagePathsCalls == [["a"]])
        #expect(store.unplannedUnstagedEntries.map(\.path) == ["a"])

        // Out of a planned commit and into Commit 1.
        await store.move(["c"], to: .staged)
        #expect(git.stagePathsCalls.last == ["c"])
        #expect(store.commitPlan.drafts[0].files.isEmpty)
        #expect(store.stagedCommitEntries.map(\.path) == ["b", "c"])
    }

    @Test func plannedCommitsNeverTouchTheIndex() async throws {
        let (store, git) = await store([staged("a"), unstaged("b")])

        await store.move(["a", "b"], to: .newDraft)

        #expect(git.stagePathsCalls.isEmpty)
        #expect(git.unstagePathsCalls.isEmpty)
        let draft = try #require(store.commitPlan.drafts.first)
        #expect(draft.files == ["a", "b"])
        // Commit 1 no longer lists the staged file a planned commit holds.
        #expect(store.stagedCommitEntries.isEmpty)
        #expect(store.selectedDraftID == draft.id)
    }

    @Test func commitAllMakesCommitOneFirstThenThePlannedCommits() async {
        let (store, git) = await store(
            [staged("a"), unstaged("b")],
            drafts: [CommitDraft(message: "two", files: ["b"], source: .manual)]
        )
        store.commitSummary = "one"
        #expect(store.canCommitStack)

        await store.commitStack()

        #expect(git.events == ["commit one", "plan two"])
        #expect(store.commitPlan.isEmpty)
        #expect(store.commitSummary.isEmpty)
    }

    @Test func aStagedFileAPlannedCommitHoldsLeavesTheIndexBeforeCommitOne() async {
        let (store, git) = await store(
            [staged("a"), staged("b")],
            drafts: [CommitDraft(message: "two", files: ["b"], source: .manual)]
        )
        store.commitSummary = "one"

        let committed = await store.commit()

        #expect(committed)
        #expect(git.events == ["unstage b", "commit one"])
        #expect(store.commitPlan.drafts.map(\.files) == [["b"]])
    }

    @Test func aFailedCommitOneStopsCommitAll() async {
        let (store, git) = await store(
            [staged("a"), unstaged("b")],
            drafts: [CommitDraft(message: "two", files: ["b"], source: .manual)]
        )
        git.failCommit = true
        store.commitSummary = "one"

        await store.commitStack()

        #expect(git.commitPlanCalls.isEmpty)
        #expect(store.commitPlan.drafts.map(\.message) == ["two"])
        #expect(store.commitSummary == "one")
        #expect(store.errorMessage?.contains("hook rejected") == true)
    }

    @Test func theBlockerNamesTheFirstCommitThatIsNotReady() async {
        let (store, _) = await store(
            [staged("a"), unstaged("b"), unstaged("c")],
            drafts: [
                CommitDraft(message: "two", files: ["b"], source: .manual),
                CommitDraft(message: "", files: ["c"], source: .manual)
            ]
        )
        #expect(store.stackBlocker == "Commit 1 needs a message")
        #expect(!store.canCommitStack)

        store.commitSummary = "one"
        #expect(store.stackBlocker == "Commit 3 needs a message")

        store.setMessage("three", forDraft: store.commitPlan.drafts[1].id)
        #expect(store.stackBlocker == nil)
        #expect(store.canCommitStack)
    }

    @Test func stageAllLeavesFilesOfPlannedCommitsAlone() async {
        let (store, git) = await store(
            [unstaged("a"), unstaged("b")],
            drafts: [CommitDraft(message: "two", files: ["b"], source: .manual)]
        )

        await store.stageAll()

        #expect(git.stagePathsCalls == [["a"]])
        #expect(store.commitPlan.drafts[0].files == ["b"])
    }

    @Test func deletingAPlannedCommitPutsItsFilesBackWhereTheyWere() async {
        let draft = CommitDraft(message: "two", files: ["a", "b"], source: .manual)
        let (store, git) = await store([staged("a"), unstaged("b")], drafts: [draft])
        #expect(store.stagedCommitEntries.isEmpty)

        store.deleteDraft(draft.id)

        #expect(store.stagedCommitEntries.map(\.path) == ["a"])
        #expect(store.unplannedUnstagedEntries.map(\.path) == ["b"])
        #expect(git.stagePathsCalls.isEmpty && git.unstagePathsCalls.isEmpty)
    }
}
