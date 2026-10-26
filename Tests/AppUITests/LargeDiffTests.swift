import AppKit
@testable import AppUI
import GitKit
import Testing

struct LargeDiffTests {
    @Test @MainActor func rendersLargeAddition() {
        let document = DiffDocument(additions((0 ..< 8000).map { "let value\($0) = \"Zoë 👋 名前\" // " + String(repeating: "text ", count: 12) }))
        let start = ContinuousClock.now
        let rendered = NativeDiffTextView.attributedText(document, display: DiffDisplay(path: "large.swift"))
        print("Large addition rendering: \(start.duration(to: .now))")
        #expect(rendered.string == document.text)
    }

    @Test @MainActor func rendersLargeReplacement() {
        let document = DiffDocument(replacement())
        let start = ContinuousClock.now
        let rendered = NativeDiffTextView.attributedText(document, display: DiffDisplay(path: "large.swift"))
        print("Large replacement rendering: \(start.duration(to: .now))")
        #expect(rendered.string == document.text)
    }

    @Test @MainActor func wordHighlightingIsBoundedInBothLayouts() throws {
        let diff = replacement()
        let document = DiffDocument(diff)
        let unified = NativeDiffTextView.wordHighlights(document)
        #expect(!unified.isEmpty)
        #expect(unified.count < 2000)
        let last = try #require(document.rows.last)
        #expect(!unified.contains { NSIntersectionRange($0.range, last.range).length > 0 })

        let sides = DiffDocument.sideBySide(diff)
        let words = NativeDiffTextView.sideBySideWordHighlights(old: sides.old, new: sides.new)
        #expect(!words.old.isEmpty && !words.new.isEmpty)
        #expect(words.old.count + words.new.count == unified.count)
        let lastNewRow = try #require(sides.new.rows.last)
        #expect(!words.new.contains { NSIntersectionRange($0.range, lastNewRow.range).length > 0 })
    }

    @Test @MainActor func syntaxFallsBackToPlainTextForLargeDocuments() throws {
        let line = "let value = \"" + String(repeating: "x", count: 1000) + "\""
        let document = DiffDocument(additions(Array(repeating: line, count: 1000)))
        #expect(document.text.utf16.count > SyntaxHighlighter.maximumDocumentLength)
        let rendered = NativeDiffTextView.attributedText(document, display: DiffDisplay(path: "large.swift"))
        #expect(rendered.string == document.text)
        let row = document.rows[1]
        let color = try #require(rendered.attribute(.foregroundColor, at: row.range.location + 2, effectiveRange: nil) as? NSColor)
        #expect(color == NSColor.textColor)
        #expect(rendered.attribute(.backgroundColor, at: row.range.location, effectiveRange: nil) != nil)
    }

    @Test @MainActor func largeDiffRetainsNativeTextAndGuttersInBothLayouts() throws {
        _ = NSApplication.shared
        let diff = replacement()
        let document = DiffDocument(diff)
        let scroll = NativeDiffTextView.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        NativeDiffTextView.updateDocument(diff, in: scroll)
        let text = try #require(scroll.documentView as? NSTextView)
        #expect(text.string == document.text)
        #expect(text.isSelectable && text.usesFindBar && !text.isEditable)
        #expect((scroll.verticalRulerView as? DiffLineRuler)?.document?.rows.last?.newLine == 1000)

        let container = SideBySideDiffContainer()
        container.frame = scroll.frame
        container.show(diff, display: DiffDisplay(path: "large.swift"), resetPosition: true)
        let sides = DiffDocument.sideBySide(diff)
        let panes = container.arrangedSubviews.compactMap { $0 as? DiffScrollView }
        #expect(panes.count == 2)
        #expect((panes.first?.documentView as? NSTextView)?.string == sides.old.text)
        #expect((panes.last?.documentView as? NSTextView)?.string == sides.new.text)
    }

    private func replacement() -> FileDiff {
        let old = String(repeating: "value + ", count: 65) + "before"
        let new = String(repeating: "value + ", count: 65) + "after"
        let lines = (0 ..< 1000).map { DiffLine(id: $0, kind: .deletion, text: old, oldLineNumber: $0 + 1, newLineNumber: nil) }
            + (0 ..< 1000).map { DiffLine(id: $0 + 1000, kind: .addition, text: new, oldLineNumber: nil, newLineNumber: $0 + 1) }
        return FileDiff(hunks: [DiffHunk(
            header: "@@ -1,1000 +1,1000 @@", oldStart: 1, oldCount: 1000, newStart: 1, newCount: 1000, lines: lines
        )], isBinary: false)
    }

    @Test func extractsEveryUnicodeLineFromALargeDocument() {
        let lines = (0 ..< 8000).map { "let value\($0) = \"Zoë 👋 名前\" // " + String(repeating: "text ", count: 12) }
        let document = DiffDocument(additions(lines))
        let start = ContinuousClock.now
        let extracted = lines.indices.map { document.lineText(ofRow: $0 + 1) }
        print("Large diff line extraction: \(start.duration(to: .now))")
        #expect(extracted == lines)
    }

    private func additions(_ lines: [String]) -> FileDiff {
        FileDiff(hunks: [DiffHunk(
            header: "@@ -0,0 +1,\(lines.count) @@", oldStart: 0, oldCount: 0,
            newStart: 1, newCount: lines.count,
            lines: lines.enumerated().map { index, line in
                DiffLine(id: index, kind: .addition, text: line, oldLineNumber: nil, newLineNumber: index + 1)
            }
        )], isBinary: false)
    }
}
