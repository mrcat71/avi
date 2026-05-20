/// A parsed unified diff for a single file.
public struct FileDiff: Sendable, Equatable {
    public let hunks: [DiffHunk]
    public let isBinary: Bool

    public init(hunks: [DiffHunk], isBinary: Bool) {
        self.hunks = hunks
        self.isBinary = isBinary
    }

    /// No textual changes and not binary (e.g. mode-only change or identical content).
    public var isEmpty: Bool { hunks.isEmpty && !isBinary }
}

public struct DiffHunk: Sendable, Equatable {
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public struct DiffLine: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case context
        case addition
        case deletion
        case noNewline
    }

    public let id: Int
    public let kind: Kind
    /// Line content without the leading +/-/space marker.
    public let text: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(id: Int, kind: Kind, text: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

/// Which version of a file to diff against.
public enum DiffSource: Sendable, Equatable {
    case unstaged   // working tree vs index
    case staged     // index vs HEAD
    case untracked  // whole file as additions
}
