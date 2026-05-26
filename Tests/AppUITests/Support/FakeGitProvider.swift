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
    public func deleteBranch(named _: String, in _: URL) async throws {}
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
        GitRemoteOperationResult(output: "ok")
    }

    public func push(branch _: String?, in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }

    public func stage(path _: String, in _: URL) async throws {}
    public func stageAll(in _: URL) async throws {}
    public func unstage(path _: String, in _: URL) async throws {}
    public func unstageAll(in _: URL) async throws {}
    public func discard(_: FileStatus, in _: URL) async throws {}
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

    public func pushTag(name _: String, remote _: String?, in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
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

    public func push(branch _: String?, remote _: String?, force _: Bool, pushTags _: Bool, in _: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }

    public func stashes(in _: URL) async throws -> [StashEntry] {
        []
    }

    public func applyStash(ref _: String, in _: URL) async throws {}
    public func popStash(ref _: String, in _: URL) async throws {}
    public func dropStash(ref _: String, in _: URL) async throws {}
}
