import Foundation

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

    /// Recent commits in newest-to-oldest topological order.
    func history(in repository: URL, limit: Int) async throws -> [CommitSummary]

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

    /// Delete a local branch using Git's safe non-force delete.
    func deleteBranch(named name: String, in repository: URL) async throws

    /// Fetch from one remote or all configured remotes when nil.
    func fetch(remote: String?, in repository: URL) async throws -> GitRemoteOperationResult

    /// Pull the current branch with a fast-forward-only strategy.
    func pull(in repository: URL) async throws -> GitRemoteOperationResult

    /// Push the current branch. If it has no upstream, set origin/<branch> when origin exists.
    func push(in repository: URL) async throws -> GitRemoteOperationResult

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
}
