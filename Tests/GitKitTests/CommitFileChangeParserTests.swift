import Foundation
@testable import GitKit
import Testing

struct CommitFileChangeParserTests {
    @Test func `parses ordinary and rename records`() throws {
        let raw = [
            "M",
            "modified.txt",
            "A",
            "added.txt",
            "R100",
            "old.txt",
            "new.txt",
            ""
        ].joined(separator: "\u{0}")

        let changes = try CommitFileChangeParser.parse(Data(raw.utf8))

        #expect(changes.count == 3)
        #expect(changes[0] == CommitFileChange(path: "modified.txt", kind: .modified))
        #expect(changes[1] == CommitFileChange(path: "added.txt", kind: .added))
        #expect(changes[2] == CommitFileChange(path: "new.txt", oldPath: "old.txt", kind: .renamed))
    }
}
