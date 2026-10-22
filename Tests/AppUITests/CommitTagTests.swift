@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Tags on planned commits")
struct CommitTagPlanTests {
    @Test func mergedCommitsKeepBothTags() throws {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a"], source: .manual, tags: [NewTag(name: "first")]),
            CommitDraft(message: "two", files: ["b"], source: .manual, tags: [NewTag(name: "v1.0", message: "1.0")])
        ])
        let merged = plan.merge(plan.drafts[0].id, withNext: true)
        let survivor = try #require(merged)
        #expect(plan.draft(id: survivor)?.tags.map(\.name) == ["first", "v1.0"])
    }

    /// A revised set of commits ends with all of the changes, so the tag goes there.
    @Test func aRevisionPutsTheTagsOnTheLastNewCommit() {
        var plan = CommitPlan(drafts: [
            CommitDraft(message: "release", files: ["a", "b"], source: .manual, tags: [NewTag(name: "v1.0")])
        ])
        let outcome = plan.applyRevision([(["a"], "first half"), (["b"], "second half")], replacing: [plan.drafts[0].id])
        #expect(outcome.created.count == 2)
        #expect(plan.drafts.map(\.tags.count) == [0, 1])
        #expect(plan.drafts.last?.tags.first?.name == "v1.0")
    }

    @Test func theGitPlanCarriesEachCommitsTags() {
        let plan = CommitPlan(drafts: [
            CommitDraft(message: "one", files: ["a"], source: .manual),
            CommitDraft(message: "two", files: ["b"], source: .manual, tags: [NewTag(name: "v1.0", message: "1.0")])
        ])
        let gitPlan = plan.fileCommitPlan(for: plan.drafts.map(\.id))
        #expect(gitPlan.commits.map(\.tags) == [[], [NewTag(name: "v1.0", message: "1.0")]])
    }

    @Test func changingTagsCountsAsAnEdit() {
        var plan = CommitPlan(drafts: [CommitDraft(message: "one", files: ["a"], source: .agent(name: "Codex", session: "t", title: nil))])
        plan.setTags([NewTag(name: "v1")], for: plan.drafts[0].id)
        #expect(plan.drafts[0].isEdited)
        #expect(plan.plannedTagNames == ["v1"])
    }
}

@MainActor
@Suite("Tag proposals")
struct TagProposalTests {
    private let root = URL(fileURLWithPath: "/tmp/avi-tag-proposals", isDirectory: true)

    private func store(_ paths: [String] = ["a.swift", "b.swift"]) async -> (RepositoryStore, FakeGitProvider) {
        let git = Fixtures.clean()
        git.status = WorkingCopyStatus(branch: git.status.branch, entries: paths.map { FileStatus(path: $0, index: .unmodified, worktree: .modified) })
        git.appliesStaging = true
        let store = RepositoryStore(git: git)
        await store.open(root)
        return (store, git)
    }

    private func proposal(_ commits: [(String, [String], NewTag?)], agent: String = "Claude Code", session: String = "a") -> AgentProposal {
        AgentProposal(
            agent: agent,
            session: session,
            title: nil,
            commits: commits.map { .init(message: $0.0, files: $0.1, tags: $0.2.map { [$0] } ?? []) },
            replace: false
        )
    }

    @Test func aSingleCommitsTagIsCreatedRightAfterTheCommit() async throws {
        let (store, git) = await store()
        let release = NewTag(name: "v1.0", message: "Release 1.0")
        let outcome = try await store.receiveProposal(proposal([("chore(release): 1.0", ["a.swift"], release)]), revealPlan: true)
        #expect(outcome.placement == .commitField)
        #expect(outcome.tags == ["v1.0"])
        #expect(store.commitTags == [release])

        await store.commit()

        #expect(git.events.suffix(2) == ["commit chore(release): 1.0", "tag v1.0"])
        #expect(git.createdTags == ["v1.0@HEAD"])
        #expect(store.commitTags.isEmpty)
        #expect(store.publishableTags == ["v1.0"])
    }

    @Test func plannedCommitsCarryTheirTagsIntoTheRun() async throws {
        let (store, git) = await store()
        let outcome = try await store.receiveProposal(
            proposal([("feat: a", ["a.swift"], nil), ("chore(release): 1.0", ["b.swift"], NewTag(name: "v1.0"))]),
            revealPlan: true
        )
        #expect(outcome.placement == .plan)
        #expect(outcome.tags == ["v1.0"])
        #expect(store.commitPlan.drafts.map { $0.tags.map(\.name) } == [[], ["v1.0"]])

        await store.commitAllDrafts()

        #expect(git.createdTags == ["v1.0@chore(release): 1.0"])
        #expect(store.publishableTags == ["v1.0"])
        #expect(store.errorMessage == nil)
    }

    @Test func aTagGitRefusesIsReportedAfterTheCommits() async {
        let (store, git) = await store()
        git.refusedTags = ["v1.0"]
        store.commitPlan = CommitPlan(drafts: [CommitDraft(message: "one", files: ["a.swift"], source: .manual, tags: [NewTag(name: "v1.0")])])

        await store.commitAllDrafts()

        #expect(store.commitPlan.isEmpty)
        #expect(store.errorMessage?.contains("v1.0") == true)
        #expect(store.publishableTags.isEmpty)
    }

    @Test(arguments: ["-delete", "v 1", "a..b", ""])
    func namesGitRefusesAreRejected(_ name: String) async {
        let (store, _) = await store()
        await #expect(throws: ProposalRejection.self) {
            _ = try await store.receiveProposal(proposal([("one", ["a.swift"], NewTag(name: name))]), revealPlan: true)
        }
        #expect(store.fieldProposal == nil)
    }

    @Test func anExistingTagIsRefused() async {
        let (store, git) = await store()
        git.refs = RepositoryRefs(
            localBranches: git.refs.localBranches,
            remoteBranches: git.refs.remoteBranches,
            tags: [GitReference(name: "v1.0", fullName: "refs/tags/v1.0", oid: "aaa1", kind: .tag)]
        )
        await #expect(throws: ProposalRejection.tagExists(name: "v1.0", owner: nil)) {
            _ = try await store.receiveProposal(proposal([("one", ["a.swift"], NewTag(name: "v1.0"))]), revealPlan: true)
        }
    }

    @Test func anotherSessionsTagIsOffLimits() async throws {
        let (store, _) = await store()
        _ = try await store.receiveProposal(proposal([("one", ["a.swift"], NewTag(name: "v1.0"))]), revealPlan: true)
        await #expect(throws: ProposalRejection.tagExists(name: "v1.0", owner: "Claude Code")) {
            _ = try await store.receiveProposal(proposal([("two", ["b.swift"], NewTag(name: "v1.0"))], agent: "Codex", session: "b"), revealPlan: true)
        }
    }

    /// Another session's commit pushes the proposal out of the commit field;
    /// its tag moves with it into the plan.
    @Test func theFieldProposalKeepsItsTagWhenItMovesIntoThePlan() async throws {
        let (store, _) = await store()
        _ = try await store.receiveProposal(proposal([("one", ["a.swift"], NewTag(name: "v1.0"))]), revealPlan: true)
        _ = try await store.receiveProposal(proposal([("two", ["b.swift"], nil)], agent: "Codex", session: "b"), revealPlan: true)
        #expect(store.commitTags.isEmpty)
        #expect(store.commitPlan.drafts.first { $0.message == "one" }?.tags.map(\.name) == ["v1.0"])
    }

    @Test func aWaitingMessagesTagJoinsOnceYouTakeTheMessage() async throws {
        let (store, _) = await store()
        store.commitSummary = "my words"
        let outcome = try await store.receiveProposal(proposal([("theirs", ["a.swift"], NewTag(name: "v1.0"))]), revealPlan: true)
        #expect(outcome.placement == .previewCard)
        #expect(store.commitTags.isEmpty)

        store.acceptAIPreview(.replace)

        #expect(store.commitTags.map(\.name) == ["v1.0"])
    }

    @Test func withdrawingTheProposalDropsItsTag() async throws {
        let (store, _) = await store()
        _ = try await store.receiveProposal(proposal([("one", ["a.swift"], NewTag(name: "v1.0"))]), revealPlan: true)
        await store.discardFieldProposal()
        #expect(store.commitTags.isEmpty)
    }

    @Test func aTagForAnExistingCommitWaitsForYou() async throws {
        let (store, git) = await store()
        git.resolvableCommits = ["HEAD": "abc1234def"]
        let source = DraftSource.agent(name: "Claude Code", session: "a", title: nil)

        let outcome = try await store.receiveTagProposal(NewTag(name: "v1.0", message: "1.0"), at: "HEAD", source: source)

        #expect(outcome.placement == .tag)
        #expect(store.tagProposals.map(\.commit) == ["abc1234def"])
        #expect(git.createdTags.isEmpty)
        await store.acceptTagProposal(store.tagProposals[0].id)
        #expect(git.createdTags == ["v1.0@abc1234def"])
        #expect(store.tagProposals.isEmpty)
        #expect(store.publishableTags == ["v1.0"])
    }

    @Test func aSessionsNewTagProposalReplacesItsOldOne() async throws {
        let (store, git) = await store()
        git.resolvableCommits = ["HEAD": "abc1234def"]
        let source = DraftSource.agent(name: "Claude Code", session: "a", title: nil)
        _ = try await store.receiveTagProposal(NewTag(name: "v1.0"), at: "HEAD", source: source)
        _ = try await store.receiveTagProposal(NewTag(name: "v1.1"), at: "HEAD", source: source)
        #expect(store.tagProposals.map(\.tag.name) == ["v1.1"])
    }

    @Test func anUnknownCommitIsRefused() async {
        let (store, _) = await store()
        await #expect(throws: ProposalRejection.unknownRevision("nope")) {
            _ = try await store.receiveTagProposal(NewTag(name: "v1.0"), at: "nope", source: .agent(name: "Codex", session: "t", title: nil))
        }
    }

    @Test func aTagThatCouldNotBeCreatedKeepsItsProposal() async throws {
        let (store, git) = await store()
        git.resolvableCommits = ["HEAD": "abc1234def"]
        git.refusedTags = ["v1.0"]
        _ = try await store.receiveTagProposal(NewTag(name: "v1.0"), at: "HEAD", source: .agent(name: "Codex", session: "t", title: nil))
        await store.acceptTagProposal(store.tagProposals[0].id)
        #expect(store.tagProposals.count == 1)
        #expect(store.errorMessage?.contains("already exists") == true)
    }

    @Test func yourTagNamesAreCheckedAgainstEverythingPending() async {
        let (store, _) = await store()
        store.commitPlan = CommitPlan(drafts: [CommitDraft(message: "one", files: ["a.swift"], source: .manual, tags: [NewTag(name: "v1.0")])])
        #expect(store.tagNameProblem("v1.0") != nil)
        #expect(store.tagNameProblem("v1.0", replacing: "v1.0") == nil)
        #expect(store.tagNameProblem("bad name") != nil)
        #expect(store.tagNameProblem("v1.1") == nil)
        store.saveTag(NewTag(name: "v1.1"), replacing: NewTag(name: "v1.0"), for: .draft(store.commitPlan.drafts[0].id))
        #expect(store.commitPlan.drafts[0].tags.map(\.name) == ["v1.1"])
    }
}

@MainActor
@Suite("Pushing tags")
struct TagPushTests {
    private func store() async -> (RepositoryStore, FakeGitProvider) {
        let git = Fixtures.clean()
        let store = RepositoryStore(git: git)
        await store.open(URL(fileURLWithPath: "/tmp/avi-tag-push", isDirectory: true))
        return (store, git)
    }

    /// Lightweight tags made outside Avi stay unticked: one might be a
    /// private label, and a pushed `v*` tag can start a release.
    @Test func approvedAndAnnotatedTagsAreTicked() async throws {
        let (store, git) = await store()
        git.unpushedTags = [
            UnpushedTag(name: "v1.0", isAnnotated: false),
            UnpushedTag(name: "notes", isAnnotated: true),
            UnpushedTag(name: "wip", isAnnotated: false)
        ]
        store.publishableTags = ["v1.0"]

        let choices = try await store.tagsForPush(branch: "main", remote: "origin")

        #expect(choices.filter(\.isPreselected).map(\.name) == ["v1.0", "notes"])
    }

    @Test func pushSendsTheTickedTagsWithTheBranch() async {
        let (store, git) = await store()
        git.unpushedTags = [UnpushedTag(name: "v1.0", isAnnotated: false), UnpushedTag(name: "wip", isAnnotated: false)]
        store.publishableTags = ["v1.0"]

        await store.push()

        #expect(git.pushCalls == ["push origin main v1.0"])
        #expect(store.publishableTags.isEmpty)
    }

    @Test func pushWithoutTagsStaysAPlainPush() async {
        let (store, git) = await store()
        await store.push()
        #expect(git.pushCalls == ["push"])
    }
}
