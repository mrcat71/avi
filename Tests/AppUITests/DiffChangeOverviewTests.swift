import AppKit
@testable import AppUI
import GitKit
import Testing

@Suite("Diff change overview")
@MainActor
struct DiffChangeOverviewTests {
    @Test func mergesAdjacentChangesOfTheSameKind() {
        let document = DiffDocument(Self.diff([
            .context, .deletion, .deletion, .addition, .context, .addition, .noNewline, .addition
        ]))
        // Row 0 is the hunk header.
        #expect(document.changeRuns() == [
            .init(rows: 2 ..< 4, kind: .deletion),
            .init(rows: 4 ..< 5, kind: .addition),
            .init(rows: 6 ..< 7, kind: .addition),
            .init(rows: 8 ..< 9, kind: .addition)
        ])
    }

    @Test func sideBySideFillerIsNotAChange() {
        let documents = DiffDocument.sideBySide(Self.diff([.deletion, .addition, .addition, .context]))
        #expect(documents.old.changeRuns() == [.init(rows: 1 ..< 2, kind: .deletion)])
        #expect(documents.new.changeRuns() == [.init(rows: 1 ..< 3, kind: .addition)])
    }

    @Test func stripSitsAtTheRightEdgeAndPassesClicksThrough() throws {
        for style in [NSScroller.Style.overlay, .legacy] {
            let scroll = Self.scrollView(style: style)
            NativeDiffTextView.updateDocument(Self.diff([.deletion, .addition]), in: scroll)
            let overview = try #require(scroll.changeOverview)
            let clip = scroll.convert(scroll.contentView.bounds, from: scroll.contentView)
            #expect(overview.frame.width == DiffChangeOverview.width)
            #expect(abs(overview.frame.maxX - clip.maxX) < 0.5)
            #expect(abs(overview.frame.height - clip.height) < 0.5)
            #expect(overview.hitTest(NSPoint(x: overview.frame.midX, y: overview.frame.midY)) == nil)
            // Above the text, below the scrollers.
            let order = scroll.subviews
            let overviewIndex = try #require(order.firstIndex { $0 === overview })
            let clipIndex = try #require(order.firstIndex { $0 === scroll.contentView })
            #expect(overviewIndex > clipIndex)
            if let scroller = scroll.verticalScroller, let scrollerIndex = order.firstIndex(where: { $0 === scroller }) {
                #expect(overviewIndex < scrollerIndex)
            }
        }
    }

    @Test func shortDocumentMarksSitLevelWithTheirLines() throws {
        let scroll = Self.scrollView()
        NativeDiffTextView.updateDocument(Self.diff([.context, .deletion, .deletion, .context, .addition]), in: scroll)
        let overview = try #require(scroll.changeOverview)
        let text = try #require(scroll.documentView as? NSTextView)
        let layout = try #require(text.layoutManager)
        layout.ensureLayout(for: try #require(text.textContainer))
        let marks = overview.markRects()
        #expect(marks.map { $0.kind } == [.deletion, .addition])
        let document = try #require(scroll.document)
        let deletion = document.rows[2].range
        let lineTop = text.textContainerOrigin.y + layout.lineFragmentRect(
            forGlyphAt: layout.glyphIndexForCharacter(at: deletion.location), effectiveRange: nil
        ).minY
        #expect(abs(marks[0].rect.minY - lineTop) < 0.5)
        #expect(marks[0].rect.height > marks[1].rect.height)
    }

    @Test func longDocumentFitsOnTheStripWithVisibleMarks() throws {
        let scroll = Self.scrollView()
        // A single added line at the end of a long file.
        NativeDiffTextView.updateDocument(Self.diff(Array(repeating: .context, count: 2000) + [.addition]), in: scroll)
        let overview = try #require(scroll.changeOverview)
        let text = try #require(scroll.documentView as? NSTextView)
        text.layoutManager?.ensureLayout(for: try #require(text.textContainer))
        let marks = overview.markRects()
        #expect(marks.count == 1)
        let mark = try #require(marks.first)
        #expect(mark.rect.height >= DiffChangeOverview.minimumMarkHeight)
        #expect(mark.rect.maxY <= overview.bounds.height + 0.5)
        #expect(mark.rect.minY > overview.bounds.height * 0.9)
    }

    @Test func drawsGreenAndRedMarks() throws {
        let scroll = Self.scrollView()
        NativeDiffTextView.updateDocument(Self.diff([.deletion, .deletion, .deletion, .context, .addition, .addition, .addition]), in: scroll)
        let overview = try #require(scroll.changeOverview)
        let text = try #require(scroll.documentView as? NSTextView)
        text.layoutManager?.ensureLayout(for: try #require(text.textContainer))
        let marks = overview.markRects()
        let bitmap = try #require(overview.bitmapImageRepForCachingDisplay(in: overview.bounds))
        overview.cacheDisplay(in: overview.bounds, to: bitmap)
        let factor = CGFloat(bitmap.pixelsWide) / overview.bounds.width
        func color(at y: CGFloat) throws -> NSColor {
            try #require(bitmap.colorAt(x: Int(overview.bounds.midX * factor), y: Int(y * factor))?.usingColorSpace(.deviceRGB))
        }
        let red = try color(at: marks[0].rect.midY)
        let green = try color(at: marks[1].rect.midY)
        let empty = try color(at: overview.bounds.height - 4)
        #expect(red.alphaComponent > 0.5 && red.redComponent > red.greenComponent)
        #expect(green.alphaComponent > 0.5 && green.greenComponent > green.redComponent)
        #expect(empty.alphaComponent < 0.1)
    }

    private static func scrollView(style: NSScroller.Style = .overlay) -> DiffScrollView {
        _ = NSApplication.shared
        let scroll = NativeDiffTextView.makeScrollView()
        scroll.scrollerStyle = style
        scroll.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        scroll.tile()
        scroll.layoutSubtreeIfNeeded()
        return scroll
    }

    private static func diff(_ kinds: [DiffLine.Kind]) -> FileDiff {
        var old = 0
        var new = 0
        let lines: [DiffLine] = kinds.enumerated().map { index, kind in
            if kind == .context || kind == .deletion { old += 1 }
            if kind == .context || kind == .addition { new += 1 }
            return DiffLine(
                id: index, kind: kind, text: kind == .noNewline ? "No newline at end of file" : "line \(index)",
                oldLineNumber: kind == .addition || kind == .noNewline ? nil : old,
                newLineNumber: kind == .deletion || kind == .noNewline ? nil : new
            )
        }
        return FileDiff(hunks: [DiffHunk(
            header: "@@ -1,\(old) +1,\(new) @@", oldStart: 1, oldCount: old, newStart: 1, newCount: new, lines: lines
        )], isBinary: false)
    }
}
