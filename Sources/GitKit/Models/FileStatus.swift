/// Per-side change code from `git status --porcelain=v2`.
public enum FileState: Sendable, Equatable {
    case unmodified
    case modified
    case added
    case deleted
    case renamed
    case copied
    case typeChanged
    case updatedButUnmerged
    case untracked
    case ignored
}

/// One changed path in the working copy. `index` is the staged side (X),
/// `worktree` is the unstaged side (Y).
public struct FileStatus: Sendable, Equatable, Identifiable {
    public var id: String {
        path
    }

    public let path: String
    public let originalPath: String?
    public let index: FileState
    public let worktree: FileState
    /// Unmerged: a merge, rebase, or stash apply stopped on a conflict in this
    /// file. Git reports it apart from ordinary changes, whatever X and Y say.
    public let isConflicted: Bool

    public init(path: String, originalPath: String? = nil, index: FileState, worktree: FileState, isConflicted: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.index = index
        self.worktree = worktree
        self.isConflicted = isConflicted
    }

    public var isUntracked: Bool {
        worktree == .untracked
    }

    /// True when there is something staged for the next commit.
    public var isStaged: Bool {
        switch index {
        case .unmodified, .untracked, .ignored: return false
        default: return true
        }
    }

    /// True when the working tree differs from the index.
    public var hasUnstagedChanges: Bool {
        switch worktree {
        case .unmodified, .ignored: return false
        default: return true
        }
    }
}
