import Foundation

/// Parses `git blame --porcelain`. Each line starts with a header
/// `<oid> <original line> <final line> [<lines in group>]`; the first time a
/// commit appears, `key value` lines describing it follow; the line's content
/// comes last, after a tab.
public enum BlameParser {
    public static func parse(_ data: Data) throws -> [BlameLine] {
        // A file in another encoding still blames; its odd bytes show as U+FFFD.
        let text = String(decoding: data, as: UTF8.self)
        var commits: [String: CommitFields] = [:]
        var lines: [BlameLine] = []
        var current: (oid: String, line: Int)?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if rawLine.hasPrefix("\t") {
                guard let header = current else {
                    throw GitError.parseFailed("blame content without a header")
                }
                let fields = commits[header.oid] ?? CommitFields()
                lines.append(BlameLine(
                    lineNumber: header.line,
                    content: String(rawLine.dropFirst()),
                    commit: fields.commit(oid: header.oid)
                ))
                current = nil
                continue
            }
            guard !rawLine.isEmpty else { continue }
            if current == nil {
                let parts = rawLine.split(separator: " ")
                guard parts.count >= 3, let finalLine = Int(parts[2]), isOID(parts[0]) else {
                    throw GitError.parseFailed("unexpected blame header: \(rawLine)")
                }
                current = (String(parts[0]), finalLine)
                continue
            }
            guard let oid = current?.oid else { continue }
            let pair = rawLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair[0])
            let value = pair.count > 1 ? String(pair[1]) : ""
            commits[oid, default: CommitFields()].set(key, value)
        }
        return lines
    }

    private static func isOID(_ value: Substring) -> Bool {
        (value.count == 40 || value.count == 64) && value.allSatisfy(\.isHexDigit)
    }

    private struct CommitFields {
        var author = ""
        var email = ""
        var time: TimeInterval?
        var summary = ""

        mutating func set(_ key: String, _ value: String) {
            switch key {
            case "author": author = value
            case "author-mail": email = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            case "author-time": time = TimeInterval(value)
            case "summary": summary = value
            default: break
            }
        }

        func commit(oid: String) -> BlameCommit {
            BlameCommit(
                oid: oid,
                author: author,
                authorEmail: email,
                authorDate: time.map { Date(timeIntervalSince1970: $0) },
                summary: summary
            )
        }
    }
}
