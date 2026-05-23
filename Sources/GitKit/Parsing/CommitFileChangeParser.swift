import Foundation

/// Parses NUL-delimited `git diff-tree --name-status -z` output.
public enum CommitFileChangeParser {
    public static func parse(_ data: Data) throws -> [CommitFileChange] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
        var changes: [CommitFileChange] = []
        var index = 0

        while index < fields.count {
            guard let status = String(data: Data(fields[index]), encoding: .utf8) else {
                throw GitError.parseFailed("file change status contains non-UTF-8 data")
            }
            index += 1

            let kind = CommitFileChangeKind(statusToken: status)
            switch kind {
            case .renamed, .copied:
                guard index + 1 < fields.count,
                      let oldPath = String(data: Data(fields[index]), encoding: .utf8),
                      let newPath = String(data: Data(fields[index + 1]), encoding: .utf8) else {
                    throw GitError.parseFailed("missing paths for \(status)")
                }
                changes.append(CommitFileChange(path: newPath, oldPath: oldPath, kind: kind))
                index += 2
            default:
                guard index < fields.count,
                      let path = String(data: Data(fields[index]), encoding: .utf8) else {
                    throw GitError.parseFailed("missing path for \(status)")
                }
                changes.append(CommitFileChange(path: path, kind: kind))
                index += 1
            }
        }

        return changes
    }
}
