import Foundation
import GitKit

/// Text and gutter metadata share UTF-16 offsets, matching AppKit's text system.
struct DiffDocument {
    struct Row {
        let range: NSRange
        let oldLine: Int?
        let newLine: Int?
        let kind: DiffLine.Kind?
        /// A blank row that keeps the two sides of a side-by-side diff level.
        var isFiller = false
    }

    let text: String
    let rows: [Row]

    init(_ diff: FileDiff) {
        var builder = Builder()
        for hunk in diff.hunks {
            builder.header(hunk.header)
            for line in hunk.lines {
                builder.append(line, old: line.oldLineNumber, new: line.newLineNumber)
            }
        }
        self.init(text: builder.text, rows: builder.rows)
    }

    init(text: String, rows: [Row]) {
        self.text = text
        self.rows = rows
    }

    /// The old and the new file side by side, row for row: the lines a change
    /// removes face the lines it adds, context lines face themselves, and the
    /// shorter side of a change is padded with blank rows.
    static func sideBySide(_ diff: FileDiff) -> (old: DiffDocument, new: DiffDocument) {
        var old = Builder()
        var new = Builder()
        var removed: [DiffLine] = []
        var added: [DiffLine] = []

        func flush() {
            for index in 0 ..< max(removed.count, added.count) {
                if index < removed.count {
                    old.append(removed[index], old: removed[index].oldLineNumber, new: nil)
                } else {
                    old.filler()
                }
                if index < added.count {
                    new.append(added[index], old: nil, new: added[index].newLineNumber)
                } else {
                    new.filler()
                }
            }
            removed = []
            added = []
        }

        for hunk in diff.hunks {
            flush()
            old.header(hunk.header)
            new.header(hunk.header)
            var previous = DiffLine.Kind.context
            for line in hunk.lines {
                // "\ No newline at end of file" belongs to the line before it.
                switch line.kind == .noNewline ? previous : line.kind {
                case .deletion:
                    removed.append(line)
                case .addition:
                    added.append(line)
                case .context, .noNewline:
                    flush()
                    old.append(line, old: line.oldLineNumber, new: nil)
                    new.append(line, old: nil, new: line.newLineNumber)
                }
                if line.kind != .noNewline {
                    previous = line.kind
                }
            }
        }
        flush()
        return (DiffDocument(text: old.text, rows: old.rows), DiffDocument(text: new.text, rows: new.rows))
    }

    func row(containing offset: Int) -> Row? {
        guard offset >= 0 else { return nil }
        var lower = 0
        var upper = rows.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(rows[middle].range) <= offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < rows.count, NSLocationInRange(offset, rows[lower].range) else { return nil }
        return rows[lower]
    }

    private struct Builder {
        var text = ""
        var rows: [Row] = []
        private var offset = 0

        mutating func header(_ value: String) {
            add(value, old: nil, new: nil, kind: nil, filler: false)
        }

        mutating func append(_ line: DiffLine, old: Int?, new: Int?) {
            let marker: String
            switch line.kind {
            case .addition: marker = "+"
            case .deletion: marker = "-"
            case .context: marker = " "
            case .noNewline: marker = "\\"
            }
            add(marker + " " + line.text, old: old, new: new, kind: line.kind, filler: false)
        }

        mutating func filler() {
            add("", old: nil, new: nil, kind: nil, filler: true)
        }

        private mutating func add(_ value: String, old: Int?, new: Int?, kind: DiffLine.Kind?, filler: Bool) {
            let line = value + "\n"
            let length = line.utf16.count
            rows.append(Row(range: NSRange(location: offset, length: length), oldLine: old, newLine: new, kind: kind, isFiller: filler))
            text.append(line)
            offset += length
        }
    }
}
