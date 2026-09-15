import Foundation

/// Parses `git worktree list --porcelain`. Records are separated by a blank
/// line and always open with `worktree <path>`:
///
///     worktree /repo
///     HEAD <oid>
///     branch refs/heads/main
///
///     worktree /repo-feature
///     HEAD <oid>
///     detached
///     locked being rebased
public enum WorktreeParser {
    public static func parse(_ text: String) throws -> [Worktree] {
        var worktrees: [Worktree] = []
        for record in text.components(separatedBy: "\n\n") {
            let lines = record.split(separator: "\n").map(String.init)
            guard !lines.isEmpty else { continue }
            try worktrees.append(worktree(from: lines))
        }
        return worktrees
    }

    private static func worktree(from lines: [String]) throws -> Worktree {
        var path: URL?
        var headOID: String?
        var branch: String?
        var isBare = false
        var isLocked = false
        var lockReason: String?
        var isPrunable = false
        var prunableReason: String?

        for line in lines {
            let (keyword, value) = split(line)
            switch keyword {
            case "worktree":
                guard let value else { throw GitError.parseFailed(line) }
                path = URL(fileURLWithPath: value, isDirectory: true)
            case "HEAD":
                headOID = value
            case "branch":
                // Only refs/heads/* can be checked out into a worktree.
                branch = value.map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst("refs/heads/".count)) : $0 }
            case "detached":
                branch = nil
            case "bare":
                isBare = true
            case "locked":
                isLocked = true
                lockReason = value
            case "prunable":
                isPrunable = true
                prunableReason = value
            default:
                // Unknown attributes are data from a newer git, not an error.
                continue
            }
        }

        guard let path else { throw GitError.parseFailed(lines.joined(separator: "\n")) }
        return Worktree(
            path: path,
            headOID: headOID,
            branch: branch,
            isBare: isBare,
            isLocked: isLocked,
            lockReason: lockReason,
            isPrunable: isPrunable,
            prunableReason: prunableReason
        )
    }

    /// Splits `keyword value` where the value itself may contain spaces, and
    /// reports a bare keyword such as `detached` as a nil value.
    private static func split(_ line: String) -> (String, String?) {
        guard let separator = line.firstIndex(of: " ") else { return (line, nil) }
        let value = String(line[line.index(after: separator)...])
        return (String(line[..<separator]), value.isEmpty ? nil : value)
    }
}
