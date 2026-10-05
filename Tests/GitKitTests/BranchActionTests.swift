import Foundation
@testable import GitKit
import Testing

/// The branch menu's actions against real repositories under /tmp.
struct BranchActionTests {
    // MARK: Fast-forward

    @Test func fastForwardMovesABranchThatIsNotCheckedOut() async throws {
        try await withBranches { repo in
            try await repo.git("branch", "--set-upstream-to=main", "feature")
            let tip = try await oid(repo, "main")

            try await provider(repo).fastForward(branch: "feature", in: repo.url)

            #expect(try await oid(repo, "feature") == tip)
            #expect(try await currentBranch(repo) == "main")
            // A local fast-forward is not a fetch: the "fetched" time must not move.
            #expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/FETCH_HEAD").path))
        }
    }

    @Test func fastForwardChecksOutTheNewCommitsOnTheCurrentBranch() async throws {
        try await withBranches { repo in
            try await repo.git("switch", "-q", "feature")
            try await repo.git("branch", "--set-upstream-to=main")

            try await provider(repo).fastForward(branch: "feature", in: repo.url)

            #expect(try await oid(repo, "HEAD") == oid(repo, "main"))
            #expect(try repo.read("main.txt") == "main\n")
        }
    }

    @Test func fastForwardRefusesADivergedBranch() async throws {
        try await withBranches { repo in
            try await repo.git("switch", "-q", "feature")
            try await commit(repo, "feature.txt", "feature\n", "feature work")
            try await repo.git("switch", "-q", "main")
            try await repo.git("branch", "--set-upstream-to=main", "feature")
            let before = try await oid(repo, "feature")

            await #expect(throws: GitError.self) {
                try await provider(repo).fastForward(branch: "feature", in: repo.url)
            }
            #expect(try await oid(repo, "feature") == before)
        }
    }

    // MARK: Merge

    @Test func mergeRecordsAMergeCommitNamedAfterTheBranch() async throws {
        try await withDivergedBranches { repo in
            let outcome = try await provider(repo).merge(branch: "feature", mode: .noFastForward, in: repo.url)

            #expect(outcome == .completed)
            let parents = try await repo.git("log", "-1", "--format=%P").stdoutString.split(separator: " ")
            #expect(parents.count == 2)
            #expect(try await repo.git("log", "-1", "--format=%s").stdoutString.hasPrefix("Merge branch 'feature'"))
        }
    }

    @Test func mergeFastForwardsWhenItCan() async throws {
        try await withBranches { repo in
            try await repo.git("switch", "-q", "feature")

            let outcome = try await provider(repo).merge(branch: "main", mode: .fastForwardIfPossible, in: repo.url)

            #expect(outcome == .completed)
            #expect(try await oid(repo, "HEAD") == oid(repo, "main"))
        }
    }

    @Test func mergeNeverTakesATagWithTheBranchName() async throws {
        try await withBranches { repo in
            try await repo.git("switch", "-q", "feature")
            // "main" is also a tag on the older commit; the branch must win.
            try await repo.git("tag", "main", "feature")

            _ = try await provider(repo).merge(branch: "main", mode: .fastForwardIfPossible, in: repo.url)

            #expect(try await oid(repo, "HEAD") == oid(repo, "refs/heads/main"))
        }
    }

    @Test func fastForwardOnlyRefusesDivergedBranchesAndLeavesNothingBehind() async throws {
        try await withDivergedBranches { repo in
            let before = try await oid(repo, "HEAD")

            await #expect(throws: GitError.self) {
                try await provider(repo).merge(branch: "feature", mode: .fastForwardOnly, in: repo.url)
            }
            #expect(try await oid(repo, "HEAD") == before)
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
        }
    }

    @Test func conflictingMergeStopsAndAbortRestoresTheBranch() async throws {
        try await withConflictingBranches { repo in
            let before = try await oid(repo, "HEAD")

            let outcome = try await provider(repo).merge(branch: "feature", mode: .fastForwardIfPossible, in: repo.url)

            guard case .stopped(let message) = outcome else {
                Issue.record("Expected the merge to stop on the conflict, got \(outcome)")
                return
            }
            #expect(message.contains("CONFLICT"))
            #expect(try await provider(repo).operationState(in: repo.url) == .merge)

            try await provider(repo).abortOperation(.merge, in: repo.url)

            #expect(try await provider(repo).operationState(in: repo.url) == nil)
            #expect(try await oid(repo, "HEAD") == before)
            #expect(try repo.read("shared.txt") == "main side\n")
        }
    }

    @Test func squashMergeStagesTheChangesWithoutCommitting() async throws {
        try await withDivergedBranches { repo in
            let before = try await oid(repo, "HEAD")

            let outcome = try await provider(repo).merge(branch: "feature", mode: .squash, in: repo.url)

            #expect(outcome == .completed)
            #expect(try await oid(repo, "HEAD") == before)
            let staged = try await provider(repo).status(in: repo.url).entries.filter(\.isStaged).map(\.path)
            #expect(staged == ["feature.txt"])
            #expect(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent(".git/SQUASH_MSG").path))
        }
    }

    // MARK: Rebase

    @Test func rebaseReplaysTheCurrentBranchOntoAnother() async throws {
        try await withDivergedBranches { repo in
            try await repo.git("switch", "-q", "feature")

            let outcome = try await provider(repo).rebase(onto: "main", autostash: true, in: repo.url)

            #expect(outcome == .completed)
            #expect(try await oid(repo, "HEAD^") == oid(repo, "main"))
            #expect(try await currentBranch(repo) == "feature")
        }
    }

    @Test func conflictingRebaseStopsAndContinuesOnceResolved() async throws {
        try await withConflictingBranches { repo in
            try await repo.git("switch", "-q", "feature")

            let outcome = try await provider(repo).rebase(onto: "main", autostash: true, in: repo.url)

            guard case .stopped = outcome else {
                Issue.record("Expected the rebase to stop on the conflict, got \(outcome)")
                return
            }
            #expect(try await provider(repo).operationState(in: repo.url) == .rebase)
            // Continuing with the conflict unresolved stops again instead of failing.
            guard case .stopped = try await provider(repo).continueRebase(in: repo.url) else {
                Issue.record("Continuing with unresolved conflicts must stop again")
                return
            }

            try repo.write("shared.txt", "resolved\n")
            try await repo.git("add", "shared.txt")
            #expect(try await provider(repo).continueRebase(in: repo.url) == .completed)
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
            #expect(try await oid(repo, "HEAD^") == oid(repo, "main"))
            #expect(try repo.read("shared.txt") == "resolved\n")
        }
    }

    @Test func abortingARebaseRestoresTheBranch() async throws {
        try await withConflictingBranches { repo in
            try await repo.git("switch", "-q", "feature")
            let before = try await oid(repo, "HEAD")
            _ = try await provider(repo).rebase(onto: "main", autostash: true, in: repo.url)

            try await provider(repo).abortOperation(.rebase, in: repo.url)

            #expect(try await provider(repo).operationState(in: repo.url) == nil)
            #expect(try await oid(repo, "HEAD") == before)
            #expect(try await currentBranch(repo) == "feature")
        }
    }

    @Test func skippingTheConflictingCommitFinishesTheRebase() async throws {
        try await withConflictingBranches { repo in
            try await repo.git("switch", "-q", "feature")
            _ = try await provider(repo).rebase(onto: "main", autostash: true, in: repo.url)

            #expect(try await provider(repo).skipRebaseCommit(in: repo.url) == .completed)
            #expect(try await oid(repo, "HEAD") == oid(repo, "main"))
        }
    }

    // MARK: Interactive rebase

    @Test func rebaseCandidatesAreOldestFirstWithoutCommitsAlreadyOnTheTarget() async throws {
        try await withFeatureStack { repo, commits in
            // A copy of C on main makes Git skip C in the replay.
            try await repo.git("switch", "-q", "main")
            try await repo.git("cherry-pick", commits[2])
            try await repo.git("switch", "-q", "feature")

            let candidates = try await provider(repo).rebaseCandidates(onto: "main", in: repo.url)

            #expect(candidates.map(\.oid) == [commits[0], commits[1], commits[3]])
            #expect(candidates.map(\.subject) == ["A", "B", "D"])
        }
    }

    @Test func interactiveRebaseReordersRewordsFixesUpAndDrops() async throws {
        try await withFeatureStack { repo, commits in
            let plan = try InteractiveRebasePlan(original: commits, items: [
                RebaseTodoItem(oid: commits[2], action: .pick),
                RebaseTodoItem(oid: commits[0], action: .reword("A reworded\n\nWith a body.")),
                RebaseTodoItem(oid: commits[1], action: .fixup),
                RebaseTodoItem(oid: commits[3], action: .drop)
            ])

            let outcome = try await provider(repo).interactiveRebase(onto: "main", plan: plan, autostash: true, in: repo.url)

            #expect(outcome == .completed)
            let subjects = try await repo.git("log", "--format=%s", "main..HEAD").stdoutString
            #expect(subjects == "A reworded\nC\n")
            #expect(try await repo.git("log", "-1", "--format=%b").stdoutString.contains("With a body."))
            #expect(try repo.read("a.txt") == "a\nb\n")
            #expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("d.txt").path))
        }
    }

    @Test func squashKeepsBothMessages() async throws {
        try await withFeatureStack { repo, commits in
            let plan = try InteractiveRebasePlan(original: commits, items: [
                RebaseTodoItem(oid: commits[0]),
                RebaseTodoItem(oid: commits[1], action: .squash),
                RebaseTodoItem(oid: commits[2]),
                RebaseTodoItem(oid: commits[3])
            ])

            #expect(try await provider(repo).interactiveRebase(onto: "main", plan: plan, autostash: true, in: repo.url) == .completed)

            let messages = try await repo.git("log", "--format=%B%x00", "main..HEAD").stdoutString
                .split(separator: "\0").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            #expect(messages.count == 3)
            #expect(messages.last == "A\n\nB")
        }
    }

    @Test func editStopsForAmendingAndARewordAfterItSurvivesTheStop() async throws {
        try await withFeatureStack { repo, commits in
            let plan = try InteractiveRebasePlan(original: commits, items: [
                RebaseTodoItem(oid: commits[0], action: .edit),
                RebaseTodoItem(oid: commits[1], action: .reword("B reworded")),
                RebaseTodoItem(oid: commits[2]),
                RebaseTodoItem(oid: commits[3])
            ])

            let outcome = try await provider(repo).interactiveRebase(onto: "main", plan: plan, autostash: true, in: repo.url)

            guard case .stopped = outcome else {
                Issue.record("Edit must stop the rebase, got \(outcome)")
                return
            }
            #expect(try await provider(repo).operationState(in: repo.url) == .rebase)
            let message = repo.url.appendingPathComponent(".git/rebase-merge/avi-messages/\(commits[1])")
            #expect(FileManager.default.fileExists(atPath: message.path))

            #expect(try await provider(repo).continueRebase(in: repo.url) == .completed)
            let subjects = try await repo.git("log", "--format=%s", "main..HEAD").stdoutString
            #expect(subjects == "D\nC\nB reworded\nA\n")
        }
    }

    @Test func interactiveRebaseRefusesOnceTheBranchMoved() async throws {
        try await withFeatureStack { repo, commits in
            let plan = try InteractiveRebasePlan(original: commits, items: commits.map { RebaseTodoItem(oid: $0, action: .drop) })
            try await commit(repo, "e.txt", "e\n", "E")
            let moved = try await oid(repo, "HEAD")

            await #expect(throws: GitError.self) {
                try await provider(repo).interactiveRebase(onto: "main", plan: plan, autostash: true, in: repo.url)
            }
            // Nothing was dropped and no rebase is left behind.
            #expect(try await oid(repo, "HEAD") == moved)
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
        }
    }

    // MARK: Checkout

    @Test func checkoutCarriesStagedUnstagedAndNewFilesAlong() async throws {
        try await withBranches { repo in
            try repo.write("base.txt", "edited\n")
            try repo.write("staged.txt", "staged\n")
            try await repo.git("add", "staged.txt")
            try repo.write("new.txt", "new\n")
            let feature = try #require(try await provider(repo).refs(in: repo.url).localBranches.first { $0.name == "feature" })

            let outcome = try await provider(repo).checkout(feature, carryingLocalChanges: true, in: repo.url)

            #expect(outcome == .switched)
            #expect(try await currentBranch(repo) == "feature")
            #expect(try repo.read("base.txt") == "edited\n")
            #expect(try repo.read("new.txt") == "new\n")
            let entries = try await provider(repo).status(in: repo.url).entries
            #expect(entries.first { $0.path == "staged.txt" }?.isStaged == true)
            #expect(try await provider(repo).stashes(in: repo.url).isEmpty)
        }
    }

    @Test func conflictingCarriedChangesStayInTheStash() async throws {
        try await withConflictingBranches { repo in
            try repo.write("shared.txt", "uncommitted\n")
            let feature = try #require(try await provider(repo).refs(in: repo.url).localBranches.first { $0.name == "feature" })

            let outcome = try await provider(repo).checkout(feature, carryingLocalChanges: true, in: repo.url)

            guard case .changesConflicted = outcome else {
                Issue.record("Expected a conflict, got \(outcome)")
                return
            }
            #expect(try await currentBranch(repo) == "feature")
            #expect(try await provider(repo).stashes(in: repo.url).count == 1)
        }
    }

    @Test func checkoutWithNothingToCarryCreatesNoStash() async throws {
        try await withBranches { repo in
            let feature = try #require(try await provider(repo).refs(in: repo.url).localBranches.first { $0.name == "feature" })

            #expect(try await provider(repo).checkout(feature, carryingLocalChanges: true, in: repo.url) == .switched)
            #expect(try await provider(repo).stashes(in: repo.url).isEmpty)
        }
    }

    // MARK: Worktrees

    @Test func addWorktreeChecksTheBranchOutInANewFolder() async throws {
        try await withBranches { repo in
            let path = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-wt-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: path) }

            try await provider(repo).addWorktree(at: path, branch: "feature", in: repo.url)

            let worktrees = try await provider(repo).worktrees(in: repo.url)
            #expect(worktrees.contains { $0.branch == "feature" && $0.path.lastPathComponent == path.lastPathComponent })
        }
    }

    @Test func addWorktreeOnlyTakesLocalBranches() async throws {
        try await withBranches { repo in
            try await repo.git("tag", "v1")
            let path = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-wt-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: path) }

            await #expect(throws: GitError.self) {
                try await provider(repo).addWorktree(at: path, branch: "v1", in: repo.url)
            }
            #expect(!FileManager.default.fileExists(atPath: path.path))
        }
    }

    // MARK: Helpers

    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    private func commit(_ repo: GitFixture, _ file: String, _ content: String, _ message: String) async throws {
        try repo.write(file, content)
        try await repo.git("add", "--", file)
        try await repo.git("commit", "-q", "-m", message)
    }

    private func oid(_ repo: GitFixture, _ revision: String) async throws -> String {
        try await repo.git("rev-parse", revision).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentBranch(_ repo: GitFixture) async throws -> String {
        try await repo.git("branch", "--show-current").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `main` one commit ahead of `feature`; `main` checked out.
    private func withBranches(_ body: (GitFixture) async throws -> Void) async throws {
        try await withTempRepo { repo in
            try await commit(repo, "base.txt", "base\n", "base")
            try await repo.git("branch", "-M", "main")
            try await repo.git("branch", "feature")
            try await commit(repo, "main.txt", "main\n", "main work")
            try await body(repo)
        }
    }

    /// `main` and `feature` each with a commit of their own; `main` checked out.
    private func withDivergedBranches(_ body: (GitFixture) async throws -> Void) async throws {
        try await withBranches { repo in
            try await repo.git("switch", "-q", "feature")
            try await commit(repo, "feature.txt", "feature\n", "feature work")
            try await repo.git("switch", "-q", "main")
            try await body(repo)
        }
    }

    /// `main` and `feature` changing the same line; `main` checked out.
    private func withConflictingBranches(_ body: (GitFixture) async throws -> Void) async throws {
        try await withTempRepo { repo in
            try await commit(repo, "shared.txt", "base\n", "base")
            try await repo.git("branch", "-M", "main")
            try await repo.git("branch", "feature")
            try await commit(repo, "shared.txt", "main side\n", "main side")
            try await repo.git("switch", "-q", "feature")
            try await commit(repo, "shared.txt", "feature side\n", "feature side")
            try await repo.git("switch", "-q", "main")
            try await body(repo)
        }
    }

    /// `feature` with commits A, B (both touching a.txt), C, and D on top of
    /// `main`; `feature` checked out. Passes the commit IDs oldest first.
    private func withFeatureStack(_ body: (GitFixture, [String]) async throws -> Void) async throws {
        try await withTempRepo { repo in
            try await commit(repo, "base.txt", "base\n", "base")
            try await repo.git("branch", "-M", "main")
            try await repo.git("switch", "-q", "-c", "feature")
            var commits: [String] = []
            for (file, content, message) in [("a.txt", "a\n", "A"), ("a.txt", "a\nb\n", "B"), ("c.txt", "c\n", "C"), ("d.txt", "d\n", "D")] {
                try await commit(repo, file, content, message)
                try await commits.append(oid(repo, "HEAD"))
            }
            try await body(repo, commits)
        }
    }
}
