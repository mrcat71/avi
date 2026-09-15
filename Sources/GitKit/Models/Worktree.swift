import Foundation

/// One entry from `git worktree list --porcelain`. The main worktree is always
/// first; the rest are linked worktrees sharing this repository's refs.
public struct Worktree: Sendable, Equatable, Identifiable {
    public var id: String {
        path.standardizedFileURL.path
    }

    public let path: URL
    public let headOID: String?
    /// Short branch name. nil when the worktree has a detached HEAD or is bare.
    public let branch: String?
    public let isBare: Bool
    public let isLocked: Bool
    /// Reason git recorded for the lock, when it recorded one.
    public let lockReason: String?
    public let isPrunable: Bool
    public let prunableReason: String?

    public init(
        path: URL,
        headOID: String? = nil,
        branch: String? = nil,
        isBare: Bool = false,
        isLocked: Bool = false,
        lockReason: String? = nil,
        isPrunable: Bool = false,
        prunableReason: String? = nil
    ) {
        self.path = path
        self.headOID = headOID
        self.branch = branch
        self.isBare = isBare
        self.isLocked = isLocked
        self.lockReason = lockReason
        self.isPrunable = isPrunable
        self.prunableReason = prunableReason
    }

    public var isDetached: Bool {
        branch == nil && !isBare
    }
}
