import AppKit
import GitKit
import SwiftUI

/// A read-only document rather than independent row labels: selection, copying,
/// horizontal scrolling, and the standard macOS find bar work across hunks.
struct NativeDiffTextView: NSViewRepresentable {
    let diff: FileDiff

    func makeNSView(context _: Context) -> DiffScrollView {
        Self.makeScrollView()
    }

    static func makeScrollView() -> DiffScrollView {
        let scroll = DiffScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        // The gutter uses NSLayoutManager coordinates. Create a matching TextKit 1
        // view explicitly rather than switching a TextKit 2 view during drawing.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let text = NSTextView(frame: .zero, textContainer: container)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = true
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = text.maxSize
        text.textContainer?.widthTracksTextView = false
        text.textContainerInset = NSSize(width: 12, height: 8)
        text.backgroundColor = .textBackgroundColor
        text.setAccessibilityLabel("File diff")
        scroll.documentView = text
        scroll.verticalRulerView = DiffLineRuler(scrollView: scroll, textView: text)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: DiffScrollView, context: Context) {
        guard context.coordinator.diff != diff else { return }
        context.coordinator.diff = diff
        Self.updateDocument(diff, in: scroll)
    }

    static func updateDocument(_ diff: FileDiff, in scroll: DiffScrollView) {
        guard let text = scroll.documentView as? NSTextView else { return }
        text.textStorage?.setAttributedString(document(diff))
        (scroll.verticalRulerView as? DiffLineRuler)?.document = DiffDocument(diff)
        text.setSelectedRange(NSRange(location: 0, length: 0))
        scroll.resetDocumentPosition()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var diff: FileDiff?
    }

    static func document(_ diff: FileDiff) -> NSAttributedString {
        let document = DiffDocument(diff)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 19
        paragraph.lineBreakMode = .byClipping
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph
        ]
        let result = NSMutableAttributedString(string: document.text, attributes: base)
        for row in document.rows {
            var attributes: [NSAttributedString.Key: Any] = [:]
            switch row.kind {
            case .addition:
                attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.14)
            case .deletion:
                attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.14)
            case nil:
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.08)
            case .context, .noNewline: break
            }
            result.addAttributes(attributes, range: row.range)
        }
        return result
    }
}

final class DiffScrollView: NSScrollView {
    private var needsDocumentPositionReset = false

    func resetDocumentPosition() {
        needsDocumentPositionReset = true
        tile()
    }

    override func tile() {
        super.tile()
        // SwiftUI may install the document before assigning the panel a size.
        // Scrolling to a glyph at that point leaves its prefix under the ruler.
        guard needsDocumentPositionReset,
              contentView.bounds.width > contentView.contentInsets.left + contentView.contentInsets.right,
              contentView.bounds.height > contentView.contentInsets.top + contentView.contentInsets.bottom,
              let text = documentView as? NSTextView else { return }
        needsDocumentPositionReset = false
        text.scrollRangeToVisible(NSRange(location: 0, length: 0))
        // AppKit can overlay rulers inside the clip view. Its top-left origin
        // then includes negative insets, rather than being (0, 0).
        contentView.scroll(to: NSPoint(x: -contentView.contentInsets.left, y: -contentView.contentInsets.top))
        reflectScrolledClipView(contentView)
    }
}
