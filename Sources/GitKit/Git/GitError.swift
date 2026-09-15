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
    static func indicatesLockContention(_ stderr: String) -> Bool {
        // index.lock: "Another git process seems to be running in this repository"
        // ref/index .lock: "... Unable to create '/path/X.lock': File exists."
        stderr.contains("git process seems to be running")
            || stderr.contains(".lock': File exists")
    }
}
