import AppKit
import GitKit
import SwiftUI

/// How a diff document is drawn: wrapped or scrolling sideways, with or
/// without marks for invisible characters, in the Diff font, and colored
/// for the file's language.
struct DiffDisplay: Equatable {
    var wrapsLines = false
    var showsInvisibles = false
    /// Settings > Appearance > Diff font; empty is the system monospaced font.
    var fontFamily = ""
    var fontSize: CGFloat = 12
    /// The file's path, which picks the syntax colors.
    var path = ""

    var font: NSFont {
        Self.codeFont(family: fontFamily, size: fontSize)
    }

    /// The Diff font at `size`, or the system monospaced font when the
    /// family is empty, "SF Mono", or not installed.
    static func codeFont(family: String, size: CGFloat) -> NSFont {
        let trimmed = family.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("SF Mono") == .orderedSame {
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFontManager.shared.font(withFamily: trimmed, traits: [], weight: 5, size: size)
            ?? NSFont(name: trimmed, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var lineHeight: CGFloat {
        (fontSize * 1.6).rounded()
    }
}

/// A read-only document rather than independent row labels: selection, copying,
/// horizontal scrolling, and the standard macOS find bar work across hunks.
struct NativeDiffTextView: NSViewRepresentable {
    let diff: FileDiff
    var display = DiffDisplay()
    /// Staging picked lines, in the Changes view only.
    var lineActions: DiffLineActions?

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
        let layout = InvisiblesLayoutManager()
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
        scroll.observeForLineActions()
        return scroll
    }

    func updateNSView(_ scroll: DiffScrollView, context: Context) {
        scroll.lineActions = lineActions
        let coordinator = context.coordinator
        guard coordinator.diff != diff || coordinator.display != display else { return }
        let diffChanged = coordinator.diff != diff
        coordinator.diff = diff
        coordinator.display = display
        Self.apply(display, to: scroll)
        // After staging or discarding lines, the same file reloads: stay put.
        let keepsPosition = scroll.takeKeepsPosition()
        Self.show(DiffDocument(diff), in: scroll, display: display, resetPosition: diffChanged && !keepsPosition)
    }

    /// Shows `diff` from its top, unwrapped and without invisible characters.
    static func updateDocument(_ diff: FileDiff, in scroll: DiffScrollView) {
        show(DiffDocument(diff), in: scroll, display: DiffDisplay(), resetPosition: true)
    }

    /// Puts `document` in the scroll view, keeping the scroll position unless
    /// a different file came in. `words` overrides the word highlights, for
    /// one side of a side-by-side diff.
    static func show(
        _ document: DiffDocument,
        in scroll: DiffScrollView,
        display: DiffDisplay,
        resetPosition: Bool,
        words: [WordHighlight]? = nil
    ) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let caret = min(text.selectedRange().location, (document.text as NSString).length)
        text.textStorage?.setAttributedString(attributedText(document, display: display, words: words))
        (scroll.verticalRulerView as? DiffLineRuler)?.fontSize = display.fontSize
        (scroll.verticalRulerView as? DiffLineRuler)?.document = document
        scroll.document = document
        if resetPosition {
            text.setSelectedRange(NSRange(location: 0, length: 0))
            scroll.resetDocumentPosition()
        } else {
            text.setSelectedRange(NSRange(location: caret, length: 0))
        }
        scroll.updateLineActionBar()
    }

    /// Wrapped lines follow the pane's width; unwrapped ones scroll sideways.
    static func apply(_ display: DiffDisplay, to scroll: DiffScrollView) {
        guard let text = scroll.documentView as? NSTextView, let container = text.textContainer else { return }
        if let layout = text.layoutManager as? InvisiblesLayoutManager, layout.showsInvisibles != display.showsInvisibles {
            layout.showsInvisibles = display.showsInvisibles
            text.needsDisplay = true
        }
        guard container.widthTracksTextView != display.wrapsLines else { return }
        scroll.hasHorizontalScroller = !display.wrapsLines
        text.isHorizontallyResizable = !display.wrapsLines
        container.widthTracksTextView = display.wrapsLines
        if display.wrapsLines {
            text.setFrameSize(NSSize(width: scroll.contentSize.width, height: text.frame.height))
        } else {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        (scroll.verticalRulerView as? DiffLineRuler)?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var diff: FileDiff?
        var display = DiffDisplay()
    }

    static func document(_ diff: FileDiff) -> NSAttributedString {
        attributedText(DiffDocument(diff), display: DiffDisplay())
    }

    /// A changed run of words inside a removed or added line.
    struct WordHighlight {
        let range: NSRange
        let kind: DiffLine.Kind
    }

    /// The words each replaced line changed, in document offsets.
    static func wordHighlights(_ document: DiffDocument) -> [WordHighlight] {
        var result: [WordHighlight] = []
        for (removed, added) in document.replacedLinePairs() {
            guard let changes = WordDiff.changes(old: document.lineText(ofRow: removed), new: document.lineText(ofRow: added)) else { continue }
            result += changes.old.map { WordHighlight(range: shifted($0, into: document.rows[removed]), kind: .deletion) }
            result += changes.new.map { WordHighlight(range: shifted($0, into: document.rows[added]), kind: .addition) }
        }
        return result
    }

    /// The words that differ between rows facing each other in a side-by-side diff.
    static func sideBySideWordHighlights(old: DiffDocument, new: DiffDocument) -> (old: [WordHighlight], new: [WordHighlight]) {
        var oldWords: [WordHighlight] = []
        var newWords: [WordHighlight] = []
        for index in 0 ..< min(old.rows.count, new.rows.count) where old.rows[index].kind == .deletion && new.rows[index].kind == .addition {
            guard let changes = WordDiff.changes(old: old.lineText(ofRow: index), new: new.lineText(ofRow: index)) else { continue }
            oldWords += changes.old.map { WordHighlight(range: shifted($0, into: old.rows[index]), kind: .deletion) }
            newWords += changes.new.map { WordHighlight(range: shifted($0, into: new.rows[index]), kind: .addition) }
        }
        return (oldWords, newWords)
    }

    /// A range in a line's text, moved past the row's "+ " marker.
    private static func shifted(_ range: NSRange, into row: DiffDocument.Row) -> NSRange {
        NSRange(location: row.range.location + 2 + range.location, length: range.length)
    }

    static func attributedText(_ document: DiffDocument, display: DiffDisplay, words: [WordHighlight]? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = display.lineHeight
        paragraph.lineBreakMode = display.wrapsLines ? .byCharWrapping : .byClipping
        let base: [NSAttributedString.Key: Any] = [
            .font: display.font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph
        ]
        let result = NSMutableAttributedString(string: document.text, attributes: base)
        for row in document.rows where !row.isFiller {
            var attributes: [NSAttributedString.Key: Any] = [:]
            switch row.kind {
            case .addition:
                attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.12)
            case .deletion:
                attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.12)
            case nil:
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.08)
            case .context, .noNewline: break
            }
            result.addAttributes(attributes, range: row.range)
            // The + and - markers carry their line's color.
            if row.kind == .addition || row.kind == .deletion, row.range.length >= 1 {
                let color = row.kind == .addition ? NSColor.systemGreen : NSColor.systemRed
                result.addAttribute(.foregroundColor, value: color, range: NSRange(location: row.range.location, length: 1))
            }
        }

        // Syntax colors, skipped for very long diffs.
        if let highlighter = SyntaxHighlighter.forPath(display.path), document.rows.count <= 20000 {
            var inBlockComment = false
            for (index, row) in document.rows.enumerated() {
                guard let kind = row.kind, kind != .noNewline else {
                    inBlockComment = false
                    continue
                }
                let line = document.lineText(ofRow: index)
                for (range, token) in highlighter.highlight(line, inBlockComment: &inBlockComment) {
                    result.addAttribute(.foregroundColor, value: SyntaxHighlighter.color(for: token), range: shifted(range, into: row))
                }
            }
        }

        for word in words ?? wordHighlights(document) {
            let color = word.kind == .addition ? NSColor.systemGreen : NSColor.systemRed
            result.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.32), range: word.range)
        }
        return result
    }
}

/// The old file on the left and the new one on the right, scrolling together.
/// Lines do not wrap here, so the two sides stay level row for row.
struct SideBySideDiffView: NSViewRepresentable {
    let diff: FileDiff
    var display = DiffDisplay()

    func makeNSView(context _: Context) -> SideBySideDiffContainer {
        SideBySideDiffContainer()
    }

    func updateNSView(_ container: SideBySideDiffContainer, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.diff != diff || coordinator.display != display else { return }
        let diffChanged = coordinator.diff != diff
        coordinator.diff = diff
        coordinator.display = display
        container.show(diff, display: display, resetPosition: diffChanged)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var diff: FileDiff?
        var display = DiffDisplay()
    }
}

final class SideBySideDiffContainer: NSSplitView {
    private let old = NativeDiffTextView.makeScrollView()
    private let new = NativeDiffTextView.makeScrollView()
    private var syncing = false

    init() {
        super.init(frame: .zero)
        isVertical = true
        dividerStyle = .thin
        for (scroll, label) in [(old, "Old version"), (new, "New version")] {
            (scroll.verticalRulerView as? DiffLineRuler)?.singleColumn = true
            (scroll.documentView as? NSTextView)?.setAccessibilityLabel(label)
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            addArrangedSubview(scroll)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("SideBySideDiffContainer does not support NSCoder")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func show(_ diff: FileDiff, display: DiffDisplay, resetPosition: Bool) {
        let documents = DiffDocument.sideBySide(diff)
        let words = NativeDiffTextView.sideBySideWordHighlights(old: documents.old, new: documents.new)
        var display = display
        display.wrapsLines = false
        for (scroll, document, highlights) in [(old, documents.old, words.old), (new, documents.new, words.new)] {
            NativeDiffTextView.apply(display, to: scroll)
            NativeDiffTextView.show(document, in: scroll, display: display, resetPosition: resetPosition, words: highlights)
        }
    }

    override func layout() {
        super.layout()
        // Start with two equal halves; after that the divider is yours.
        if subviews.count == 2, subviews[0].frame.width == 0 || subviews[1].frame.width == 0, bounds.width > 0 {
            setPosition((bounds.width - dividerThickness) / 2, ofDividerAt: 0)
        }
    }

    /// Keeps both sides on the same rows: they have the same number of rows
    /// at the same height, so the same vertical offset shows the same rows.
    @objc private func scrolled(_ notification: Notification) {
        guard !syncing, let source = notification.object as? NSClipView else { return }
        let target = source === old.contentView ? new : old
        let y = source.bounds.origin.y
        guard target.contentView.bounds.origin.y != y else { return }
        syncing = true
        target.contentView.scroll(to: NSPoint(x: target.contentView.bounds.origin.x, y: y))
        target.reflectScrolledClipView(target.contentView)
        syncing = false
    }
}

final class DiffScrollView: NSScrollView {
    private var needsDocumentPositionReset = false
    /// The document on show, to tell which lines a selection picks.
    var document: DiffDocument?
    var lineActions: DiffLineActions? {
        didSet { updateLineActionBar() }
    }

    private var actionBar: NSHostingView<DiffLineActionBar>?
    private var keepsPosition = false

    /// Whether the next document should keep the scroll position, once.
    func takeKeepsPosition() -> Bool {
        defer { keepsPosition = false }
        return keepsPosition
    }

    func observeForLineActions() {
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(lineActionContextChanged(_:)), name: NSView.boundsDidChangeNotification, object: contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(lineActionContextChanged(_:)), name: NSTextView.didChangeSelectionNotification, object: documentView
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func lineActionContextChanged(_: Notification) {
        updateLineActionBar()
    }

    /// Shows the buttons beside the first picked row, or hides them when
    /// nothing is picked. A caret picks its hunk once you have clicked in the
    /// diff; selected text picks the changed lines it touches.
    func updateLineActionBar() {
        guard let actions = lineActions, let document,
              let text = documentView as? NSTextView,
              let layout = text.layoutManager, let container = text.textContainer
        else {
            actionBar?.isHidden = true
            return
        }
        let selection = text.selectedRange()
        let picked = document.lineKeys(in: selection)
        let caretIsActive = selection.length > 0 || window?.firstResponder === text
        guard caretIsActive, !picked.keys.isEmpty, let first = picked.firstRow else {
            actionBar?.isHidden = true
            return
        }
        let keys = picked.keys
        let bar = DiffLineActionBar(mode: actions.mode, isHunk: picked.isHunk) { [weak self] command in
            self?.keepsPosition = command != .discard
            actions.perform(command, keys)
        }
        let host: NSHostingView<DiffLineActionBar>
        if let actionBar {
            host = actionBar
            host.rootView = bar
        } else {
            host = NSHostingView(rootView: bar)
            addSubview(host, positioned: .above, relativeTo: nil)
            actionBar = host
        }
        let glyphs = layout.glyphRange(forCharacterRange: first.range, actualCharacterRange: nil)
        var rowRect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        rowRect.origin.x += text.textContainerOrigin.x
        rowRect.origin.y += text.textContainerOrigin.y
        let row = convert(rowRect, from: text)
        let visible = contentView.frame
        let size = host.fittingSize
        // Level with the row's top, kept inside the visible part of the diff.
        let rowTop = isFlipped ? row.minY : row.maxY
        var y = isFlipped ? rowTop : rowTop - size.height
        y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)
        host.frame = NSRect(x: visible.maxX - size.width - 12, y: y, width: size.width, height: size.height)
        host.isHidden = false
    }

    func resetDocumentPosition() {
        needsDocumentPositionReset = true
        tile()
    }

    override func tile() {
        super.tile()
        updateLineActionBar()
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
