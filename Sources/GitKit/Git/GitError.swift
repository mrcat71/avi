import Foundation

public enum GitError: Error, Sendable, Equatable {
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case invalidInput(String)
    case parseFailed(String)
}

extension GitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .commandFailed(command, exitCode, stderr):
            if let worktree = GitError.worktreeHoldingBranch(stderr) {
                return "That branch is checked out in another worktree (\(worktree)). "
                    + "Switch to that worktree, or check out a different branch here."
            }
            if GitError.indicatesLockContention(stderr) {
                return "Git could not acquire a repository lock. Wait for other Git operations "
                    + "to finish, then retry. Do not remove a lock while another process may be using it.\n\n"
                    + stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` failed (exit \(exitCode))" + (detail.isEmpty ? "" : ": \(detail)")
        case let .invalidInput(detail):
            return detail
        case let .parseFailed(detail):
            return "Failed to parse git output: \(detail)"
        }
    }
}

extension GitError {
    /// True when a failed git command's stderr indicates the repository's index
    /// or a ref lock is held by another process. avi's in-process
    /// `GitCommandQueue` only serializes avi's own commands, so an external git
    /// client (IDE, terminal, another GUI) can still hold `.git/index.lock`.
    /// Used to retry briefly (see `CLIGitProvider`) and to surface a clearer
    /// message instead of a raw `fatal:`.
    /// Path from git's refusal to check out a branch another worktree holds:
    /// "fatal: 'x' is already used by worktree at '/path'". nil for anything else.
    static func worktreeHoldingBranch(_ stderr: String) -> String? {
        guard stderr.contains("is already used by worktree at") else { return nil }
        guard let start = stderr.range(of: "is already used by worktree at ") else { return nil }
        let tail = stderr[start.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = tail.hasPrefix("'")
            ? tail.dropFirst().prefix { $0 != "'" }
            : tail.prefix { !$0.isNewline }
        let path = String(unquoted)
        return path.isEmpty ? nil : path
    }

    /// True when git refused `branch -d` because the branch still holds commits
    /// it cannot see in HEAD. A squash-merged branch always looks like this: its
    /// commits were never replayed, only their content.
    public static func indicatesUnmergedBranch(_ stderr: String) -> Bool {
        stderr.contains("is not fully merged")
    }

    static func indicatesLockContention(_ stderr: String) -> Bool {
        // index.lock: "Another git process seems to be running in this repository"
        // ref/index .lock: "... Unable to create '/path/X.lock': File exists."
        stderr.contains("git process seems to be running")
            || stderr.contains(".lock': File exists")
    }
}
