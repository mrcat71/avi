@testable import AppUI
import Testing

struct AISplitParserTests {
    @Test func parsesPlainJSON() throws {
        let raw = """
        {
          "groups": [
            { "files": ["a.swift", "b.swift"], "message": "feat: add A" },
            { "files": ["c.md"], "message": "docs: explain A" }
          ]
        }
        """
        let groups = try AISplitParser.parse(raw)
        #expect(groups.count == 2)
        #expect(groups[0].files == ["a.swift", "b.swift"])
        #expect(groups[0].message == "feat: add A")
        #expect(groups[1].files == ["c.md"])
        #expect(groups[1].message == "docs: explain A")
    }

    @Test func parsesJSONInsideMarkdownFence() throws {
        let raw = """
        Here is the split:

        ```json
        {
          "groups": [
            { "files": ["x"], "message": "chore: x" }
          ]
        }
        ```

        Let me know if you want changes.
        """
        let groups = try AISplitParser.parse(raw)
        #expect(groups.count == 1)
        #expect(groups[0].files == ["x"])
        #expect(groups[0].message == "chore: x")
    }

    @Test func parsesJSONInGenericFence() throws {
        let raw = """
        ```
        {"groups": [{"files": ["a"], "message": "fix: a"}]}
        ```
        """
        let groups = try AISplitParser.parse(raw)
        #expect(groups.count == 1)
        #expect(groups[0].message == "fix: a")
    }

    @Test func parsesJSONWithSurroundingProse() throws {
        let raw = """
        Sure! Based on the diff, I propose:

        {"groups": [{"files": ["a"], "message": "feat: a"}]}

        Hope this helps.
        """
        let groups = try AISplitParser.parse(raw)
        #expect(groups.count == 1)
        #expect(groups[0].message == "feat: a")
    }

    @Test func trimsWhitespaceInMessages() throws {
        let raw = #"{"groups": [{"files": ["a"], "message": "  feat: a  \n\n"}]}"#
        let groups = try AISplitParser.parse(raw)
        #expect(groups[0].message == "feat: a")
    }

    @Test func throwsWhenNoJSON() {
        let raw = "Sorry, I cannot split this diff."
        #expect(throws: AISplitParseError.self) {
            _ = try AISplitParser.parse(raw)
        }
    }

    @Test func throwsWhenJSONIsMalformed() {
        let raw = "{ this is not json }"
        #expect(throws: AISplitParseError.self) {
            _ = try AISplitParser.parse(raw)
        }
    }

    @Test func throwsWhenGroupsIsEmpty() {
        let raw = #"{"groups": []}"#
        #expect(throws: AISplitParseError.self) {
            _ = try AISplitParser.parse(raw)
        }
    }
}
