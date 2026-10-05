import Foundation

/// Parses `git log --follow --name-status -z` run with the format
/// `<RS>%H<US>%P<US>%an<US>%ae<US>%aI<US>%s<US>%b<GS>`. Each record is one
/// commit: the header up to the group separator, then NUL-separated
/// name-status fields for the followed file (`M path`, or `R100 old new`).
public enum FileHistoryParser {
    static let format = "%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%b%x1d"

    /// `path` is the file's current name. A commit that lists no change for it,
    /// such as a merge, keeps the name the newer commits ended with.
    public static func parse(_ data: Data, path: String) throws -> [FileHistoryEntry] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var currentPath = path
        var entries: [FileHistoryEntry] = []

        for record in data.split(separator: 0x1E, omittingEmptySubsequences: true) {
            guard let headerEnd = record.firstIndex(of: 0x1D) else {
                // Output before the first record, such as a stray newline.
                if record.allSatisfy({ $0 == 0x0A || $0 == 0 }) {
                    continue
                }
                throw GitError.parseFailed("file history record without a header end")
            }
            guard let header = String(data: Data(record[record.startIndex ..< headerEnd]), encoding: .utf8) else {
                throw GitError.parseFailed("file history contains non-UTF-8 data")
            }
            let commit = try parseCommit(header, formatter: formatter)
            let tokens = try record[record.index(after: headerEnd)...]
                .split(separator: 0, omittingEmptySubsequences: true)
                .map { field -> String in
                    guard let text = String(data: Data(field), encoding: .utf8) else {
                        throw GitError.parseFailed("file history contains a non-UTF-8 path")
                    }
                    return text
                }
            let entry = entry(for: commit, tokens: tokens, currentPath: currentPath)
            entries.append(entry)
            currentPath = entry.oldPath ?? entry.path
        }
        return entries
    }

    private static func entry(for commit: CommitSummary, tokens: [String], currentPath: String) -> FileHistoryEntry {
        // The status field follows the header's NUL and newline.
        guard let status = tokens.first?.trimmingCharacters(in: .newlines), !status.isEmpty else {
            return FileHistoryEntry(commit: commit, path: currentPath, kind: .unknown)
        }
        let kind = CommitFileChangeKind(statusToken: status)
        if kind == .renamed || kind == .copied, tokens.count >= 3 {
            return FileHistoryEntry(commit: commit, path: tokens[2], oldPath: tokens[1], kind: kind)
        }
        return FileHistoryEntry(commit: commit, path: tokens.count >= 2 ? tokens[1] : currentPath, kind: kind)
    }

    private static func parseCommit(_ header: String, formatter: ISO8601DateFormatter) throws -> CommitSummary {
        let fields = header.split(separator: "\u{1F}", maxSplits: 6, omittingEmptySubsequences: false)
        guard fields.count == 7 else {
            throw GitError.parseFailed(header)
        }
        let dateText = String(fields[4])
        guard let date = formatter.date(from: dateText) ?? ISO8601DateFormatter().date(from: dateText) else {
            throw GitError.parseFailed("invalid author date: \(dateText)")
        }
        return CommitSummary(
            oid: String(fields[0]),
            parentOIDs: fields[1].split(separator: " ").map(String.init),
            authorName: String(fields[2]),
            authorEmail: String(fields[3]),
            authorDate: date,
            subject: String(fields[5]),
            body: String(fields[6]).trimmingCharacters(in: .newlines)
        )
    }
}
