@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Commit plan model")
struct CommitPlanModelTests {
    private let claude = DraftSource.agent(name: "Claude Code", session: "a", title: "Bridge")
    private let codex = DraftSource.agent(name: "Codex", session: "b", title: nil)

    @Test func movingFilesTakesThemFromTheirDraftAndMarksBothEdited() {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a", "b"], source: claude),
            CommitDraft(message: "two", files: ["c"], source: claude)
        ])
        let target = plan.drafts[1].id
        plan.move(["b"], to: .draft(target))
        #expect(plan.drafts.map(\.files) == [["a"], ["c", "b"]])
        #expect(plan.drafts.filter(\.isEdited).count == 2)
    }

    @Test func movingToANewDraftOrOutOfThePlan() throws {
        var plan = CommitPlan(drafts: [CommitDraft(message: "one", files: ["a", "b"], source: claude)])
        let moved = plan.move(["a"], to: .newDraft)
        let created = try #require(moved)
        #expect(plan.draft(id: created)?.files == ["a"])
        #expect(plan.draft(id: created)?.source == .manual)
        plan.move(["b"], to: .unassigned)
        #expect(plan.drafts[0].files.isEmpty)
        #expect(plan.unassigned(changed: ["a", "b", "c"]) == ["b", "c"])
    }

    @Test func replacingASessionKeepsItsPlaceAndEveryoneElse() {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "x", files: ["x"], source: codex),
            CommitDraft(message: "old 1", files: ["a"], source: claude),
            CommitDraft(message: "old 2", files: ["b"], source: claude),
            CommitDraft(message: "mine", files: ["m"], source: .manual)
        ])
        plan.replaceDrafts(from: claude, with: [CommitDraft(message: "new", files: ["a", "b"], source: claude)])
        #expect(plan.drafts.map(\.message) == ["x", "new", "mine"])
        plan.replaceDrafts(from: .ai, with: [CommitDraft(message: "ai", files: ["z"], source: .ai)])
        #expect(plan.drafts.map(\.message) == ["x", "new", "mine", "ai"])
    }

    @Test func groupsFollowRunsOfOneSourceWithUniqueIDs() {
        let plan = CommitPlan(drafts: [
            CommitDraft(message: "1", files: ["a"], source: claude),
            CommitDraft(message: "2", files: ["b"], source: claude),
            CommitDraft(message: "3", files: ["c"], source: codex),
            CommitDraft(message: "4", files: ["d"], source: claude)
        ])
        #expect(plan.groups.map(\.drafts.count) == [2, 1, 1])
        #expect(Set(plan.groups.map(\.id)).count == 3)
        #expect(plan.groups[0].source.groupTitle == "Claude Code - Bridge")
    }

    @Test func groupIdsNeverCollideWithDraftIds() {
        let plan = CommitPlan(drafts: [
            CommitDraft(message: "1", files: ["a"], source: claude),
            CommitDraft(message: "2", files: ["b"], source: codex)
        ])
        // A shared id made the list draw the group header in place of draft 1.
        let draftIDs = Set(plan.drafts.map { AnyHashable($0.id.uuidString) } + plan.drafts.map { AnyHashable($0.id) })
        #expect(plan.groups.allSatisfy { !draftIDs.contains(AnyHashable($0.id)) })
    }

    @Test(arguments: [true, false])
    func mergingKeepsBothMessagesAndAllFiles(withNext: Bool) throws {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "feat: one", files: ["a"], source: claude),
            CommitDraft(message: "fix: two\n\nWhy.", files: ["b", "c"], source: claude),
            CommitDraft(message: "docs: three", files: ["d"], source: claude)
        ])
        let middle = plan.drafts[1].id
        let result = plan.merge(middle, withNext: withNext)
        let survivor = try #require(result)
        #expect(plan.drafts.count == 2)
        let merged = try #require(plan.draft(id: survivor))
        #expect(merged.isEdited)
        if withNext {
            #expect(merged.files == ["b", "c", "d"])
            #expect(merged.message == "fix: two\n\nWhy.\n\ndocs: three")
        } else {
            #expect(merged.files == ["a", "b", "c"])
            #expect(merged.message == "feat: one\n\nfix: two\n\nWhy.")
        }
    }

    @Test func mergingPastTheEndsDoesNothing() {
        var plan = CommitPlan(drafts: [CommitDraft(message: "only", files: ["a"], source: .manual)])
        #expect(plan.merge(plan.drafts[0].id, withNext: true) == nil)
        #expect(plan.merge(plan.drafts[0].id, withNext: false) == nil)
        #expect(plan.drafts.count == 1)
    }

    @Test func revisionReplacesDraftsInPlace() {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "before", files: ["x"], source: codex),
            CommitDraft(message: "big", files: ["a", "b", "c"], source: claude),
            CommitDraft(message: "after", files: ["y"], source: codex)
        ])
        let outcome = plan.applyRevision(
            [(files: ["a", "ghost"], message: "feat: a"), (files: ["b"], message: " test: b \n")],
            replacing: [plan.drafts[1].id]
        )
        #expect(plan.drafts.map(\.message) == ["before", "feat: a", "test: b", "after"])
        #expect(plan.drafts[1].source == claude)
        #expect(plan.drafts[1].isEdited)
        #expect(outcome.dropped == ["ghost"])
        #expect(outcome.leftOut == ["c"])
        #expect(outcome.created.count == 2)
    }

    @Test func revisionAcrossSourcesBecomesAIDrafts() {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a"], source: claude),
            CommitDraft(message: "two", files: ["b"], source: codex)
        ])
        plan.applyRevision([(files: ["a", "b"], message: "feat: together")], replacing: plan.drafts.map(\.id))
        #expect(plan.drafts.count == 1)
        #expect(plan.drafts[0].source == .ai)
    }

    @Test func revisionWithoutUsableCommitsChangesNothing() {
        var plan = CommitPlan(drafts: [CommitDraft(message: "keep", files: ["a"], source: claude)])
        let before = plan
        let outcome = plan.applyRevision([(files: ["elsewhere"], message: "x")], replacing: [plan.drafts[0].id])
        #expect(plan == before)
        #expect(outcome.created.isEmpty)
    }

    @Test func issuesNameWhatBlocksACommit() {
        let plan = CommitPlan()
        let draft = CommitDraft(message: " ", files: ["gone"], source: .manual)
        #expect(plan.issues(of: draft, changed: ["a"]) == [.emptyMessage, .unchanged(["gone"])])
        #expect(plan.issues(of: CommitDraft(message: "x", files: [], source: .manual), changed: []) == [.noFiles])
    }

    @Test func gitPlanFollowsPlanOrderAndTrimsMessages() {
        let plan = CommitPlan(drafts: [
            CommitDraft(message: "first\n", files: ["a"], source: claude),
            CommitDraft(message: "second", files: ["b"], source: codex)
        ])
        let git = plan.fileCommitPlan(for: [plan.drafts[1].id, plan.drafts[0].id])
        #expect(git.commits.map(\.message) == ["first", "second"])
    }

    @Test(arguments: [
        ("subject", "subject", ""),
        ("subject\n\nbody", "subject", "body"),
        ("subject\nline two", "subject", "line two"),
        ("subject\n\n\nbody\n\nmore", "subject", "body\n\nmore")
    ])
    func messagePartsSplitAndJoin(message: String, summary: String, body: String) {
        let parts = CommitMessageParts.split(message)
        #expect(parts.summary == summary)
        #expect(parts.body == body)
        #expect(CommitMessageParts.split(CommitMessageParts.join(summary: summary, body: body)) == parts)
    }
}

@MainActor
@Suite("Agent proposals")
struct AgentProposalTests {
    private let root = URL(fileURLWithPath: "/tmp/avi-proposals", isDirectory: true)

    private func store(_ entries: [FileStatus]) async -> (RepositoryStore, FakeGitProvider) {
        let git = Fixtures.clean()
        git.status = WorkingCopyStatus(branch: git.status.branch, entries: entries)
        git.appliesStaging = true
        let store = RepositoryStore(git: git)
        await store.open(root)
        return (store, git)
    }

    private func modified(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .unmodified, worktree: .modified)
    }

    private func proposal(
        _ commits: [(String, [String])],
        agent: String = "Claude Code",
        session: String = "a",
        replace: Bool = false
    ) -> AgentProposal {
        AgentProposal(agent: agent, session: session, title: nil, commits: commits.map { .init(message: $0.0, files: $0.1) }, replace: replace)
    }

    @Test func singleCommitStagesItsFilesAndFillsTheField() async throws {
        let (store, git) = await store([modified("a.swift"), modified("b.swift")])
        let outcome = try await store.receiveProposal(proposal([("feat: add a\n\nWhy it matters.", ["a.swift"])]), revealPlan: true)
        #expect(outcome.placement == .commitField)
        #expect(git.stagePathsCalls == [["a.swift"]])
        #expect(store.commitSummary == "feat: add a")
        #expect(store.commitBody == "Why it matters.")
        #expect(store.fieldProposal?.stagedByAvi == ["a.swift"])
        #expect(store.commitPlan.isEmpty)
        #expect(store.changesMode == .files)
    }

    @Test func yourOwnMessageIsNeverOverwritten() async throws {
        let (store, _) = await store([modified("a.swift")])
        store.commitSummary = "my words"
        let outcome = try await store.receiveProposal(proposal([("feat: theirs", ["a.swift"])]), revealPlan: true)
        #expect(outcome.placement == .previewCard)
        #expect(store.commitSummary == "my words")
        #expect(store.aiPendingPreview?.proposedBy == "Claude Code")
        #expect(store.aiPendingPreview?.subject == "feat: theirs")
    }

    @Test func messageOnlyProposalKeepsWhatIsStaged() async throws {
        let (store, git) = await store([FileStatus(path: "a.swift", index: .modified, worktree: .unmodified)])
        let outcome = try await store.receiveProposal(proposal([("fix: staged work", [])]), revealPlan: true)
        #expect(outcome.placement == .commitField)
        #expect(git.stagePathsCalls.isEmpty)
        #expect(store.commitSummary == "fix: staged work")
    }

    @Test func severalCommitsGoToThePlanWithoutStaging() async throws {
        let (store, git) = await store([modified("a.swift"), modified("b.swift")])
        let outcome = try await store.receiveProposal(proposal([("one", ["a.swift"]), ("two", ["b.swift"])]), revealPlan: true)
        #expect(outcome.placement == .plan)
        #expect(outcome.commits == 2)
        #expect(git.stagePathsCalls.isEmpty)
        #expect(store.commitPlan.drafts.map(\.files) == [["a.swift"], ["b.swift"]])
        #expect(store.changesMode == .plan)
        #expect(store.hasUnseenProposal)
    }

    @Test func aPlanDoesNotFlipTheViewYouAreLookingAt() async throws {
        let (store, _) = await store([modified("a.swift"), modified("b.swift")])
        store.workspaceSelection = .allCommits
        _ = try await store.receiveProposal(proposal([("one", ["a.swift"]), ("two", ["b.swift"])]), revealPlan: false)
        #expect(store.changesMode == .files)
        #expect(store.workspaceSelection == .allCommits)
        #expect(store.hasUnseenProposal)
    }

    @Test func aProposalWaitsInChangesWhenYouComeBack() async throws {
        let (store, _) = await store([modified("a.swift")])
        store.workspaceSelection = .allCommits
        store.changesMode = .plan
        _ = try await store.receiveProposal(proposal([("feat: a", ["a.swift"])]), revealPlan: true)
        #expect(store.workspaceSelection == .localChanges)
        #expect(store.changesMode == .files)
    }

    @Test func asecondSessionMovesTheFieldProposalIntoThePlan() async throws {
        let (store, git) = await store([modified("a.swift"), modified("b.swift")])
        _ = try await store.receiveProposal(proposal([("from claude", ["a.swift"])]), revealPlan: true)
        let outcome = try await store.receiveProposal(proposal([("from codex", ["b.swift"])], agent: "Codex", session: "b"), revealPlan: true)
        #expect(outcome.placement == .plan)
        #expect(outcome.notes.count == 1)
        #expect(store.commitPlan.drafts.map(\.message) == ["from claude", "from codex"])
        #expect(store.fieldProposal == nil)
        #expect(store.commitSummary.isEmpty)
        // What Avi staged for the first proposal is put back.
        #expect(git.unstagePathsCalls == [["a.swift"]])
    }

    @Test func anotherSessionsFilesAreOffLimits() async throws {
        let (store, _) = await store([modified("a.swift"), modified("b.swift")])
        _ = try await store.receiveProposal(proposal([("one", ["a.swift"]), ("two", ["b.swift"])]), revealPlan: true)
        await #expect(throws: ProposalRejection.fileClaimed(["b.swift": "Claude Code"])) {
            try await store.receiveProposal(proposal([("mine", ["b.swift"])], agent: "Codex", session: "b"), revealPlan: true)
        }
    }

    @Test func resendingReplacesOnlyYourOwnDrafts() async throws {
        let (store, _) = await store([modified("a.swift"), modified("b.swift"), modified("c.swift")])
        _ = try await store.receiveProposal(proposal([("codex", ["c.swift"]), ("codex 2", ["b.swift"])], agent: "Codex", session: "b"), revealPlan: true)
        _ = try await store.receiveProposal(proposal([("claude", ["a.swift"])]), revealPlan: true)
        _ = try await store.receiveProposal(proposal([("claude again", ["a.swift"])]), revealPlan: true)
        #expect(store.commitPlan.drafts.map(\.message) == ["codex", "codex 2", "claude again"])
    }

    @Test func editedDraftsNeedReplaceToBeOverwritten() async throws {
        let (store, _) = await store([modified("a.swift"), modified("b.swift")])
        _ = try await store.receiveProposal(proposal([("one", ["a.swift"]), ("two", ["b.swift"])]), revealPlan: true)
        store.setMessage("my edit", forDraft: store.commitPlan.drafts[0].id)
        await #expect(throws: ProposalRejection.editedByUser) {
            try await store.receiveProposal(proposal([("again", ["a.swift"]), ("two", ["b.swift"])]), revealPlan: true)
        }
        _ = try await store.receiveProposal(proposal([("again", ["a.swift"]), ("two", ["b.swift"])], replace: true), revealPlan: true)
        #expect(store.commitPlan.drafts[0].message == "again")
    }

    @Test func unknownPathsListWhatDidChange() async throws {
        let (store, git) = await store([modified("a.swift")])
        await #expect(throws: ProposalRejection.unknownPaths(["nope.swift"], changed: ["a.swift"])) {
            try await store.receiveProposal(proposal([("x", ["a.swift", "nope.swift"])]), revealPlan: true)
        }
        #expect(git.stagePathsCalls.isEmpty)
    }

    @Test func conflictsAreRefused() async throws {
        let (store, _) = await store([modified("a.swift"), FileStatus(path: "c.swift", index: .updatedButUnmerged, worktree: .updatedButUnmerged)])
        await #expect(throws: ProposalRejection.conflicts(["c.swift"])) {
            try await store.receiveProposal(proposal([("x", ["a.swift"])]), revealPlan: true)
        }
    }

    @Test func somethingElseStagedSendsASingleCommitToThePlan() async throws {
        let (store, git) = await store([modified("a.swift"), FileStatus(path: "mine.swift", index: .modified, worktree: .unmodified)])
        let outcome = try await store.receiveProposal(proposal([("theirs", ["a.swift"])]), revealPlan: true)
        #expect(outcome.placement == .plan)
        #expect(git.stagePathsCalls.isEmpty)
    }

    @Test func withdrawingUnstagesWhatAviStaged() async throws {
        let (store, git) = await store([modified("a.swift")])
        _ = try await store.receiveProposal(proposal([("feat: a", ["a.swift"])]), revealPlan: true)
        await store.discardFieldProposal()
        #expect(store.fieldProposal == nil)
        #expect(store.commitSummary.isEmpty)
        #expect(git.unstagePathsCalls == [["a.swift"]])
    }
}

@MainActor
@Suite("Applying a commit plan")
struct CommitPlanApplyTests {
    private func store(_ paths: [String]) async -> (RepositoryStore, FakeGitProvider) {
        let git = Fixtures.clean()
        git.status = WorkingCopyStatus(branch: git.status.branch, entries: paths.map { FileStatus(path: $0, index: .unmodified, worktree: .modified) })
        let store = RepositoryStore(git: git)
        await store.open(URL(fileURLWithPath: "/tmp/avi-apply", isDirectory: true))
        return (store, git)
    }

    @Test func commitAllCreatesEveryDraftInOrderAndLeavesPlanMode() async {
        let (store, git) = await store(["a", "b"])
        store.commitPlan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a"], source: .manual),
            CommitDraft(message: "two", files: ["b"], source: .manual)
        ])
        store.changesMode = .plan
        await store.commitAllDrafts()
        #expect(git.commitPlanCalls.first?.commits.map(\.message) == ["one", "two"])
        #expect(store.commitPlan.isEmpty)
        #expect(store.changesMode == .files)
        #expect(store.planProgress == nil)
    }

    @Test func aFailureKeepsTheDraftsThatWereNotCommitted() async {
        let (store, git) = await store(["a", "b", "c"])
        git.failCommitPlanAfter = 1
        store.commitPlan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a"], source: .manual),
            CommitDraft(message: "two", files: ["b"], source: .manual),
            CommitDraft(message: "three", files: ["c"], source: .manual)
        ])
        await store.commitAllDrafts()
        #expect(store.commitPlan.drafts.map(\.message) == ["two", "three"])
        #expect(store.errorMessage?.contains("Stopped after 1 of 3") == true)
    }

    @Test func committingOneMovesToTheNextDraft() async {
        let (store, git) = await store(["a", "b", "c"])
        store.commitPlan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a"], source: .manual),
            CommitDraft(message: "two", files: ["b"], source: .manual),
            CommitDraft(message: "three", files: ["c"], source: .manual)
        ])
        let ids = store.commitPlan.drafts.map(\.id)
        store.selectDraft(ids[1])
        await store.commitDraft(ids[1])
        #expect(git.commitPlanCalls.last?.commits.map(\.message) == ["two"])
        #expect(store.commitPlan.drafts.map(\.message) == ["one", "three"])
        #expect(store.selectedDraftID == ids[2])
    }

    @Test func revisionRequestsNameTheirScope() async {
        let (store, _) = await store(["a", "b"])
        store.commitPlan = CommitPlan(drafts: [
            CommitDraft(message: "feat: one", files: ["a"], source: .manual),
            CommitDraft(message: "fix: two", files: ["b"], source: .manual)
        ])
        let ids = store.commitPlan.drafts.map(\.id)
        store.requestRevision(of: [ids[1]], suggestion: "Split it")
        #expect(store.revisionRequest?.title == "Commit 2: fix: two")
        #expect(store.revisionRequest?.suggestion == "Split it")
        store.requestRevision(of: ids)
        #expect(store.revisionRequest?.title == "All 2 commits")
    }

    @Test func thePlanSentToTheAIListsMessagesAndFiles() throws {
        let json = RepositoryStore.planJSON([CommitDraft(message: "feat: a", files: ["Sources/a.swift"], source: .manual)])
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        #expect(decoded?.first?["message"] as? String == "feat: a")
        #expect(decoded?.first?["files"] as? [String] == ["Sources/a.swift"])
        #expect(RepositoryStore.clipped(String(repeating: "x", count: RepositoryStore.aiDiffLimit + 10)).hasSuffix("[diff truncated]\n"))
    }

    @Test func aiSplitKeepsOtherDraftsAndDropsUnknownPaths() async {
        let git = Fixtures.clean()
        git.status = WorkingCopyStatus(branch: git.status.branch, entries: [
            FileStatus(path: "a", index: .modified, worktree: .unmodified),
            FileStatus(path: "b", index: .modified, worktree: .unmodified),
            FileStatus(path: "c", index: .modified, worktree: .unmodified)
        ])
        let store = RepositoryStore(git: git)
        await store.open(URL(fileURLWithPath: "/tmp/avi-ai-split", isDirectory: true))
        store.commitPlan = CommitPlan(drafts: [CommitDraft(message: "agent", files: ["c"], source: .agent(name: "Codex", session: "s", title: nil))])
        store.adoptAISplit([
            AICommitGroup(files: ["a", "ghost"], message: "first"),
            AICommitGroup(files: ["b", "c"], message: "second")
        ])
        #expect(store.commitPlan.drafts.map(\.files) == [["c"], ["a"], ["b"]])
        #expect(store.planNotice?.contains("ghost") == true)
        #expect(store.planNotice?.contains("c") == true)
        #expect(store.changesMode == .plan)
        // The split ran in the background, so the tab says so until you look.
        #expect(store.hasUnseenProposal)
    }
}
