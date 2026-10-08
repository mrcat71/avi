import Foundation

/// A merge, rebase, cherry-pick, or revert that stopped half-way and waits
/// for you: conflicts to resolve, or a commit to amend during an interactive
/// rebase.
public enum GitOperationState: Sendable, Equatable {
    case merge
    case rebase
    case cherryPick
    case revert

    /// Reads the state Git keeps in `gitDir`. A linked worktree has its own
    /// git dir, so each working tree reports only its own operation.
    /// `rebase-apply` without `applying` is a rebase; with it, `git am`,
    /// which Avi does not drive and so does not report.
    public static func detect(gitDir: URL, fileManager: FileManager = .default) -> GitOperationState? {
        func exists(_ name: String) -> Bool {
            fileManager.fileExists(atPath: gitDir.appendingPathComponent(name).path)
        }
        if exists("rebase-merge") || (exists("rebase-apply") && !exists("rebase-apply/applying")) {
            return .rebase
        }
        if exists("MERGE_HEAD") {
            return .merge
        }
        if exists("CHERRY_PICK_HEAD") {
            return .cherryPick
        }
        if exists("REVERT_HEAD") {
            return .revert
        }
        return nil
    }
}

/// How a merge or rebase ended.
public enum IntegrationOutcome: Sendable, Equatable {
    /// Finished. Nothing waits.
    case completed
    /// Git stopped with the operation still in progress, to resolve conflicts
    /// or amend a commit. Carries Git's own explanation.
    case stopped(String)
}

/// How `git merge` combines the other branch.
public enum MergeMode: String, Sendable, CaseIterable, Identifiable {
    /// Plain `git merge`: moves the branch when it can, else makes a merge commit.
    case fastForwardIfPossible
    /// `--no-ff`: always records a merge commit.
    case noFastForward
    /// `--ff-only`: refuses unless the branch can simply move forward.
    case fastForwardOnly
    /// `--squash`: stages the combined change and commits nothing.
    case squash

    public var id: String {
        rawValue
    }

    var argument: String? {
        switch self {
        case .fastForwardIfPossible: return nil
        case .noFastForward: return "--no-ff"
        case .fastForwardOnly: return "--ff-only"
        case .squash: return "--squash"
        }
    }
}

/// What happened to your local changes when a checkout carried them over.
public enum CheckoutOutcome: Sendable, Equatable {
    /// Switched; any carried changes are back in the working tree.
    case switched
    /// Switched, but the carried changes conflicted with the new branch. They
    /// are in the working tree with conflict markers and still in the stash.
    case changesConflicted(String)
}
