import AppKit

/// A fixed gutter, independent of the selectable and horizontally scrolling text.
final class DiffLineRuler: NSRulerView {
    var document: DiffDocument? {
        didSet {
            let maximum = document?.rows.flatMap { [$0.oldLine, $0.newLine].compactMap { $0 } }.max() ?? 1
            columnWidth = max(36, CGFloat(String(maximum).count) * 8 + 12)
            ruleThickness = columnWidth * 2 + 8
            needsDisplay = true
        }
    }

    private var columnWidth: CGFloat = 36
    override var isFlipped: Bool {
        true
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 80
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("DiffLineRuler does not support NSCoder")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func viewportChanged() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // AppKit can supply a dirty region wider than the ruler itself. Never
        // paint its background over the neighbouring document view.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        NSColor.windowBackgroundColor.setFill()
        rect.intersection(bounds).fill()
        guard let textView = clientView as? NSTextView,
              let layout = textView.layoutManager,
              let container = textView.textContainer,
              let document else { return }
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        layout.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, range, _ in
            guard let row = document.row(containing: layout.characterIndexForGlyph(at: range.location)) else { return }
            let point = self.convert(NSPoint(x: origin.x, y: origin.y + fragment.minY), from: textView)
            for (index, value) in [row.oldLine, row.newLine].enumerated() {
                guard let value else { continue }
                let label = String(value) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: CGFloat(index + 1) * self.columnWidth - size.width, y: point.y + (fragment.height - size.height) / 2), withAttributes: attributes)
            }
        }
    }
}
