import AppKit
import GitKit

extension DiffDocument {
    /// A run of consecutive added or removed rows.
    struct ChangeRun: Equatable {
        let rows: Range<Int>
        let kind: DiffLine.Kind
    }

    /// Added and removed rows, merged into runs of the same kind. Hunk
    /// headers, context, and side-by-side filler rows are not changes.
    func changeRuns() -> [ChangeRun] {
        var runs: [ChangeRun] = []
        for (index, row) in rows.enumerated() where !row.isFiller {
            guard let kind = row.kind, kind == .addition || kind == .deletion else { continue }
            if let last = runs.last, last.kind == kind, last.rows.upperBound == index {
                runs[runs.count - 1] = ChangeRun(rows: last.rows.lowerBound ..< index + 1, kind: kind)
            } else {
                runs.append(ChangeRun(rows: index ..< index + 1, kind: kind))
            }
        }
        return runs
    }
}

/// A strip along the diff's right edge, under the vertical scroller, that
/// marks where the whole file adds lines (green) and removes them (red), so
/// the changes outside the visible part are easy to find. The strip spans
/// the same height as the scroller's track and maps the document onto it
/// the same way, so a mark sits level with the knob when its lines are on
/// screen. It never takes clicks: text selection and the scroller keep
/// working underneath and above it.
final class DiffChangeOverview: NSView {
    static let width: CGFloat = 6
    /// A one-line change in a long file still gets a visible mark.
    static let minimumMarkHeight: CGFloat = 2

    var document: DiffDocument? {
        didSet {
            runs = document?.changeRuns() ?? []
            needsDisplay = true
        }
    }

    private(set) var runs: [DiffDocument.ChangeRun] = []
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        // Views stopped clipping to their bounds by default in macOS 14;
        // never paint marks over the neighbouring text.
        clipsToBounds = true
        setAccessibilityElement(false)
        // Wrapping, the font size, and a new document change the text's
        // height, and with it where each change lands on the strip.
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(textFrameChanged), name: NSView.frameDidChangeNotification, object: textView
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("DiffChangeOverview does not support NSCoder")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    @objc private func textFrameChanged() {
        needsDisplay = true
    }

    /// Each run's top and bottom on the strip. The document maps onto the
    /// strip's height like it maps onto the scroller's track; a document
    /// shorter than the strip is drawn at its real size, level with its lines.
    func markRects() -> [(rect: NSRect, kind: DiffLine.Kind)] {
        guard !runs.isEmpty, let document, let textView,
              let layout = textView.layoutManager,
              let storage = textView.textStorage,
              bounds.height > 0 else { return [] }
        let glyphCount = layout.numberOfGlyphs
        guard glyphCount > 0 else { return [] }
        let origin = textView.textContainerOrigin
        let scale = bounds.height / max(textView.frame.height, bounds.height)
        var result: [(rect: NSRect, kind: DiffLine.Kind)] = []
        result.reserveCapacity(runs.count)
        for run in runs {
            let first = document.rows[run.rows.lowerBound].range
            let last = document.rows[run.rows.upperBound - 1].range
            // The text and the document are replaced together; skip a run
            // that the text on show does not have yet.
            guard NSMaxRange(last) <= storage.length, last.length > 0 else { continue }
            let firstGlyph = layout.glyphIndexForCharacter(at: first.location)
            // A row ends with its newline, which sits on the row's last fragment.
            let lastGlyph = layout.glyphIndexForCharacter(at: NSMaxRange(last) - 1)
            guard firstGlyph < glyphCount, lastGlyph < glyphCount else { continue }
            let top = origin.y + layout.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil).minY
            let bottom = origin.y + layout.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil).maxY
            let height = max(Self.minimumMarkHeight, (bottom - top) * scale)
            let y = min(top * scale, bounds.height - height)
            result.append((NSRect(x: 1, y: y, width: bounds.width - 2, height: height), run.kind))
        }
        return result
    }

    override func draw(_: NSRect) {
        for mark in markRects() {
            let color = mark.kind == .addition ? NSColor.systemGreen : NSColor.systemRed
            color.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: mark.rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}
