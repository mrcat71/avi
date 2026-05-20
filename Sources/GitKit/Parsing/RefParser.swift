import Foundation

/// Parses NUL-record, unit-separator-field output from `git for-each-ref`.
public enum RefParser {
    private static let fieldSeparator = Character("\u{1F}")

    public static func parse(_ data: Data) throws -> RepositoryRefs {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var localBranches: [GitReference] = []
        var remoteBranches: [GitReference] = []
        var tags: [GitReference] = []

        for record in records {
            guard let rawText = String(data: Data(record), encoding: .utf8) else {
                throw GitError.parseFailed("ref record contains non-UTF-8 data")
            }

            let text = rawText.trimmingCharacters(in: .newlines)
            guard !text.isEmpty else { continue }

            let fields = text.split(separator: fieldSeparator, maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5 else {
                throw GitError.parseFailed(text)
            }

            let fullName = String(fields[0])
            let oid = String(fields[1])
            let upstream = String(fields[2]).nilIfEmpty
            let isCurrent = String(fields[3]) == "*"
            let subject = String(fields[4]).nilIfEmpty

            if fullName.hasPrefix("refs/heads/") {
                localBranches.append(GitReference(
                    name: String(fullName.dropFirst("refs/heads/".count)),
                    fullName: fullName,
                    oid: oid,
                    kind: .localBranch,
                    upstream: upstream,
                    isCurrent: isCurrent,
                    subject: subject
                ))
            } else if fullName.hasPrefix("refs/remotes/") {
                let name = String(fullName.dropFirst("refs/remotes/".count))
                guard !name.hasSuffix("/HEAD") else { continue }
                remoteBranches.append(GitReference(
                    name: name,
                    fullName: fullName,
                    oid: oid,
                    kind: .remoteBranch,
                    upstream: upstream,
                    isCurrent: false,
                    subject: subject
                ))
            } else if fullName.hasPrefix("refs/tags/") {
                tags.append(GitReference(
                    name: String(fullName.dropFirst("refs/tags/".count)),
                    fullName: fullName,
                    oid: oid,
                    kind: .tag,
                    upstream: nil,
                    isCurrent: false,
                    subject: subject
                ))
            }
        }

        return RepositoryRefs(
            localBranches: localBranches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            remoteBranches: remoteBranches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            tags: tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
