import Foundation

/// Parses the NUL-record, unit-separator-field format produced by
/// `git log --pretty=format:...`.
public enum LogParser {
    private static let fieldSeparator = Character("\u{1F}")

    public static func parse(_ data: Data) throws -> [CommitSummary] {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return try records.map { record in
            guard let rawText = String(data: Data(record), encoding: .utf8) else {
                throw GitError.parseFailed("history contains non-UTF-8 data")
            }
            let text = rawText.trimmingCharacters(in: .newlines)

            let fields = text.split(separator: fieldSeparator, maxSplits: 6, omittingEmptySubsequences: false)
            guard fields.count == 7 else {
                throw GitError.parseFailed(text)
            }

            let dateText = String(fields[4])
            let authorDate = formatter.date(from: dateText) ?? ISO8601DateFormatter().date(from: dateText)
            guard let authorDate else {
                throw GitError.parseFailed("invalid author date: \(dateText)")
            }

            let parents = String(fields[1])
                .split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)

            return CommitSummary(
                oid: String(fields[0]),
                parentOIDs: parents,
                authorName: String(fields[2]),
                authorEmail: String(fields[3]),
                authorDate: authorDate,
                subject: String(fields[5]),
                body: String(fields[6]).trimmingCharacters(in: .newlines)
            )
        }
    }
}
