import Foundation
@testable import GitKit
import Testing

/// Parser-only tests with canned porcelain v2 bytes, independent of the installed git version.
struct StatusParserTests {
    @Test func parsesOrdinaryAndRenameRecords() throws {
        let raw = [
            "# branch.head main",
            "1 .M N... 100644 100644 100644 0000000 1111111 modified.txt",
            "2 R. N... 100644 100644 100644 0000000 1111111 R100 new.txt",
            "old.txt",
            "? untracked.txt",
            ""
        ].joined(separator: "\u{0}")

        let status = try StatusParser.parse(Data(raw.utf8))
        #expect(status.branch.name == "main")
        #expect(status.entries.count == 3)

        let modified = try #require(status.entries.first { $0.path == "modified.txt" })
        #expect(modified.worktree == .modified)
        #expect(modified.index == .unmodified)

        let renamed = try #require(status.entries.first { $0.path == "new.txt" })
        #expect(renamed.index == .renamed)
        #expect(renamed.originalPath == "old.txt")

        let untracked = try #require(status.entries.first { $0.path == "untracked.txt" })
        #expect(untracked.isUntracked)
    }

    @Test func emptyInputYieldsNoEntries() throws {
        #expect(try StatusParser.parse(Data()).entries.isEmpty)
    }
}
