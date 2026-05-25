import Foundation

/// Filtering options for `history(in:limit:filter:)`.
public struct HistoryFilter: Sendable, Equatable {
    public enum Scope: Sendable, Equatable {
        /// Default: only the current branch and its ancestors.
        case currentBranch
        /// `git log --all`: every ref.
        case allBranches
        /// Single ref name (branch / remote / tag) used as the log root.
        case ref(String)
    }

    public var scope: Scope
    public var hideMerges: Bool

    public init(scope: Scope = .currentBranch, hideMerges: Bool = false) {
        self.scope = scope
        self.hideMerges = hideMerges
    }

    public static let `default` = HistoryFilter()
}

/// The seam between the app and Git. The CLI implementation comes first; a
/// libgit2-backed implementation can be added later for hot-path reads and
/// swapped in behind this protocol.
public protocol GitProviding: Sendable {
    /// Top-level directory of the repository containing `url`. Throws if `url` is not in a repo.
    func repositoryRoot(for url: URL) async throws -> URL

    /// Working-copy status of `repository`: current branch plus changed entries.
    func status(in repository: URL) async throws -> WorkingCopyStatus

    /// Unified diff for `path` against the given `source`.
    func diff(path: String, source: DiffSource, in repository: URL) async throws -> FileDiff

    /// Recent commits in newest-to-oldest topological order, default filter (current branch, with merges).
    func history(in repository: URL, limit: Int) async throws -> [CommitSummary]

    /// Filtered history: scope (current / all / ref) and optional merge hiding.
    func history(in repository: URL, limit: Int, filter: HistoryFilter) async throws -> [CommitSummary]

    /// Local branches, remote branches, and tags.
    func refs(in repository: URL) async throws -> RepositoryRefs

    /// Configured Git remotes.
    func remotes(in repository: URL) async throws -> [GitRemote]

    /// Files changed by `commitOID`.
    func changedFiles(in commitOID: String, in repository: URL) async throws -> [CommitFileChange]

    /// Unified diff for one file as changed by `commitOID`.
    func diff(commitOID: String, path: String, in repository: URL) async throws -> FileDiff

    /// Check out a local branch, create a tracking branch from a remote branch, or detach at a tag.
    func checkout(_ ref: GitReference, in repository: URL) async throws

    /// Create a branch. When `checkout` is true, switch to it immediately.
    func createBranch(named name: String, startPoint: String?, checkout: Bool, in repository: URL) async throws

    /// Rename a local branch. The branch does not need to be the current one.
    func renameBranch(from oldName: String, to newName: String, in repository: URL) async throws

    /// Set the upstream tracking branch for `branch` to `upstream` (e.g. `origin/main`).
    func setUpstream(branch: String, upstream: String, in repository: URL) async throws

    /// Clear upstream tracking on `branch`.
    func unsetUpstream(branch: String, in repository: URL) async throws

    /// Delete a local branch using Git's safe non-force delete.
    func deleteBranch(named name: String, in repository: URL) async throws

    /// Create a tag at `targetOID`. When `message` is nil, creates a lightweight tag;
    /// when non-nil, creates an annotated tag (`git tag -a <name> <oid> -m <message>`).
    /// Throws if the tag already exists - callers should surface the error.
    func createTag(name: String, targetOID: String, message: String?, in repository: URL) async throws

    /// Push a single tag to `remote` (defaults to "origin" when nil).
    /// Runs `git push <remote> refs/tags/<name>`.
    func pushTag(name: String, remote: String?, in repository: URL) async throws -> GitRemoteOperationResult

    /// Fetch from one remote or all configured remotes when nil.
    func fetch(remote: String?, in repository: URL) async throws -> GitRemoteOperationResult

    /// Pull the current branch using git's default merge strategy.
    /// Diverged branches produce a merge commit. A dirty working tree
    /// still aborts the pull (git refuses to overwrite local changes).
    func pull(in repository: URL) async throws -> GitRemoteOperationResult

    /// Pull a branch using git's default merge strategy. When `branch` is nil,
    /// pulls the current branch. If `branch` is not the current branch, uses
    /// `git fetch <remote> <upstream>:<branch>` to fast-forward the local ref
    /// without checking out.
    func pull(branch: String?, in repository: URL) async throws -> GitRemoteOperationResult

    /// Push the current branch. If it has no upstream, set origin/<branch> when origin exists.
    func push(in repository: URL) async throws -> GitRemoteOperationResult

    /// Push a specific branch. When `branch` is nil, pushes the current branch.
    /// For non-current branches with an upstream, runs `git push <remote> <branch>:<upstream-branch>`.
    /// For non-current branches without an upstream, throws.
    func push(branch: String?, in repository: URL) async throws -> GitRemoteOperationResult

    /// Push the current branch with explicit options. `remote` overrides the upstream remote.
    /// `force` uses `--force-with-lease` (safer than `--force`). `pushTags` adds `--tags`.
    func push(
        branch: String?,
        remote: String?,
        force: Bool,
        pushTags: Bool,
        in repository: URL
    ) async throws -> GitRemoteOperationResult

    /// Stage `path` (`git add`).
    func stage(path: String, in repository: URL) async throws

    /// Stage all tracked and untracked working-copy changes.
    func stageAll(in repository: URL) async throws

    /// Unstage `path`, keeping working-tree changes (`git restore --staged`).
    func unstage(path: String, in repository: URL) async throws

    /// Unstage all staged changes, keeping working-tree changes.
    func unstageAll(in repository: URL) async throws

    /// Discard changes for `file`. Destructive: callers must confirm with the user first.
    /// Tracked files are restored from the index; untracked files are deleted.
    func discard(_ file: FileStatus, in repository: URL) async throws

    /// Commit staged changes with `message` (`git commit -m`).
    func commit(message: String, in repository: URL) async throws

    /// Amend the last commit. A non-nil `message` replaces it; nil keeps it (`--no-edit`).
    func amend(message: String?, in repository: URL) async throws

    /// Subject+body of the last commit, or nil if there are no commits yet.
    func lastCommitMessage(in repository: URL) async throws -> String?

    /// Raw unified diff of staged changes (used as AI input).
    func stagedDiff(in repository: URL) async throws -> String

    /// Full subject + body of the commit at `oid`, or `nil` if it doesn't exist.
    func commitMessage(for oid: String, in repository: URL) async throws -> String?

    /// Unified diff produced by a single commit (`git show --format= <oid>`).
    func commitDiff(for oid: String, in repository: URL) async throws -> String

    /// Unified diff covering the combined changes from `oldest`^..`newest`
    /// (used as input for multi-commit AI recompose).
    func commitRangeDiff(oldest: String, newest: String, in repository: URL) async throws -> String

    /// `git reset --<mode> <target>`. Pass `target = nil` to reset against HEAD.
    func reset(mode: GitResetMode, target: String?, in repository: URL) async throws

    /// Begin a one-commit-targeted interactive rebase. For `.edit` the rebase
    /// pauses at `oid` and the method returns; for `.reword(newMessage:)` the
    /// rebase runs to completion replacing only that commit's message.
    func rebaseSingle(commit oid: String, action: SingleCommitRebaseAction, in repository: URL) async throws

    /// Begin an interactive rebase that pauses just AFTER applying `newest`,
    /// keeping everything from `oldest` through `newest` (inclusive) as picks.
    /// Caller is then expected to `git reset --mixed <oldest>^` to roll back
    /// the whole range, stage the new groups, commit them, and call
    /// `rebaseContinue` to replay the commits that came after `newest`.
    func rebaseRangeEdit(oldest: String, newest: String, in repository: URL) async throws

    /// `git rebase --continue`. Surfaces stderr through the result so the UI
    /// can show conflicts.
    func rebaseContinue(in repository: URL) async throws -> GitRemoteOperationResult

    /// `git rebase --abort`. Best-effort: ignores the "no rebase in progress" error.
    func rebaseAbort(in repository: URL) async throws

    /// True iff `.git/rebase-merge` or `.git/rebase-apply` exists.
    func isRebaseInProgress(in repository: URL) async -> Bool
}

public enum GitResetMode: String, Sendable {
    case soft
    case mixed
    case hard
}

public enum SingleCommitRebaseAction: Sendable {
    /// Rebase pauses at the target commit; caller is expected to mutate the
    /// working tree, stage groups, and call `rebaseContinue`.
    case edit
    /// Rebase runs to completion replacing the target commit's message.
    case reword(newMessage: String)
}

public extension GitProviding {
    /// Default implementation forwards the simple `history` call to the filtered variant.
    func history(in repository: URL, limit: Int) async throws -> [CommitSummary] {
        try await history(in: repository, limit: limit, filter: .default)
    }

    /// Default implementation: delegates to the simple `push(branch:in:)` for callers that
    /// don't need the explicit-flags overload. CLI provider overrides this with real flag handling.
    func push(
        branch: String?,
        remote _: String?,
        force _: Bool,
        pushTags _: Bool,
        in repository: URL
    ) async throws -> GitRemoteOperationResult {
        try await push(branch: branch, in: repository)
    }
}
