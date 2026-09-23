import Foundation
@testable import GitKit

/// In-memory GitProviding used by snapshot tests to render `RepositoryStore`-backed views
/// with deterministic data and no shell-outs to git. Marked `@unchecked Sendable`
/// because the test fake mutates state from tests on a single thread.
public final class FakeGitProvider: GitProviding, @unchecked Sendable {
    public var status: WorkingCopyStatus
    public var refs: RepositoryRefs
    public var commits: [CommitSummary]
    public var remotes: [GitRemote]
    public var fileDiffs: [String: FileDiff]
    public var commitFiles: [String: [CommitFileChange]]
    public var lastCommit: String?

    /// Recorded calls for batched staging assertions in tests.
    public private(set) var stagePathsCalls: [[String]] = []
    public private(set) var unstagePathsCalls: [[String]] = []
    /// Paths passed to the batched `discard`, one entry per call.
    public private(set) var discardCalls: [[String]] = []
    /// Branch names passed to `deleteBranch`, in call order.
    public private(set) var deleteBranchCalls: [String] = []
    /// Tag names passed to `deleteTag`, in call order.
    public private(set) var deleteTagCalls: [String] = []
    /// Tag names passed to `pushTag`, with the resolved remote.
    public private(set) var pushTagCalls: [(name: String, remote: String?)] = []
    /// Branches that `deleteBranch` refuses, mirroring `git branch -d` on unmerged work.
    public var unmergedBranches: Set<String> = []
    /// Branches whose deletion fails for a reason forcing cannot fix.
    public var brokenBranches: Set<String> = []
    /// Anything that would reach the remote, so local-only operations can assert on it.
    public private(set) var pushCalls: [String] = []
    /// Stash changed-files keyed by stash ref, for stash-content tests.
    public var stashChanges: [String: [CommitFileChange]] = [:]
    /// Worktrees reported by `worktrees(in:)`, main worktree first.
    public var worktrees: [Worktree] = []
    /// Common dir reported by `location(of:)`; nil means an ordinary repository.
    public var commonDir: URL?
    /// When set, batched stage/unstage calls update `status` like Git would.
    public var appliesStaging = false
    /// Plans passed to `commitFiles`, in call order.
    public private(set) var commitPlanCalls: [FileCommitPlan] = []
    /// Makes `commitFiles` stop with `CommitPlanError` after this many commits.
    public var failCommitPlanAfter: Int?

    public init(
        status: WorkingCopyStatus,
        refs: RepositoryRefs = .empty,
        commits: [CommitSummary] = [],
        remotes: [GitRemote] = [],
        fileDiffs: [String: FileDiff] = [:],
        commitFiles: [String: [CommitFileChange]] = [:],
        lastCommit: String? = nil
    ) {
        self.status = status
        self.refs = refs
        self.commits = commits
        self.remotes = remotes
        self.fileDiffs = fileDiffs
        self.commitFiles = commitFiles
        self.lastCommit = lastCommit
    }

    public func repositoryRoot(for url: URL) async throws -> URL {
        url
    }

    public func location(of repository: URL) async throws -> RepositoryLocation {
        RepositoryLocation(
            workingTree: repository,
            gitDir: repository.appendingPathComponent(".git"),
            commonDir: commonDir ?? repository.appendingPathComponent(".git")
        )
    }

    public func worktrees(in _: URL) async throws -> [Worktree] {
        worktrees
    }

    public func status(in _: URL) async throws -> WorkingCopyStatus {
        status
    }

    public func diff(path: String, source _: DiffSource, in _: URL) async throws -> FileDiff {
        fileDiffs[path] ?? FileDiff(hunks: [], isBinary: false)
    }

    public func history(in _: URL, limit _: Int) async throws -> [CommitSummary] {
        commits
    }

    public func history(in _: URL, limit _: Int, filter _: HistoryFilter) async throws -> [CommitSummary] {
        commits
    }

    public func refs(in _: URL) async throws -> RepositoryRefs {
        refs
    }

    public func remotes(in _: URL) async throws -> [GitRemote] {
        remotes
    }

    public func changedFiles(in commitOID: String, in _: URL) async throws -> [CommitFileChange] {
        commitFiles[commitOID] ?? []
    }

    public func diff(commitOID _: String, path: String, in _: URL) async throws -> FileDiff {
        fileDiffs[path] ?? FileDiff(hunks: [], isBinary: false)
    }

    public func checkout(_: GitReference, in _: URL) async throws {}
    public func createBranch(named _: String, startPoint _: String?, checkout _: Bool, in _: URL) async throws {}
    public func renameBranch(from _: String, to _: String, in _: URL) async throws {}
    public func setUpstream(branch _: String, upstream _: String, in _: URL) async throws {}
    public func unsetUpstream(branch _: String, in _: URL) async throws {}
    public func deleteBranch(named name: String, force: Bool, in _: URL) async throws {
        deleteBranchCalls.append(force ? "\(name) (forced)" : name)
        if brokenBranches.contains(name) {
            throw GitError.commandFailed(
                command: "git branch -d -- \(name)",
                exitCode: 1,
                stderr: "error: worktree is dirty"
            )
        }
        if unmergedBranches.contains(name), !force {
            throw GitError.commandFailed(
                command: "git branch -d -- \(name)",
                exitCode: 1,
                stderr: "error: the branch '\(name)' is not fully merged"
            )
        }
        refs = RepositoryRefs(
            localBranches: refs.localBranches.filter { $0.name != name },
            remoteBranches: refs.remoteBranches,
            tags: refs.tags
        )
    }

    public func fetch(remote _: String?, in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }

    public func pull(in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }

    public func pull(branch _: String?, in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }

    public func push(in _: URL) async throws -> GitRemoteOperationResult {
        pushCalls.append("push")
        return GitRemoteOperationResult(output: "ok")
    }

    public func push(branch: String?, in _: URL) async throws -> GitRemoteOperationResult {
        pushCalls.append("push \(branch ?? "")")
        return GitRemoteOperationResult(output: "ok")
    }

    public func stage(path _: String, in _: URL) async throws {}
    public func stage(paths: [String], in _: URL) async throws {
        stagePathsCalls.append(paths)
        guard appliesStaging else { return }
        let chosen = Set(paths)
        status = WorkingCopyStatus(branch: status.branch, entries: status.entries.map { entry in
            guard chosen.contains(entry.path) else { return entry }
            let index: FileState = entry.isUntracked ? .added : (entry.worktree == .deleted ? .deleted : .modified)
            return FileStatus(path: entry.path, originalPath: entry.originalPath, index: index, worktree: .unmodified)
        })
    }

    public func stageAll(in _: URL) async throws {}
    public func unstage(path _: String, in _: URL) async throws {}
    public func unstage(paths: [String], in _: URL) async throws {
        unstagePathsCalls.append(paths)
        guard appliesStaging else { return }
        let chosen = Set(paths)
        status = WorkingCopyStatus(branch: status.branch, entries: status.entries.map { entry in
            guard chosen.contains(entry.path), entry.isStaged else { return entry }
            let worktree: FileState = entry.index == .added ? .untracked : entry.index
            return FileStatus(path: entry.path, originalPath: entry.originalPath, index: entry.index == .added ? .untracked : .unmodified, worktree: worktree)
        })
    }

    /// Diff text returned for any paths, and the paths asked for.
    public var workingTreeDiffText = "diff --git a/file b/file"
    public private(set) var workingTreeDiffCalls: [[String]] = []

    public func workingTreeDiff(paths: [String], in _: URL) async throws -> String {
        workingTreeDiffCalls.append(paths)
        return workingTreeDiffText
    }

    public func commitFiles(_ plan: FileCommitPlan, in _: URL, progress: (@Sendable (Int) -> Void)?) async throws {
        commitPlanCalls.append(plan)
        let commits = try plan.resolved(against: status)
        for (index, commit) in commits.enumerated() {
            if let limit = failCommitPlanAfter, index == limit {
                throw CommitPlanError(completed: index, total: commits.count, reason: "simulated hook failure")
            }
            let done = Set(commit.files)
            status = WorkingCopyStatus(branch: status.branch, entries: status.entries.filter { !done.contains($0.path) })
            progress?(index + 1)
        }
    }

    public func unstageAll(in _: URL) async throws {}
    public func discard(_ file: FileStatus, in _: URL) async throws {
        discardCalls.append([file.path])
    }

    public func discard(_ files: [FileStatus], in _: URL) async throws {
        discardCalls.append(files.map(\.path))
    }

    public func commit(message _: String, in _: URL) async throws {}
    public func amend(message _: String?, in _: URL) async throws {}
    public func lastCommitMessage(in _: URL) async throws -> String? {
        lastCommit
    }

    public func stagedDiff(in _: URL) async throws -> String {
        ""
    }

    public func defaultBranch(remote _: String, in _: URL) async throws -> String? {
        nil
    }

    public func createTag(name _: String, targetOID _: String, message _: String?, in _: URL) async throws {}

    public func deleteTag(named name: String, in _: URL) async throws {
        deleteTagCalls.append(name)
        refs = RepositoryRefs(
            localBranches: refs.localBranches,
            remoteBranches: refs.remoteBranches,
            tags: refs.tags.filter { $0.name != name }
        )
    }

    public func pushTag(name: String, remote: String?, in _: URL) async throws -> GitRemoteOperationResult {
        pushTagCalls.append((name: name, remote: remote))
        return GitRemoteOperationResult(output: "ok")
    }

    public func commitMessage(for _: String, in _: URL) async throws -> String? {
        nil
    }

    public func commitDiff(for _: String, in _: URL) async throws -> String {
        ""
    }

    public func commitRangeDiff(oldest _: String, newest _: String, in _: URL) async throws -> String {
        ""
    }

    public func reset(mode _: GitResetMode, target _: String?, in _: URL) async throws {}

    public func rebaseSingle(commit _: String, action _: SingleCommitRebaseAction, in _: URL) async throws {}

    public func rebaseRangeEdit(oldest _: String, newest _: String, in _: URL) async throws {}

    public func rebaseContinue(in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }

    public func rebaseAbort(in _: URL) async throws {}

    public func isRebaseInProgress(in _: URL) async -> Bool {
        false
    }

    public func push(branch: String?, remote: String?, force _: Bool, pushTags _: Bool, in _: URL) async throws -> GitRemoteOperationResult {
        pushCalls.append("push \(remote ?? "") \(branch ?? "")")
        return GitRemoteOperationResult(output: "ok")
    }

    public func stashes(in _: URL) async throws -> [StashEntry] {
        []
    }

    public func applyStash(ref _: String, in _: URL) async throws {}
    public func popStash(ref _: String, in _: URL) async throws {}
    public func dropStash(ref _: String, in _: URL) async throws {}

    public func stashChangedFiles(ref: String, in _: URL) async throws -> [CommitFileChange] {
        stashChanges[ref] ?? []
    }

    public func stashDiff(ref _: String, path: String, in _: URL) async throws -> FileDiff {
        fileDiffs[path] ?? FileDiff(hunks: [], isBinary: false)
    }
}
