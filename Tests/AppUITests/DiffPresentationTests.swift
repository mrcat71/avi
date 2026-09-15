import AppKit
@testable import AppUI
import GitKit
import Testing

@Suite("Diff presentation")
@MainActor
struct DiffPresentationTests {
    @Test func rulerDoesNotPaintOverAdjacentDocument() throws {
        _ = NSApplication.shared
        let scroll = NativeDiffTextView.makeScrollView()
        let ruler = try #require(scroll.verticalRulerView as? DiffLineRuler)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        ruler.frame = NSRect(x: 0, y: 0, width: 80, height: 200)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.magenta.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 200).fill()
        ruler.drawHashMarksAndLabels(in: NSRect(x: 0, y: 0, width: 300, height: 200))
        let outside = try #require(bitmap.colorAt(x: 150, y: 100)?.usingColorSpace(.deviceRGB))
        #expect(outside.redComponent > 0.95)
        #expect(outside.greenComponent < 0.05)
        #expect(outside.blueComponent > 0.95)
    }

    @Test func preservesLineNumbersAndChangeMarkers() {
        let diff = FileDiff(hunks: [DiffHunk(
            header: "@@ -1 +1 @@", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1,
            lines: [
                DiffLine(id: 0, kind: .deletion, text: "before", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(id: 1, kind: .addition, text: "after", oldLineNumber: nil, newLineNumber: 1)
            ]
        )], isBinary: false)
        let document = NativeDiffTextView.document(diff)
        #expect(document.string == "@@ -1 +1 @@\n- before\n+ after\n")
        let metadata = DiffDocument(diff)
        #expect(metadata.rows[1].oldLine == 1)
        #expect(metadata.rows[1].newLine == nil)
        #expect(metadata.rows[2].newLine == 1)
        let addition = (document.string as NSString).range(of: "+ after")
        #expect(document.attribute(.backgroundColor, at: addition.location, effectiveRange: nil) != nil)
    }

    @Test func emptyDocumentHasNoPlaceholderCode() {
        #expect(NativeDiffTextView.document(FileDiff(hunks: [], isBinary: false)).length == 0)
    }

    @Test func gutterOffsetsFollowUTF16AndExcludeEndOfDocument() {
        let diff = FileDiff(hunks: [DiffHunk(
            header: "@@ -12 +12,2 @@", oldStart: 12, oldCount: 1, newStart: 12, newCount: 2,
            lines: [
                DiffLine(id: 0, kind: .context, text: "let icon = \"🐈\"", oldLineNumber: 12, newLineNumber: 12),
                DiffLine(id: 1, kind: .addition, text: "let cafe = \"café\"", oldLineNumber: nil, newLineNumber: 13)
            ]
        )], isBinary: false)
        let document = DiffDocument(diff)
        let offset = (document.text as NSString).range(of: "+ let cafe").location
        #expect(document.row(containing: offset)?.newLine == 13)
        #expect(document.row(containing: offset - 1)?.newLine == 12)
        #expect(document.row(containing: -1) == nil)
        #expect(document.row(containing: document.text.utf16.count) == nil)
    }

    @Test func samePathCanSelectEitherSide() async {
        let store = RepositoryStore()
        let file = FileStatus(path: "file.swift", index: .modified, worktree: .modified)
        // No repository is opened: this tests selection identity without disk,
        // watchers, preferences, or Git mutations.
        await store.select(file, source: .staged)
        #expect(store.selectedPath == file.path)
        #expect(store.selectedDiffSource == .staged)
        await store.select(file, source: .unstaged)
        #expect(store.selectedDiffSource == .unstaged)
        await store.select(nil)
        #expect(store.selectedPath == nil)
        #expect(store.diff == nil)
    }
}
