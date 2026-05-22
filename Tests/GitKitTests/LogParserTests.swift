import Foundation
@testable import GitKit
import Testing

struct LogParserTests {
    @Test func `parses nul delimited commits`() throws {
        let first = [
            "2222222222222222222222222222222222222222",
            "1111111111111111111111111111111111111111",
            "Avi Test",
            "test@example.com",
            "2026-05-20T12:34:56Z",
            "second commit",
            "body line"
        ].joined(separator: "\u{1F}")
        let second = [
            "1111111111111111111111111111111111111111",
            "",
            "Avi Test",
            "test@example.com",
            "2026-05-19T10:00:00Z",
            "first commit",
            ""
        ].joined(separator: "\u{1F}")
        let raw = first + "\u{0}" + second + "\u{0}"

        let commits = try LogParser.parse(Data(raw.utf8))

        #expect(commits.count == 2)
        #expect(commits[0].subject == "second commit")
        #expect(commits[0].parentOIDs == ["1111111111111111111111111111111111111111"])
        #expect(commits[0].body == "body line")
        #expect(commits[1].parentOIDs.isEmpty)
    }
}
