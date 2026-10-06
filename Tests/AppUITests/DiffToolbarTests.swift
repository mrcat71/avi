import AppKit
@testable import AppUI
import Foundation
import GitKit
import Testing

@MainActor
@Suite("Diff toolbar")
struct DiffToolbarTests {
    private func line(_ id: Int, _ kind: DiffLine.Kind, _ text: String, old: Int?, new: Int?) -> DiffLine {
        DiffLine(id: id, kind: kind, text: text, oldLineNumber: old, newLineNumber: new)
    }

    /// Removed lines face added ones, context faces itself, and the shorter
    /// side of a change gets blank rows, so both sides stay level.
    @Test func sideBySideKeepsBothSidesLevel() {
        let diff = FileDiff(hunks: [
            DiffHunk(header: "@@ -1,4 +1,5 @@", oldStart: 1, oldCount: 4, newStart: 1, newCount: 5, lines: [
                line(0, .context, "a", old: 1, new: 1),
                line(1, .deletion, "b", old: 2, new: nil),
                line(2, .deletion, "c", old: 3, new: nil),
                line(3, .addition, "B", old: nil, new: 2),
                line(4, .context, "d", old: 4, new: 3),
                line(5, .addition, "e", old: nil, new: 4),
                line(6, .addition, "f", old: nil, new: 5),
                line(7, .noNewline, "No newline at end of file", old: nil, new: nil)
            ])
        ], isBinary: false)
        let (old, new) = DiffDocument.sideBySide(diff)
        #expect(old.rows.count == new.rows.count)

        func texts(_ document: DiffDocument) -> [String] {
            document.text.components(separatedBy: "\n").dropLast().map { $0 }
        }
        #expect(texts(old) == ["@@ -1,4 +1,5 @@", "  a", "- b", "- c", "  d", "", "", ""])
        #expect(texts(new) == ["@@ -1,4 +1,5 @@", "  a", "+ B", "", "  d", "+ e", "+ f", "\\ No newline at end of file"])
        #expect(old.rows.map { $0.oldLine } == [nil, 1, 2, 3, 4, nil, nil, nil])
        #expect(new.rows.map { $0.newLine } == [nil, 1, 2, nil, 3, 4, 5, nil])
        #expect(new.rows.map { $0.isFiller } == [false, false, false, true, false, false, false, false])
    }

    @Test(arguments: [(3, -1, 1), (3, 1, 5), (0, -1, 0), (100, 1, 100), (4, -1, 3), (4, 1, 5), (7, 1, 10)])
    func contextStepsThroughTheLadder(from: Int, direction: Int, expected: Int) {
        #expect(DiffPreferences.step(from: from, by: direction) == expected)
    }

    @Test func choicesPersistAndBecomeGitOptions() throws {
        let name = "avi-diff-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let first = DiffPreferences(defaults: defaults)
        #expect(first.gitOptions == .standard)
        first.ignoreWhitespace = true
        first.showMoreLines()
        first.sideBySide = true

        let again = DiffPreferences(defaults: defaults)
        #expect(again.gitOptions == DiffOptions(contextLines: 5, ignoreWhitespace: true))
        #expect(again.sideBySide)
        again.wholeFile = true
        #expect(again.canShowMoreLines == false && again.canShowFewerLines == false)
    }

    /// TextKit alone leaves tabs and line ends blank; Avi draws marks for them.
    @Test func invisibleTabsAndLineEndsGetMarks() {
        func darkPixels(showing: Bool) -> Int {
            let storage = NSTextStorage(string: "\t\n", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
            let layout = InvisiblesLayoutManager()
            layout.showsInvisibles = showing
            let container = NSTextContainer(size: NSSize(width: 200, height: 60))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 60, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            // The marks use a system colour; in Dark Mode it is white, which
            // would vanish on this white bitmap.
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 200, height: 60).fill()
                layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: .zero)
            }
            NSGraphicsContext.restoreGraphicsState()
            var dark = 0
            for x in 0 ..< 200 {
                for y in 0 ..< 60 where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.9 {
                    dark += 1
                }
            }
            return dark
        }
        #expect(darkPixels(showing: false) == 0)
        #expect(darkPixels(showing: true) > 0)
        #expect(InvisiblesLayoutManager.mark(for: 0x09) == "\u{2192}")
        #expect(InvisiblesLayoutManager.mark(for: 0x41) == nil)
    }
}
