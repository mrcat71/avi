import Foundation

/// The commit that last changed a line, as `git blame` reports it.
public struct BlameCommit: Sendable, Equatable {
    public let oid: String
    public let author: String
    public let authorEmail: String
    public let authorDate: Date?
    public let summary: String

    public init(oid: String, author: String, authorEmail: String = "", authorDate: Date? = nil, summary: String) {
        self.oid = oid
        self.author = author
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.summary = summary
    }

    /// Lines you changed but have not committed carry an all-zero ID.
    public var isUncommitted: Bool {
        oid.allSatisfy { $0 == "0" }
    }

    public var shortOID: String {
        String(oid.prefix(8))
    }
}

/// One line of a blamed file.
public struct BlameLine: Sendable, Equatable, Identifiable {
    public var id: Int {
        lineNumber
    }

    /// 1-based line number in the blamed version of the file.
    public let lineNumber: Int
    public let content: String
    public let commit: BlameCommit

    public init(lineNumber: Int, content: String, commit: BlameCommit) {
        self.lineNumber = lineNumber
        self.content = content
        self.commit = commit
    }
}
