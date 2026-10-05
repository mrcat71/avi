@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Branch and file actions")
@MainActor
struct BranchActionStoreTests {
    // MARK: Merge and rebase

    @Test func aStoppedMergeExplainsItselfAndShowsChanges() async throws {
        let fake = provider()
        fake.integrationOutcome = .stopped("CONFLICT (content): Merge conflict in a.txt")
        let store = try await openStore(fake)

        await store.merge(branch: "feature", mode: .noFastForward)

        #expect(fake.actionCalls == ["merge feature noFastForward"])
        #expect(store.operationNotice == "CONFLICT (content): Merge conflict in a.txt")
        #expect(store.workspaceSelection == .localChanges)
        #expect(store.errorMessage == nil)
    }

    @Test func aSquashLeavesGitsMessageInTheCommitField() async throws {
        let fake = provider()
        let store = try await openStore(fake)
        try write("Squashed commit of the following:\n\ncommit 1234\n    feature work\n", to: ".git/SQUASH_MSG", in: store)

        await store.merge(branch: "feature", mode: .squash)

        #expect(store.commitSummary == "Squashed commit of the following:")
        #expect(store.commitBody.contains("feature work"))
        #expect(store.workspaceSelection == .localChanges)
    }

    @Test func aMergeWaitingInTheRepositoryFillsAnEmptyCommitFieldOnce() async throws {
        let store = try await openStore(provider())
        try write("deadbeef\n", to: ".git/MERGE_HEAD", in: store)
        try write("Merge branch 'feature'\n\n# Conflicts:\n#\ta.txt\n", to: ".git/MERGE_MSG", in: store)

        await store.refresh()

        #expect(store.operationState == .merge)
        #expect(store.commitSummary == "Merge branch 'feature'")
        #expect(store.commitBody.isEmpty)

        // Clearing the field is your decision; a refresh must not undo it.
        store.commitSummary = ""
        await store.refresh()
        #expect(store.commitSummary.isEmpty)

        try FileManager.default.removeItem(at: #require(store.root).appendingPathComponent(".git/MERGE_HEAD"))
        await store.refresh()
        #expect(store.operationState == nil)
        #expect(!store.rebaseInProgress)
    }

    @Test func anAbortedMergeTakesItsUntouchedMessageAlong() async throws {
        let store = try await openStore(provider())
        try write("x\n", to: ".git/MERGE_HEAD", in: store)
        try write("Merge branch 'feature'\n", to: ".git/MERGE_MSG", in: store)
        await store.refresh()
        #expect(store.commitSummary == "Merge branch 'feature'")

        // Aborted in a terminal: Avi only sees MERGE_HEAD disappear.
        try FileManager.default.removeItem(at: #require(store.root).appendingPathComponent(".git/MERGE_HEAD"))
        await store.refresh()

        #expect(store.commitSummary.isEmpty)
    }

    @Test func anEditedMergeMessageSurvivesTheAbort() async throws {
        let store = try await openStore(provider())
        try write("x\n", to: ".git/MERGE_HEAD", in: store)
        try write("Merge branch 'feature'\n", to: ".git/MERGE_MSG", in: store)
        await store.refresh()
        store.commitBody = "Why this merge happened."

        try FileManager.default.removeItem(at: #require(store.root).appendingPathComponent(".git/MERGE_HEAD"))
        await store.refresh()

        #expect(store.commitSummary == "Merge branch 'feature'")
        #expect(store.commitBody == "Why this merge happened.")
    }

    @Test func yourOwnMessageIsNotReplacedByTheMergeMessage() async throws {
        let store = try await openStore(provider())
        store.commitSummary = "mine"
        try write("x\n", to: ".git/MERGE_HEAD", in: store)
        try write("Merge branch 'feature'\n", to: ".git/MERGE_MSG", in: store)

        await store.refresh()

        #expect(store.commitSummary == "mine")
    }

    @Test func aResolvedMergeCanBeCommittedWithNothingStaged() async throws {
        let fake = provider()
        let store = try await openStore(fake)
        try write("x\n", to: ".git/MERGE_HEAD", in: store)
        await store.refresh()
        store.commitSummary = "Merge branch 'feature'"
        #expect(store.canCommit)

        fake.status = WorkingCopyStatus(branch: fake.status.branch, entries: [
            FileStatus(path: "a.txt", index: .updatedButUnmerged, worktree: .updatedButUnmerged, isConflicted: true)
        ])
        await store.refresh()
        #expect(!store.canConcludeMerge)
    }

    @Test func aPullThatStopsOnAConflictShowsTheBannerNotAnError() async throws {
        let fake = provider()
        let store = try await openStore(fake)
        // What `git pull` leaves behind when the merge it starts conflicts.
        try write("x\n", to: ".git/MERGE_HEAD", in: store)
        fake.pullError = .commandFailed(command: "git pull --no-rebase", exitCode: 1, stderr: "CONFLICT (content): Merge conflict in a.txt")

        await store.pull()

        #expect(store.errorMessage == nil)
        #expect(store.operationState == .merge)
        #expect(store.operationNotice?.contains("CONFLICT") == true)
        #expect(store.workspaceSelection == .localChanges)
    }

    @Test func aPullThatFailsOtherwiseIsStillAnError() async throws {
        let fake = provider()
        let store = try await openStore(fake)
        fake.pullError = .commandFailed(command: "git pull", exitCode: 1, stderr: "fatal: unable to access remote")

        await store.pull()

        #expect(store.errorMessage?.contains("unable to access") == true)
        #expect(store.operationNotice == nil)
    }

    @Test func aRebaseRunsWithTheChosenStashSetting() async throws {
        let fake = provider()
        let store = try await openStore(fake)

        await store.rebase(onto: "main", autostash: false)
        await store.rebase(onto: "main", autostash: true)

        #expect(fake.actionCalls == ["rebase main", "rebase main autostash"])
        #expect(store.operationNotice == nil)
    }

    // MARK: Delete

    @Test func deletingAlsoOnTheRemoteRemovesTheRemoteBranchFirst() async throws {
        let fake = provider()
        let store = try await openStore(fake)
        let stable = try #require(store.refs.localBranches.first { $0.name == "stable" })

        #expect(await store.deleteBranch(stable, alsoOnRemote: true, force: false) == .deleted)

        #expect(fake.actionCalls == ["delete remote origin/release/stable", "delete stable"])
    }

    @Test func aRemoteThatRefusesKeepsTheLocalBranch() async throws {
        let fake = provider()
        fake.protectedRemoteBranches = ["release/stable"]
        let store = try await openStore(fake)
        let stable = try #require(store.refs.localBranches.first { $0.name == "stable" })

        #expect(await store.deleteBranch(stable, alsoOnRemote: true, force: false) == .failed)

        #expect(fake.deleteBranchCalls.isEmpty)
        #expect(store.errorMessage?.contains("protected branch") == true)
    }

    @Test func theRemoteDefaultBranchIsNeverDeleted() async throws {
        let fake = provider()
        fake.refs = RepositoryRefs(
            localBranches: fake.refs.localBranches + [branch("old-main", upstream: "origin/main")],
            remoteBranches: fake.refs.remoteBranches,
            tags: []
        )
        let store = try await openStore(fake)
        let oldMain = try #require(store.refs.localBranches.first { $0.name == "old-main" })

        #expect(await store.deleteBranch(oldMain, alsoOnRemote: true, force: false) == .failed)

        #expect(fake.actionCalls.isEmpty)
        #expect(store.errorMessage?.contains("default branch") == true)
    }

    @Test func anUnmergedBranchWaitsForYouToForceIt() async throws {
        let fake = provider()
        fake.unmergedBranches = ["stable"]
        let store = try await openStore(fake)
        let stable = try #require(store.refs.localBranches.first { $0.name == "stable" })

        #expect(await store.deleteBranch(stable, alsoOnRemote: false, force: false) == .needsForce)
        #expect(store.errorMessage == nil)
        #expect(await store.deleteBranch(stable, alsoOnRemote: false, force: true) == .deleted)

        #expect(fake.deleteBranchCalls == ["stable", "stable (forced)"])
        #expect(fake.pushCalls.isEmpty)
    }

    // MARK: Menu state

    @Test func upstreamsSplitOnTheLongestConfiguredRemote() async throws {
        let fake = provider()
        fake.remotes.append(GitRemote(name: "team/eu", fetchURL: "git@example.com:team/eu.git"))
        let store = try await openStore(fake)
        let ref = branch("x", upstream: "team/eu/feature/x")

        #expect(store.upstreamParts(of: ref)?.remote == "team/eu")
        #expect(store.upstreamParts(of: ref)?.branch == "feature/x")
        #expect(store.upstreamParts(of: branch("y", upstream: "elsewhere/y")) == nil)
    }

    @Test func aPullRequestNeedsAPushUntilTheRemoteHasEveryCommit() async throws {
        let store = try await openStore(provider())

        #expect(store.pullRequestNeedsPush(branch("new")))
        #expect(!store.pullRequestNeedsPush(branch("synced", upstream: "origin/synced")))
        #expect(store.pullRequestNeedsPush(branch("ahead", upstream: "origin/ahead", ahead: 2)))
        #expect(store.pullRequestNeedsPush(branch("gone", upstream: "origin/gone", gone: true)))
        #expect(store.branchExistsOnPullRequestRemote(branch("ahead", upstream: "origin/ahead", ahead: 2)))
    }

    @Test func fastForwardIsOfferedOnlyForABranchThatIsJustBehind() async throws {
        let store = try await openStore(provider())

        #expect(store.canFastForward(branch("b", upstream: "origin/b", behind: 1)))
        #expect(!store.canFastForward(branch("b", upstream: "origin/b", ahead: 1, behind: 1)))
        #expect(!store.canFastForward(branch("b", upstream: "origin/b")))
        #expect(!store.canFastForward(branch("b", upstream: "origin/b", behind: 1, gone: true)))
    }

    @Test func trackingOffersTheSameNameOnEveryRemote() async throws {
        let store = try await openStore(provider())
        let stable = try #require(store.refs.localBranches.first { $0.name == "stable" })

        #expect(store.trackingCandidates(for: stable) == ["origin/release/stable", "origin/stable", "upstream/stable"])
    }

    @Test func aWorktreeGoesNextToTheRepository() async throws {
        let store = try await openStore(provider())
        let root = try #require(store.root)

        let path = try #require(store.suggestedWorktreePath(for: "feature/login form"))

        #expect(path.deletingLastPathComponent().path == root.deletingLastPathComponent().path)
        #expect(path.lastPathComponent == "\(root.lastPathComponent)-feature-login-form")
    }

    @Test func checkingOutCanCarryYourChanges() async throws {
        let fake = provider()
        let store = try await openStore(fake)
        let stable = try #require(store.refs.localBranches.first { $0.name == "stable" })

        await store.checkout(stable, carryingLocalChanges: true)

        #expect(fake.actionCalls == ["checkout stable carrying"])
    }

    // MARK: Files

    @Test func stashingARenameTakesBothPathsAndNewFilesNeedUntracked() async throws {
        let fake = provider()
        fake.status = WorkingCopyStatus(branch: fake.status.branch, entries: [
            FileStatus(path: "new.txt", originalPath: "old.txt", index: .renamed, worktree: .unmodified),
            FileStatus(path: "u.txt", index: .unmodified, worktree: .untracked)
        ])
        let store = try await openStore(fake)

        await store.stash(store.entries, message: "wip")

        #expect(fake.actionCalls == ["stash new.txt,old.txt,u.txt wip untracked"])
    }

    @Test func ignoringWritesTheSharedOrTheLocalIgnoreFile() async throws {
        let store = try await openStore(provider())
        let root = try #require(store.root)

        await store.ignore(pattern: "*.log", locally: false)
        await store.ignore(pattern: "/secrets.env", locally: true)

        #expect(try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8) == "*.log\n")
        #expect(try String(contentsOf: root.appendingPathComponent(".git/info/exclude"), encoding: .utf8) == "/secrets.env\n")
        #expect(store.errorMessage == nil)
    }

    // MARK: Helpers

    private func provider() -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(
                branch: BranchInfo(name: "main", oid: String(repeating: "a", count: 40), upstream: "origin/main"),
                entries: []
            ),
            refs: RepositoryRefs(
                localBranches: [
                    branch("main", upstream: "origin/main", isCurrent: true),
                    branch("stable", upstream: "origin/release/stable", behind: 1)
                ],
                remoteBranches: ["origin/main", "origin/stable", "origin/release/stable", "upstream/stable", "origin/other"].map {
                    GitReference(name: $0, fullName: "refs/remotes/\($0)", oid: String(repeating: "b", count: 40), kind: .remoteBranch)
                },
                tags: []
            ),
            remotes: [
                GitRemote(name: "origin", fetchURL: "git@github.com:org/repo.git", pushURL: "git@github.com:org/repo.git"),
                GitRemote(name: "upstream", fetchURL: "git@github.com:upstream/repo.git")
            ]
        )
    }

    private func branch(
        _ name: String,
        upstream: String? = nil,
        isCurrent: Bool = false,
        ahead: Int? = nil,
        behind: Int? = nil,
        gone: Bool = false
    ) -> GitReference {
        GitReference(
            name: name, fullName: "refs/heads/\(name)", oid: String(repeating: "c", count: 40), kind: .localBranch,
            upstream: upstream, isCurrent: isCurrent, ahead: ahead, behind: behind, isUpstreamGone: gone
        )
    }

    private func openStore(_ fake: FakeGitProvider) async throws -> RepositoryStore {
        let store = RepositoryStore(git: fake)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-branch-actions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }

    private func write(_ text: String, to path: String, in store: RepositoryStore) throws {
        let url = try #require(store.root).appendingPathComponent(path)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
