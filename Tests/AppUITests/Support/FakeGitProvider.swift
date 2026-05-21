import Foundation
@testable import GitKit

/// In-memory GitProviding used by snapshot tests to render `RepositoryStore`-backed views
/// with deterministic data and no shell-outs to git.
public final class FakeGitProvider: GitProviding {
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

    public func repositoryRoot(for url: URL) async throws -> URL { url }
    public func status(in repository: URL) async throws -> WorkingCopyStatus { status }
    public func diff(path: String, source: DiffSource, in repository: URL) async throws -> FileDiff {
        fileDiffs[path] ?? FileDiff(hunks: [], isBinary: false)
    }
    public func history(in repository: URL, limit: Int) async throws -> [CommitSummary] { commits }
    public func history(in repository: URL, limit: Int, filter: HistoryFilter) async throws -> [CommitSummary] { commits }
    public func refs(in repository: URL) async throws -> RepositoryRefs { refs }
    public func remotes(in repository: URL) async throws -> [GitRemote] { remotes }
    public func changedFiles(in commitOID: String, in repository: URL) async throws -> [CommitFileChange] {
        commitFiles[commitOID] ?? []
    }
    public func diff(commitOID: String, path: String, in repository: URL) async throws -> FileDiff {
        fileDiffs[path] ?? FileDiff(hunks: [], isBinary: false)
    }
    public func checkout(_ ref: GitReference, in repository: URL) async throws {}
    public func createBranch(named name: String, startPoint: String?, checkout: Bool, in repository: URL) async throws {}
    public func renameBranch(from oldName: String, to newName: String, in repository: URL) async throws {}
    public func setUpstream(branch: String, upstream: String, in repository: URL) async throws {}
    public func unsetUpstream(branch: String, in repository: URL) async throws {}
    public func deleteBranch(named name: String, in repository: URL) async throws {}
    public func fetch(remote: String?, in repository: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }
    public func pull(in repository: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }
    public func pull(branch: String?, in repository: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }
    public func push(in repository: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }
    public func push(branch: String?, in repository: URL) async throws -> GitRemoteOperationResult {
        GitRemoteOperationResult(output: "ok")
    }
    public func stage(path: String, in repository: URL) async throws {}
    public func stageAll(in repository: URL) async throws {}
    public func unstage(path: String, in repository: URL) async throws {}
    public func unstageAll(in repository: URL) async throws {}
    public func discard(_ file: FileStatus, in repository: URL) async throws {}
    public func commit(message: String, in repository: URL) async throws {}
    public func amend(message: String?, in repository: URL) async throws {}
    public func lastCommitMessage(in repository: URL) async throws -> String? { lastCommit }
    public func stagedDiff(in repository: URL) async throws -> String { "" }
}
