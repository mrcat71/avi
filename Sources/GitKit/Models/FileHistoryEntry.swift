import Foundation

/// One commit in a file's history, with the file's name at that commit, so a
/// file that was renamed still shows its older changes.
public struct FileHistoryEntry: Sendable, Equatable, Identifiable {
    public var id: String {
        commit.oid
    }

    public let commit: CommitSummary
    /// The file's path in this commit.
    public let path: String
    /// The path before this commit, when the commit renamed or copied the file.
    public let oldPath: String?
    public let kind: CommitFileChangeKind

    public init(commit: CommitSummary, path: String, oldPath: String? = nil, kind: CommitFileChangeKind) {
        self.commit = commit
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
    }
}
