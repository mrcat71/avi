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
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` failed (exit \(exitCode))" + (detail.isEmpty ? "" : ": \(detail)")
        case let .invalidInput(detail):
            return detail
        case let .parseFailed(detail):
            return "Failed to parse git output: \(detail)"
        }
    }
}
