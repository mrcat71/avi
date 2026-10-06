import AppKit

/// Draws a mark over spaces, tabs, carriage returns, and line ends when
/// `showsInvisibles` is on. TextKit's own `showsInvisibleCharacters` leaves
/// tabs and line ends blank, and replacing the characters themselves would
/// change what you copy and find.
/// Whoever changes `showsInvisibles` redraws the text view.
final class InvisiblesLayoutManager: NSLayoutManager {
    var showsInvisibles = false

    /// The mark drawn for each invisible character.
    static func mark(for character: unichar) -> String? {
        switch character {
        case 0x20: return "\u{00B7}" // · space
        case 0x09: return "\u{2192}" // → tab
        case 0x0D: return "\u{240D}" // ␍ carriage return, as in CRLF line ends
        case 0x0A: return "\u{00AC}" // ¬ line end
        default: return nil
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showsInvisibles, let storage = textStorage else { return }
        let text = storage.string as NSString
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard characters.length > 0 else { return }
        let font = (storage.attribute(.font, at: characters.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        for index in characters.location ..< NSMaxRange(characters) {
            guard let mark = Self.mark(for: text.character(at: index)) else { continue }
            let glyph = glyphIndexForCharacter(at: index)
            // Where the glyph itself starts, on the text's baseline. A line
            // end's bounding box spans the whole line, so it would put the
            // mark at the start. The text view is flipped, so the point is
            // the mark's top-left corner.
            let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let position = location(forGlyphAt: glyph)
            let point = NSPoint(
                x: origin.x + fragment.minX + position.x,
                y: origin.y + fragment.minY + position.y - font.ascender
            )
            (mark as NSString).draw(at: point, withAttributes: attributes)
        }
    }
}
