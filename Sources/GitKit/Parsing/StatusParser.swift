import Foundation

/// Parses NUL-delimited `git status --porcelain=v2 --branch -z` output into a
/// `WorkingCopyStatus` (branch summary + changed entries).
///
/// Record formats (fields are space-separated within a record):
///   # branch.<key> <value>                                  (branch headers)
///   1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
///   2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <Xscore> <path>   (origPath follows as its own NUL field)
///   u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
///   ? <path>
///   ! <path>
public enum StatusParser {
    public static func parse(_ data: Data) throws -> WorkingCopyStatus {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var entries: [FileStatus] = []
        var name: String?
        var oid: String?
        var upstream: String?
        var ahead = 0
        var behind = 0

        var i = 0
        while i < fields.count {
            guard let field = String(data: Data(fields[i]), encoding: .utf8), let marker = field.first else {
                i += 1
                continue
            }
            switch marker {
            case "#":
                parseBranchHeader(field, name: &name, oid: &oid, upstream: &upstream, ahead: &ahead, behind: &behind)
                i += 1
            case "1":
                try entries.append(parseChanged(field, hasRenameScore: false, originalPath: nil))
                i += 1
            case "2":
                let next = i + 1 < fields.count ? String(data: Data(fields[i + 1]), encoding: .utf8) : nil
                try entries.append(parseChanged(field, hasRenameScore: true, originalPath: next))
                i += 2
            case "u":
                try entries.append(parseUnmerged(field))
                i += 1
            case "?":
                entries.append(FileStatus(path: pathAfterMarker(field), index: .unmodified, worktree: .untracked))
                i += 1
            case "!":
                entries.append(FileStatus(path: pathAfterMarker(field), index: .ignored, worktree: .ignored))
                i += 1
            default:
                i += 1
            }
        }

        let branch = BranchInfo(name: name, oid: oid, upstream: upstream, ahead: ahead, behind: behind)
        return WorkingCopyStatus(branch: branch, entries: entries)
    }

    private static func parseBranchHeader(
        _ field: String,
        name: inout String?,
        oid: inout String?,
        upstream: inout String?,
        ahead: inout Int,
        behind: inout Int
    ) {
        // e.g. "# branch.head main", "# branch.ab +1 -2"
        let parts = field.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return }
        let value = String(parts[2])
        switch parts[1] {
        case "branch.oid":
            oid = (value == "(initial)") ? nil : value
        case "branch.head":
            name = (value == "(detached)") ? nil : value
        case "branch.upstream":
            upstream = value
        case "branch.ab":
            for token in value.split(separator: " ") {
                if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
                else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
            }
        default:
            break
        }
    }

    /// Handles both ordinary (type 1) and rename/copy (type 2) records.
    private static func parseChanged(_ field: String, hasRenameScore: Bool, originalPath: String?) throws -> FileStatus {
        let pathIndex = hasRenameScore ? 9 : 8
        let parts = field.split(separator: " ", maxSplits: pathIndex, omittingEmptySubsequences: false)
        guard parts.count == pathIndex + 1, parts[1].count == 2 else {
            throw GitError.parseFailed(field)
        }
        let xy = Array(parts[1])
        return FileStatus(
            path: String(parts[pathIndex]),
            originalPath: originalPath,
            index: state(xy[0]),
            worktree: state(xy[1])
        )
    }

    private static func parseUnmerged(_ field: String) throws -> FileStatus {
        let parts = field.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard parts.count == 11, parts[1].count == 2 else {
            throw GitError.parseFailed(field)
        }
        let xy = Array(parts[1])
        return FileStatus(path: String(parts[10]), index: state(xy[0]), worktree: state(xy[1]))
    }

    private static func pathAfterMarker(_ field: String) -> String {
        String(field.dropFirst(2))
    }

    private static func state(_ c: Character) -> FileState {
        switch c {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        case "U": return .updatedButUnmerged
        case "?": return .untracked
        case "!": return .ignored
        default: return .unmodified
        }
    }
}
