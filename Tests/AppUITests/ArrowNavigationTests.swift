@testable import AppUI
import GitKit
import Testing

struct ArrowNavigationTests {
    struct Case: Sendable {
        let name: String
        let direction: ArrowDirection
        let selection: Set<String>
        let expected: String?
    }

    /// A changed-files tree as the list shows it: folders come before the files in them.
    static let rows = [
        "Sources", "Sources/App", "Sources/App/a.swift", "Sources/App/b.swift",
        "Sources/Kit", "Sources/Kit/c.swift", "README.md"
    ]
    static let files: Set<String> = ["Sources/App/a.swift", "Sources/App/b.swift", "Sources/Kit/c.swift", "README.md"]

    static let cases: [Case] = [
        Case(name: "down with nothing selected picks the first file, past its folders", direction: .down, selection: [], expected: "Sources/App/a.swift"),
        Case(name: "up with nothing selected picks the last file", direction: .up, selection: [], expected: "README.md"),
        Case(name: "down moves to the next file", direction: .down, selection: ["Sources/App/a.swift"], expected: "Sources/App/b.swift"),
        Case(name: "down steps over a folder row", direction: .down, selection: ["Sources/App/b.swift"], expected: "Sources/Kit/c.swift"),
        Case(name: "up steps over a folder row", direction: .up, selection: ["Sources/Kit/c.swift"], expected: "Sources/App/b.swift"),
        Case(name: "down on the last file stays put", direction: .down, selection: ["README.md"], expected: nil),
        Case(name: "up on the first file stays put, with only folders above it", direction: .up, selection: ["Sources/App/a.swift"], expected: nil),
        Case(name: "down from a selected folder picks the file below it", direction: .down, selection: ["Sources/Kit"], expected: "Sources/Kit/c.swift"),
        Case(name: "up from a selected folder picks the file above it", direction: .up, selection: ["Sources/Kit"], expected: "Sources/App/b.swift"),
        Case(name: "down from several files starts after the last of them", direction: .down, selection: ["Sources/App/a.swift", "Sources/App/b.swift"], expected: "Sources/Kit/c.swift"),
        Case(name: "up from several files starts before the first of them", direction: .up, selection: ["Sources/App/b.swift", "README.md"], expected: "Sources/App/a.swift"),
        Case(name: "a selection the list no longer shows counts as none", direction: .down, selection: ["gone.swift"], expected: "Sources/App/a.swift")
    ]

    @Test(arguments: cases)
    func movesFromFileToFile(_ testCase: Case) {
        let target = arrowTarget(moving: testCase.direction, rows: Self.rows, files: Self.files, selection: testCase.selection)
        #expect(target == testCase.expected, "\(testCase.name)")
    }

    @Test func commitHeadingsArePassedOverToo() {
        let rows = ["s:staged", "dir:docs", "f:docs/x.md", "d:1", "f:README.md"]
        let files: Set = ["f:docs/x.md", "f:README.md"]

        #expect(arrowTarget(moving: .down, rows: rows, files: files, selection: ["s:staged"]) == "f:docs/x.md")
        #expect(arrowTarget(moving: .down, rows: rows, files: files, selection: ["f:docs/x.md"]) == "f:README.md")
        #expect(arrowTarget(moving: .up, rows: rows, files: files, selection: ["f:README.md"]) == "f:docs/x.md")
        #expect(arrowTarget(moving: .up, rows: rows, files: files, selection: ["f:docs/x.md"]) == nil)
    }

    @Test func anEmptyListHasNowhereToGo() {
        #expect(arrowTarget(moving: .down, rows: [], files: [], selection: []) == nil)
        #expect(arrowTarget(moving: .up, rows: ["dir:docs"], files: [], selection: []) == nil)
    }

    @Test func visibleRowsFollowTheListLayout() {
        let entries = [
            FileStatus(path: "Sources/App/a.swift", index: .unmodified, worktree: .modified),
            FileStatus(path: "README.md", index: .unmodified, worktree: .modified),
            FileStatus(path: "Sources/Kit/c.swift", index: .unmodified, worktree: .modified),
            FileStatus(path: "Sources/App/b.swift", index: .unmodified, worktree: .untracked)
        ]
        let expanded = FileTreeBuilder.allFolderIds(for: entries)

        #expect(FileTreeBuilder.visibleRows(entries, expanded: expanded, tree: false) == entries.map(\.path))
        #expect(FileTreeBuilder.visibleRows(entries, expanded: expanded, tree: true) == Self.rows)
        // A collapsed folder keeps its row and hides its files.
        #expect(FileTreeBuilder.visibleRows(entries, expanded: expanded.subtracting(["Sources/App"]), tree: true)
            == ["Sources", "Sources/App", "Sources/Kit", "Sources/Kit/c.swift", "README.md"])
    }
}
