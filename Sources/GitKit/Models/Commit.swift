import Foundation

/// One commit as shown in the history list.
public struct CommitSummary: Sendable, Equatable, Identifiable {
    public var id: String {
        oid
    }

    public let oid: String
    public let parentOIDs: [String]
    public let authorName: String
    public let authorEmail: String
    public let authorDate: Date
    public let subject: String
    public let body: String

    public init(
        oid: String,
        parentOIDs: [String],
        authorName: String,
        authorEmail: String,
        authorDate: Date,
        subject: String,
        body: String
    ) {
        self.oid = oid
        self.parentOIDs = parentOIDs
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.subject = subject
        self.body = body
    }

    public var shortOID: String {
        String(oid.prefix(12))
    }
}

public enum CommitFileChangeKind: String, Sendable, Equatable {
    case added = "A"
    case copied = "C"
    case deleted = "D"
    case modified = "M"
    case renamed = "R"
    case typeChanged = "T"
    case unmerged = "U"
    case unknown = "?"

    public init(statusToken: String) {
        guard let first = statusToken.first else {
            self = .unknown
            return
        }
        self = CommitFileChangeKind(rawValue: String(first)) ?? .unknown
    }
}

/// One file changed by a commit.
public struct CommitFileChange: Sendable, Equatable, Identifiable {
    public var id: String {
        "\(kind.rawValue):\(oldPath ?? ""):\(path)"
    }

    public let path: String
    public let oldPath: String?
    public let kind: CommitFileChangeKind

    public init(path: String, oldPath: String? = nil, kind: CommitFileChangeKind) {
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
    }

    public var displayPath: String {
        guard let oldPath else { return path }
        return "\(oldPath) -> \(path)"
    }
}
