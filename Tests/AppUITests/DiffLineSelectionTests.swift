@testable import AppUI
import Foundation
@testable import GitKit
import Testing

@MainActor
struct DiffLineSelectionTests {
    /// One hunk: context, a removal, two additions, context; then a second
    /// hunk with one addition.
    private static let diff = FileDiff(hunks: [
        DiffHunk(header: "@@ -1,3 +1,4 @@", oldStart: 1, oldCount: 3, newStart: 1, newCount: 4, lines: [
            DiffLine(id: 0, kind: .context, text: "one", oldLineNumber: 1, newLineNumber: 1),
            DiffLine(id: 1, kind: .deletion, text: "two", oldLineNumber: 2, newLineNumber: nil),
            DiffLine(id: 2, kind: .addition, text: "TWO", oldLineNumber: nil, newLineNumber: 2),
            DiffLine(id: 3, kind: .addition, text: "two and a half", oldLineNumber: nil, newLineNumber: 3),
            DiffLine(id: 4, kind: .context, text: "three", oldLineNumber: 3, newLineNumber: 4)
        ]),
        DiffHunk(header: "@@ -20,2 +21,3 @@", oldStart: 20, oldCount: 2, newStart: 21, newCount: 3, lines: [
            DiffLine(id: 5, kind: .context, text: "twenty", oldLineNumber: 20, newLineNumber: 21),
            DiffLine(id: 6, kind: .addition, text: "new", oldLineNumber: nil, newLineNumber: 22),
            DiffLine(id: 7, kind: .context, text: "twenty-one", oldLineNumber: 21, newLineNumber: 23)
        ])
    ], isBinary: false)

    private static let document = DiffDocument(diff)

    /// Rows: 0 header, 1 one, 2 -two, 3 +TWO, 4 +two and a half, 5 three,
    /// 6 header, 7 twenty, 8 +new, 9 twenty-one.
    private func range(rows: ClosedRange<Int>) -> NSRange {
        let first = Self.document.rows[rows.lowerBound].range
        let last = Self.document.rows[rows.upperBound].range
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    @Test func selectingLinesPicksTheChangesTheyTouch() {
        let picked = Self.document.lineKeys(in: range(rows: 2 ... 3))
        #expect(picked.keys == [DiffLineKey(side: .removed, number: 2), DiffLineKey(side: .added, number: 2)])
        #expect(!picked.isHunk)
    }

    @Test func aSelectionEndingAtTheNextRowsStartDoesNotPickIt() {
        let row = Self.document.rows[3].range
        let picked = Self.document.lineKeys(in: NSRange(location: row.location, length: row.length))
        #expect(picked.keys == [DiffLineKey(side: .added, number: 2)])
    }

    @Test func selectingOnlyContextPicksNothing() {
        #expect(Self.document.lineKeys(in: range(rows: 1 ... 1)).keys.isEmpty)
    }

    @Test func aCaretPicksItsWholeHunk() {
        let caret = NSRange(location: Self.document.rows[7].range.location + 2, length: 0)
        let picked = Self.document.lineKeys(in: caret)
        #expect(picked.keys == [DiffLineKey(side: .added, number: 22)])
        #expect(picked.isHunk)
    }

    @Test func aCaretOnAHunkHeaderPicksThatHunk() {
        let picked = Self.document.lineKeys(in: NSRange(location: 0, length: 0))
        #expect(picked.keys.count == 3)
        #expect(picked.isHunk)
    }

    @Test func stagingPickedLinesAppliesAForwardPatchToTheIndex() async throws {
        let provider = Fixtures.dirty()
        provider.fileDiffs["README.md"] = Self.diff
        let store = RepositoryStore(git: provider)
        await store.open(URL(fileURLWithPath: "/tmp/avi-line-actions"))
        await store.refresh()
        let file = try #require(store.entries.first { $0.path == "README.md" })

        await store.applyLines(.stage, keys: [DiffLineKey(side: .added, number: 22)], file: file)

        let applied = try #require(provider.appliedPatches.first)
        #expect(applied.toIndex && !applied.reverse)
        #expect(applied.patch.contains("+new"))
        #expect(!applied.patch.contains("TWO"))
    }

    @Test func discardingPickedLinesReversesThemInTheWorkingTree() async throws {
        let provider = Fixtures.dirty()
        provider.fileDiffs["README.md"] = Self.diff
        let store = RepositoryStore(git: provider)
        await store.open(URL(fileURLWithPath: "/tmp/avi-line-actions"))
        await store.refresh()
        let file = try #require(store.entries.first { $0.path == "README.md" })

        await store.applyLines(.discard, keys: [DiffLineKey(side: .added, number: 2)], file: file)

        let applied = try #require(provider.appliedPatches.first)
        #expect(!applied.toIndex && applied.reverse)
        #expect(applied.patch.contains("+TWO"))
        // The other addition stays: a reverse patch keeps it as context.
        #expect(applied.patch.contains(" two and a half"))
    }
}
