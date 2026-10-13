@testable import GitKit
import Testing

struct ConflictDocumentTests {
    private let twoConflicts = """
    intro
    <<<<<<< HEAD
    mine 1
    =======
    theirs 1
    >>>>>>> feature
    middle
    <<<<<<< HEAD
    mine 2
    ||||||| base
    base 2
    =======
    theirs 2a
    theirs 2b
    >>>>>>> feature
    outro

    """

    @Test func splitsTheFileIntoCommonTextAndConflicts() throws {
        let document = try #require(ConflictDocument(text: twoConflicts))
        let conflicts = document.conflicts

        #expect(conflicts.count == 2)
        #expect(conflicts[0].currentLabel == "HEAD")
        #expect(conflicts[0].incomingLabel == "feature")
        #expect(conflicts[0].current == ["mine 1"])
        #expect(conflicts[0].incoming == ["theirs 1"])
        #expect(conflicts[0].base == nil)
        #expect(conflicts[0].startLine == 2)
        #expect(conflicts[1].baseLabel == "base")
        #expect(conflicts[1].base == ["base 2"])
        #expect(conflicts[1].incoming == ["theirs 2a", "theirs 2b"])
        #expect(conflicts[1].startLine == 8)
        #expect(document.segments.first == .common(["intro"]))
        #expect(document.segments.last == .common(["outro"]))
    }

    @Test func writesBackTheSameTextUntilSomethingIsResolved() throws {
        let document = try #require(ConflictDocument(text: twoConflicts))
        #expect(document.text == twoConflicts)
    }

    struct Resolving: Sendable, CustomTestStringConvertible {
        let resolution: ConflictDocument.Resolution
        let lines: [String]

        var testDescription: String {
            "\(resolution)"
        }
    }

    @Test(arguments: [
        Resolving(resolution: .current, lines: ["mine 1"]),
        Resolving(resolution: .incoming, lines: ["theirs 1"]),
        Resolving(resolution: .currentThenIncoming, lines: ["mine 1", "theirs 1"]),
        Resolving(resolution: .incomingThenCurrent, lines: ["theirs 1", "mine 1"])
    ])
    func resolvingOneConflictLeavesTheOtherAsItWas(_ item: Resolving) throws {
        let document = try #require(ConflictDocument(text: twoConflicts))

        let resolved = document.resolving(conflictAt: 0, with: item.resolution)

        let expected = (["intro"] + item.lines + ["middle"]).joined(separator: "\n") + "\n"
        #expect(resolved.text.hasPrefix(expected + "<<<<<<< HEAD\nmine 2\n||||||| base\n"))
        #expect(resolved.conflicts.count == 1)
        #expect(resolved.conflicts[0].startLine == 2 + item.lines.count + 1)
        // The text the sides agree on reads as one block again.
        #expect(resolved.segments.first == .common(["intro"] + item.lines + ["middle"]))
    }

    @Test func resolvingEveryConflictLeavesNoMarkers() throws {
        let document = try #require(ConflictDocument(text: twoConflicts))

        let resolved = document.resolving(conflictAt: 0, with: .incoming).resolving(conflictAt: 0, with: .current)

        #expect(resolved.text == "intro\ntheirs 1\nmiddle\nmine 2\noutro\n")
        #expect(resolved.conflicts.isEmpty)
    }

    @Test func keepsWindowsLineEndingsAndAMissingFinalNewline() throws {
        let text = "a\r\n<<<<<<< HEAD\r\nmine\r\n=======\r\ntheirs\r\n>>>>>>> topic\r\nb\r\n<<<<<<< HEAD\r\nx\r\n=======\r\ny\r\n>>>>>>> topic\r\nend"
        let document = try #require(ConflictDocument(text: text))
        #expect(document.conflicts.count == 2)
        #expect(document.conflicts[0].incomingLabel == "topic")
        #expect(document.text == text)

        let resolved = document.resolving(conflictAt: 0, with: .incoming)

        #expect(resolved.text == "a\r\ntheirs\r\nb\r\n<<<<<<< HEAD\r\nx\r\n=======\r\ny\r\n>>>>>>> topic\r\nend")
    }

    @Test(arguments: [
        // A conflict that never closes.
        "<<<<<<< HEAD\nmine\n=======\ntheirs\n",
        // A second separator inside one conflict.
        "<<<<<<< HEAD\nmine\n=======\ntheirs\n=======\nmore\n>>>>>>> topic\n",
        // A conflict opened inside another.
        "<<<<<<< HEAD\n<<<<<<< HEAD\nmine\n=======\ntheirs\n>>>>>>> topic\n"
    ])
    func refusesMarkersThatDoNotPairUp(_ text: String) {
        #expect(ConflictDocument(text: text) == nil)
    }

    /// Separators and closing markers outside a conflict are plain text, such
    /// as a Markdown heading underline.
    @Test func aFileWithoutOpeningMarkersHasNoConflicts() throws {
        let document = try #require(ConflictDocument(text: "Title\n=======\n>>>>>>> quote\n"))
        #expect(document.conflicts.isEmpty)
        #expect(document.text == "Title\n=======\n>>>>>>> quote\n")
    }
}
