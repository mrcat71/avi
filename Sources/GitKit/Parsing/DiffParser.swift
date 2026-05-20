import Foundation

/// Parses git unified-diff output (`git diff` family, `--no-color`) into hunks.
public enum DiffParser {
    public static func parse(_ text: String) -> FileDiff {
        let hunkHeader = /@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/
        var hunks: [DiffHunk] = []
        var isBinary = false
        var nextID = 0
        var current: HunkBuilder?

        func finalize() {
            if let builder = current {
                hunks.append(builder.build())
                current = nil
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("@@") {
                finalize()
                if let match = line.firstMatch(of: hunkHeader) {
                    current = HunkBuilder(
                        header: line,
                        oldStart: Int(match.1) ?? 0,
                        oldCount: match.2.flatMap { Int($0) } ?? 1,
                        newStart: Int(match.3) ?? 0,
                        newCount: match.4.flatMap { Int($0) } ?? 1
                    )
                }
                continue
            }

            guard current != nil else {
                if line.hasPrefix("Binary files") { isBinary = true }
                continue
            }

            guard let marker = line.first else { continue }
            switch marker {
            case " ":
                current?.add(.context, String(line.dropFirst()), id: &nextID)
            case "+":
                current?.add(.addition, String(line.dropFirst()), id: &nextID)
            case "-":
                current?.add(.deletion, String(line.dropFirst()), id: &nextID)
            case "\\":
                // "\ No newline at end of file"
                current?.add(.noNewline, String(line.dropFirst(2)), id: &nextID)
            default:
                // Start of the next file's header block ends the current hunk.
                finalize()
                if line.hasPrefix("Binary files") { isBinary = true }
            }
        }
        finalize()
        return FileDiff(hunks: hunks, isBinary: isBinary)
    }
}

private struct HunkBuilder {
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int

    private var lines: [DiffLine] = []
    private var oldLine: Int
    private var newLine: Int

    init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.oldLine = oldStart
        self.newLine = newStart
    }

    mutating func add(_ kind: DiffLine.Kind, _ text: String, id: inout Int) {
        let lineID = id
        id += 1
        switch kind {
        case .context:
            lines.append(DiffLine(id: lineID, kind: .context, text: text, oldLineNumber: oldLine, newLineNumber: newLine))
            oldLine += 1
            newLine += 1
        case .addition:
            lines.append(DiffLine(id: lineID, kind: .addition, text: text, oldLineNumber: nil, newLineNumber: newLine))
            newLine += 1
        case .deletion:
            lines.append(DiffLine(id: lineID, kind: .deletion, text: text, oldLineNumber: oldLine, newLineNumber: nil))
            oldLine += 1
        case .noNewline:
            lines.append(DiffLine(id: lineID, kind: .noNewline, text: text, oldLineNumber: nil, newLineNumber: nil))
        }
    }

    func build() -> DiffHunk {
        DiffHunk(header: header, oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: lines)
    }
}
