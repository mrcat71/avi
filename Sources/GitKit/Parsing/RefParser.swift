import Foundation

/// Parses NUL-record, unit-separator-field output from `git for-each-ref`.
///
/// Expected format string (8 fields):
/// `%(refname)<US>%(objectname)<US>%(upstream:short)<US>%(upstream:track)<US>%(HEAD)<US>%(subject)<US>%(taggerdate:iso-strict)<US>%(contents:subject)<NUL>`
public enum RefParser {
    private static let fieldSeparator = Character("\u{1F}")
    private static let trackingRegex = try! NSRegularExpression(
        pattern: #"ahead\s+(\d+)|behind\s+(\d+)|(gone)"#,
        options: []
    )

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

            let fields = text.split(separator: fieldSeparator, maxSplits: 7, omittingEmptySubsequences: false)
            guard fields.count == 8 else {
                throw GitError.parseFailed(text)
            }

            let fullName = String(fields[0])
            let oid = String(fields[1])
            let upstream = String(fields[2]).nilIfEmpty
            let trackingText = String(fields[3])
            let isCurrent = String(fields[4]) == "*"
            let subject = String(fields[5]).nilIfEmpty
            let taggerDateText = String(fields[6])
            let annotatedSubject = String(fields[7]).nilIfEmpty

            let tracking = parseTracking(trackingText)

            if fullName.hasPrefix("refs/heads/") {
                localBranches.append(GitReference(
                    name: String(fullName.dropFirst("refs/heads/".count)),
                    fullName: fullName,
                    oid: oid,
                    kind: .localBranch,
                    upstream: upstream,
                    isCurrent: isCurrent,
                    subject: subject,
                    ahead: tracking.ahead,
                    behind: tracking.behind,
                    isUpstreamGone: tracking.gone
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
                let isAnnotated = !taggerDateText.isEmpty
                tags.append(GitReference(
                    name: String(fullName.dropFirst("refs/tags/".count)),
                    fullName: fullName,
                    oid: oid,
                    kind: .tag,
                    upstream: nil,
                    isCurrent: false,
                    subject: subject,
                    taggerDate: isAnnotated ? parseIsoDate(taggerDateText) : nil,
                    annotatedMessage: isAnnotated ? annotatedSubject : nil
                ))
            }
        }

        return RepositoryRefs(
            localBranches: localBranches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            remoteBranches: remoteBranches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            tags: tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    struct Tracking {
        var ahead: Int?
        var behind: Int?
        var gone: Bool = false
    }

    static func parseTracking(_ text: String) -> Tracking {
        var result = Tracking()
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        guard !trimmed.isEmpty else { return result }

        let nsText = trimmed as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = trackingRegex.matches(in: trimmed, options: [], range: range)
        for match in matches {
            if match.range(at: 1).location != NSNotFound {
                result.ahead = Int(nsText.substring(with: match.range(at: 1)))
            } else if match.range(at: 2).location != NSNotFound {
                result.behind = Int(nsText.substring(with: match.range(at: 2)))
            } else if match.range(at: 3).location != NSNotFound {
                result.gone = true
            }
        }
        return result
    }

    private static func parseIsoDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
