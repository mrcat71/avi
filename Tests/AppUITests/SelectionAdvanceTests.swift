@testable import AppUI
import Testing

struct SelectionAdvanceTests {
    struct Case: Sendable {
        let name: String
        let order: [String]
        let acted: Set<String>
        let surviving: Set<String>
        let expected: String?
    }

    static let cases: [Case] = [
        Case(
            name: "middle file advances to the next one below",
            order: ["a", "b", "c", "d"], acted: ["b"], surviving: ["a", "c", "d"], expected: "c"
        ),
        Case(
            name: "first file advances to the next",
            order: ["a", "b", "c"], acted: ["a"], surviving: ["b", "c"], expected: "b"
        ),
        Case(
            name: "last file falls back to the previous one",
            order: ["a", "b", "c"], acted: ["c"], surviving: ["a", "b"], expected: "b"
        ),
        Case(
            name: "acting on everything clears the selection",
            order: ["a", "b"], acted: ["a", "b"], surviving: [], expected: nil
        ),
        Case(
            name: "a contiguous block advances to the file after it",
            order: ["a", "b", "c", "d"], acted: ["b", "c"], surviving: ["a", "d"], expected: "d"
        ),
        Case(
            name: "a trailing block falls back above the block",
            order: ["a", "b", "c", "d"], acted: ["c", "d"], surviving: ["a", "b"], expected: "b"
        ),
        Case(
            name: "scattered selection anchors on the last acted index",
            order: ["a", "b", "c", "d", "e"], acted: ["b", "d"], surviving: ["a", "c", "e"], expected: "e"
        ),
        Case(
            name: "a non-surviving neighbour is skipped",
            order: ["a", "b", "c", "d"], acted: ["a"], surviving: ["c", "d"], expected: "c"
        ),
        Case(
            name: "empty acted set yields nil",
            order: ["a", "b"], acted: [], surviving: ["a", "b"], expected: nil
        )
    ]

    @Test(arguments: cases)
    func advancesToExpectedNeighbour(_ testCase: Case) {
        let result = nextSelection(
            visibleOrder: testCase.order,
            acted: testCase.acted,
            surviving: testCase.surviving
        )
        #expect(result == testCase.expected, "\(testCase.name)")
    }
}
