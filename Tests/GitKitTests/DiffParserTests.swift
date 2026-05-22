import Foundation
@testable import GitKit
import Testing

struct DiffParserTests {
    @Test func `parses single hunk with line numbers`() {
        let text = [
            "diff --git a/a.txt b/a.txt",
            "index 7898192..6178079 100644",
            "--- a/a.txt",
            "+++ b/a.txt",
            "@@ -1,2 +1,3 @@",
            " line1",
            "-line2",
            "+line2 changed",
            "+line3"
        ].joined(separator: "\n")

        let diff = DiffParser.parse(text)
        #expect(diff.isBinary == false)
        #expect(diff.hunks.count == 1)

        let hunk = diff.hunks[0]
        #expect(hunk.oldStart == 1 && hunk.oldCount == 2)
        #expect(hunk.newStart == 1 && hunk.newCount == 3)
        #expect(hunk.lines.map(\.kind) == [.context, .deletion, .addition, .addition])
        #expect(hunk.lines[0].oldLineNumber == 1 && hunk.lines[0].newLineNumber == 1)
        #expect(hunk.lines[1].oldLineNumber == 2 && hunk.lines[1].newLineNumber == nil)
        #expect(hunk.lines[2].oldLineNumber == nil && hunk.lines[2].newLineNumber == 2)
        #expect(hunk.lines[3].newLineNumber == 3)
        #expect(hunk.lines[1].text == "line2")
        #expect(hunk.lines[2].text == "line2 changed")
    }

    @Test func `parses multiple hunks`() {
        let text = [
            "@@ -1 +1 @@",
            "-a",
            "+A",
            "@@ -10,2 +10,2 @@",
            " ctx",
            "-old",
            "+new"
        ].joined(separator: "\n")

        let diff = DiffParser.parse(text)
        #expect(diff.hunks.count == 2)
        #expect(diff.hunks[0].oldStart == 1 && diff.hunks[0].oldCount == 1)
        #expect(diff.hunks[1].newStart == 10)
        #expect(diff.hunks[1].lines.map(\.kind) == [.context, .deletion, .addition])
    }

    @Test func `detects binary`() {
        let text = [
            "diff --git a/img.png b/img.png",
            "Binary files a/img.png and b/img.png differ"
        ].joined(separator: "\n")

        let diff = DiffParser.parse(text)
        #expect(diff.isBinary)
        #expect(diff.hunks.isEmpty)
    }

    @Test func `empty input yields no hunks`() {
        #expect(DiffParser.parse("").hunks.isEmpty)
        #expect(DiffParser.parse("").isEmpty)
    }
}
