import Foundation
import GitKit

/// Text and gutter metadata share UTF-16 offsets, matching AppKit's text system.
struct DiffDocument {
    struct Row {
        let range: NSRange
        let oldLine: Int?
        let newLine: Int?
        let kind: DiffLine.Kind?
    }

    let text: String
    let rows: [Row]

    init(_ diff: FileDiff) {
        var text = ""
        var rows: [Row] = []
        var offset = 0
        func append(_ value: String, old: Int?, new: Int?, kind: DiffLine.Kind?) {
            let line = value + "\n"
            let length = line.utf16.count
            rows.append(Row(range: NSRange(location: offset, length: length), oldLine: old, newLine: new, kind: kind))
            text.append(line)
            offset += length
        }
        for hunk in diff.hunks {
            append(hunk.header, old: nil, new: nil, kind: nil)
            for line in hunk.lines {
                let marker: String
                switch line.kind {
                case .addition: marker = "+"
                case .deletion: marker = "-"
                case .context: marker = " "
                case .noNewline: marker = "\\"
                }
                append(marker + " " + line.text, old: line.oldLineNumber, new: line.newLineNumber, kind: line.kind)
            }
        }
        self.text = text
        self.rows = rows
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
}
