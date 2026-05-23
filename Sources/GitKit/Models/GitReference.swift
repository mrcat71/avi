import Foundation

public enum GitReferenceKind: String, Sendable, Equatable {
    case localBranch
    case remoteBranch
    case tag
}

public struct GitReference: Sendable, Equatable, Identifiable {
    public var id: String {
        fullName
    }

    public let name: String
    public let fullName: String
    public let oid: String
    public let kind: GitReferenceKind
    public let upstream: String?
    public let isCurrent: Bool
    public let subject: String?
    public let ahead: Int?
    public let behind: Int?
    public let isUpstreamGone: Bool
    public let taggerDate: Date?
    public let annotatedMessage: String?

    public init(
        name: String,
        fullName: String,
        oid: String,
        kind: GitReferenceKind,
        upstream: String? = nil,
        isCurrent: Bool = false,
        subject: String? = nil,
        ahead: Int? = nil,
        behind: Int? = nil,
        isUpstreamGone: Bool = false,
        taggerDate: Date? = nil,
        annotatedMessage: String? = nil
    ) {
        self.name = name
        self.fullName = fullName
        self.oid = oid
        self.kind = kind
        self.upstream = upstream
        self.isCurrent = isCurrent
        self.subject = subject
        self.ahead = ahead
        self.behind = behind
        self.isUpstreamGone = isUpstreamGone
        self.taggerDate = taggerDate
        self.annotatedMessage = annotatedMessage
    }
}

public struct RepositoryRefs: Sendable, Equatable {
    public let localBranches: [GitReference]
    public let remoteBranches: [GitReference]
    public let tags: [GitReference]

    public init(localBranches: [GitReference], remoteBranches: [GitReference], tags: [GitReference]) {
        self.localBranches = localBranches
        self.remoteBranches = remoteBranches
        self.tags = tags
    }

    public static let empty = RepositoryRefs(localBranches: [], remoteBranches: [], tags: [])
}
