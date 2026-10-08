@testable import AppUI
@testable import GitKit
import Testing

struct FolderSelectionTests {
    /// Folders: Sources (with AppUI/Views and Style under it), docs.
    private static let entries = [
        "Sources/AppUI/Views/A.swift",
        "Sources/AppUI/Views/B.swift",
        "Sources/AppUI/Style/Tokens.swift",
        "Sources/Root.swift",
        "docs/design.md",
        "README.md"
    ].map { FileStatus(path: $0, index: .unmodified, worktree: .modified) }

    private static let sources: Set<String> = [
        "Sources", "Sources/AppUI", "Sources/AppUI/Views", "Sources/AppUI/Style",
        "Sources/AppUI/Views/A.swift", "Sources/AppUI/Views/B.swift",
        "Sources/AppUI/Style/Tokens.swift", "Sources/Root.swift"
    ]

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let old: Set<String>
        let new: Set<String>
        var isToggle = false
        let expected: Set<String>

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(name: "clicking a folder selects everything inside it", old: [], new: ["Sources"], expected: sources),
        Case(
            name: "a nested folder brings only its own files",
            old: [], new: ["Sources/AppUI/Views"],
            expected: ["Sources/AppUI/Views", "Sources/AppUI/Views/A.swift", "Sources/AppUI/Views/B.swift"]
        ),
        Case(name: "a file click after a folder keeps just that file", old: sources, new: ["Sources/Root.swift"], expected: ["Sources/Root.swift"]),
        Case(name: "clicking a selected folder again keeps its files", old: sources, new: ["Sources"], expected: sources),
        Case(
            name: "Command-clicking the folder off takes its contents off",
            old: sources.union(["README.md"]), new: sources.union(["README.md"]).subtracting(["Sources"]), isToggle: true,
            expected: ["README.md"]
        ),
        Case(
            name: "Command-clicking one file off keeps the rest",
            old: sources, new: sources.subtracting(["Sources/Root.swift"]), isToggle: true,
            expected: sources.subtracting(["Sources/Root.swift"])
        ),
        Case(
            name: "Command-clicking a folder on keeps what was there",
            old: ["README.md"], new: ["README.md", "docs"], isToggle: true,
            expected: ["README.md", "docs", "docs/design.md"]
        ),
        Case(
            name: "a Shift-click range brings the folders in it along",
            old: ["README.md"], new: ["README.md", "docs", "Sources/AppUI/Style"],
            expected: ["README.md", "docs", "docs/design.md", "Sources/AppUI/Style", "Sources/AppUI/Style/Tokens.swift"]
        ),
        Case(name: "selecting files alone changes nothing", old: [], new: ["README.md"], expected: ["README.md"])
    ]

    @Test(arguments: cases)
    func apply(_ testCase: Case) {
        let result = FolderSelection.apply(
            old: testCase.old, new: testCase.new, entries: Self.entries,
            fileTag: { $0 }, folderTag: { $0 }, isToggle: testCase.isToggle
        )
        #expect(result == testCase.expected)
    }

    @Test func prefixedTagsWorkTheSame() {
        let result = FolderSelection.apply(
            old: [], new: ["dir:docs"], entries: Self.entries, fileTag: { "f:" + $0 }, folderTag: { "dir:" + $0 }
        )
        #expect(result == ["dir:docs", "f:docs/design.md"])
    }

    @Test func aFolderDoesNotClaimASiblingWithTheSamePrefix() {
        let entries = ["App/a.swift", "AppTests/b.swift"].map { FileStatus(path: $0, index: .unmodified, worktree: .modified) }
        #expect(FolderSelection.files(in: "App", entries: entries).map(\.path) == ["App/a.swift"])
    }
}
