import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

final class NativeDiffViewportTests: XCTestCase {
    func testInitialDocumentWaitsForNonzeroViewport() throws {
        try MainActor.assumeIsolated {
            for style in [NSScroller.Style.overlay, .legacy] {
                let scroll = makeScrollView(style: style)
                NativeDiffTextView.updateDocument(makeDiff(), in: scroll)
                resize(scroll, width: 900, height: 400)
                try assertDocumentStartsBesideRuler(scroll)
            }
        }
    }

    func testReplacingScrolledDocumentResetsBothAxesAndUpdatesRulerWidth() throws {
        try MainActor.assumeIsolated {
            let scroll = makeScrollView()
            resize(scroll, width: 900, height: 400)
            NativeDiffTextView.updateDocument(makeDiff(), in: scroll)
            for start in [10000, 1] {
                scroll.contentView.scroll(to: NSPoint(x: 300, y: 500))
                scroll.reflectScrolledClipView(scroll.contentView)
                NativeDiffTextView.updateDocument(makeDiff(start: start), in: scroll)
                scroll.layoutSubtreeIfNeeded()
                try assertDocumentStartsBesideRuler(scroll)
            }
        }
    }

    func testReplacementInCollapsedPaneResetsWhenPaneReopens() throws {
        try MainActor.assumeIsolated {
            let scroll = makeScrollView()
            resize(scroll, width: 900, height: 400)
            NativeDiffTextView.updateDocument(makeDiff(), in: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 300, y: 500))
            resize(scroll, width: 900, height: 0)
            NativeDiffTextView.updateDocument(makeDiff(start: 10000), in: scroll)
            resize(scroll, width: 600, height: 300)
            try assertDocumentStartsBesideRuler(scroll)
        }
    }

    func testUserScrollSurvivesRetilingAndResize() throws {
        try MainActor.assumeIsolated {
            let scroll = makeScrollView()
            NativeDiffTextView.updateDocument(makeDiff(), in: scroll)
            resize(scroll, width: 900, height: 400)
            try assertDocumentStartsBesideRuler(scroll)
            let ruler = try XCTUnwrap(scroll.verticalRulerView)
            let rulerX = ruler.frame.minX
            scroll.contentView.scroll(to: NSPoint(x: 300, y: 500))
            scroll.reflectScrolledClipView(scroll.contentView)
            for width in [500.0, 1200.0] {
                resize(scroll, width: width, height: 400)
                XCTAssertEqual(scroll.contentView.bounds.minX, 300, accuracy: 1)
                XCTAssertEqual(scroll.contentView.bounds.minY, 500, accuracy: 1)
                XCTAssertEqual(ruler.frame.minX, rulerX, accuracy: 1)
            }
        }
    }

    func testShortAndEmptyDocumentsDoNotKeepPreviousScrollOffset() throws {
        try MainActor.assumeIsolated {
            let scroll = makeScrollView()
            resize(scroll, width: 900, height: 400)
            NativeDiffTextView.updateDocument(makeDiff(), in: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 300, y: 500))
            let short = FileDiff(hunks: [DiffHunk(
                header: "@@ -1 +1 @@", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1,
                lines: [DiffLine(id: 0, kind: .addition, text: "short", oldLineNumber: nil, newLineNumber: 1)]
            )], isBinary: false)
            NativeDiffTextView.updateDocument(short, in: scroll)
            try assertDocumentStartsBesideRuler(scroll)
            NativeDiffTextView.updateDocument(FileDiff(hunks: [], isBinary: false), in: scroll)
            XCTAssertEqual((scroll.documentView as? NSTextView)?.string, "")
            NativeDiffTextView.updateDocument(short, in: scroll)
            try assertDocumentStartsBesideRuler(scroll)
        }
    }

    /// The real layout: the title row sits right above the gutter. Rendering the
    /// window must leave the title row free of the gutter's edge line.
    func testTitleRowAboveTheGutterStaysClean() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            // A one-letter title keeps glyphs away from the gutter edge column.
            let host = NSHostingView(rootView: FileDiffView(title: "x", diff: makeDiff()).frame(width: 600, height: 300))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let scroll = try XCTUnwrap(findScrollView(in: host))
            let ruler = try XCTUnwrap(scroll.verticalRulerView)
            // Invalidate generously, the way AppKit does when neighbours redraw.
            host.setNeedsDisplay(host.bounds)
            ruler.setNeedsDisplay(ruler.bounds.insetBy(dx: 0, dy: -60))
            window.displayIfNeeded()

            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let rulerEdge = ruler.convert(NSPoint(x: ruler.bounds.maxX - 1, y: 0), to: host)
            let rulerTop = ruler.convert(ruler.bounds, to: host)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            // Title row: from the top of the host down to the gutter's top edge.
            let titleRows = host.isFlipped ? (0 ..< Int(rulerTop.minY * scale) - 2) : (Int(rulerTop.maxY * scale) + 2 ..< bitmap.pixelsHigh)
            let edgeX = Int(rulerEdge.x * scale)
            let backgroundX = Int((rulerEdge.x + 40) * scale)
            var differing = 0
            for y in titleRows {
                // Row y in bitmap coordinates counts from the top.
                guard let edge = bitmap.colorAt(x: edgeX, y: y), let background = bitmap.colorAt(x: backgroundX, y: y) else { continue }
                if abs(edge.brightnessComponent - background.brightnessComponent) > 0.08 {
                    differing += 1
                }
            }
            XCTAssertLessThan(differing, 3, "a vertical line crosses the title row at the gutter edge")
        }
    }

    func testViewportResetAccountsForTopInset() {
        MainActor.assumeIsolated {
            let scroll = makeScrollView()
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
            NativeDiffTextView.updateDocument(makeDiff(), in: scroll)
            resize(scroll, width: 900, height: 400)
            XCTAssertEqual(scroll.contentView.bounds.minX, -scroll.contentView.contentInsets.left, accuracy: 1)
            XCTAssertEqual(scroll.contentView.bounds.minY, -scroll.contentView.contentInsets.top, accuracy: 1)
        }
    }
}

@MainActor private func makeScrollView(style: NSScroller.Style = .overlay) -> DiffScrollView {
    _ = NSApplication.shared
    let scroll = NativeDiffTextView.makeScrollView()
    scroll.scrollerStyle = style
    return scroll
}

@MainActor private func resize(_ scroll: NSScrollView, width: CGFloat, height: CGFloat) {
    scroll.frame = NSRect(x: 0, y: 0, width: width, height: height)
    scroll.tile()
    scroll.layoutSubtreeIfNeeded()
}

@MainActor private func assertDocumentStartsBesideRuler(
    _ scroll: NSScrollView, file: StaticString = #filePath, line: UInt = #line
) throws {
    let text = try XCTUnwrap(scroll.documentView as? NSTextView)
    let ruler = try XCTUnwrap(scroll.verticalRulerView)
    let layout = try XCTUnwrap(text.layoutManager)
    let container = try XCTUnwrap(text.textContainer)
    layout.ensureLayout(for: container)
    let firstGlyph = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
        .offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
    let visibleGlyph = scroll.convert(firstGlyph, from: text)
    XCTAssertGreaterThan(scroll.contentView.bounds.height, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(visibleGlyph.minX, ruler.frame.maxX, file: file, line: line)
    XCTAssertLessThan(visibleGlyph.minX, ruler.frame.maxX + 24, file: file, line: line)
    XCTAssertGreaterThanOrEqual(visibleGlyph.minY, 0, file: file, line: line)
    XCTAssertLessThan(visibleGlyph.minY, 12, file: file, line: line)
    XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: 0), file: file, line: line)
    XCTAssertTrue(text.isSelectable, file: file, line: line)
    XCTAssertFalse(text.isEditable, file: file, line: line)
    XCTAssertTrue(text.usesFindBar, file: file, line: line)
    XCTAssertTrue(text.string.hasPrefix("@@ -"), file: file, line: line)
}

private func makeDiff(start: Int = 1) -> FileDiff {
    FileDiff(hunks: [DiffHunk(
        header: "@@ -\(start),100 +\(start),100 @@", oldStart: start, oldCount: 100,
        newStart: start, newCount: 100,
        lines: (0 ..< 100).map { index in
            DiffLine(id: index, kind: .addition,
                     text: "FIRST \(index) " + String(repeating: "long line ", count: 100),
                     oldLineNumber: nil, newLineNumber: start + index)
        }
    )], isBinary: false)
}

@MainActor private func findScrollView(in view: NSView) -> DiffScrollView? {
    if let scroll = view as? DiffScrollView {
        return scroll
    }
    for child in view.subviews {
        if let found = findScrollView(in: child) {
            return found
        }
    }
    return nil
}
