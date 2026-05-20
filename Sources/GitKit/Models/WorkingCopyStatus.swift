/// Working-copy status: the current branch plus the changed entries.
public struct WorkingCopyStatus: Sendable, Equatable {
    public let branch: BranchInfo
    public let entries: [FileStatus]

    public init(branch: BranchInfo, entries: [FileStatus]) {
        self.branch = branch
        self.entries = entries
    }
}

/// HEAD/branch summary from `git status --porcelain=v2 --branch`.
public struct BranchInfo: Sendable, Equatable {
    /// Current branch name, or nil when detached.
    public let name: String?
    /// HEAD commit, or nil when the branch is unborn (no commits yet).
    public let oid: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int

    public init(name: String? = nil, oid: String? = nil, upstream: String? = nil, ahead: Int = 0, behind: Int = 0) {
        self.name = name
        self.oid = oid
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }

    public var isDetached: Bool { name == nil && oid != nil }
    public var isUnborn: Bool { oid == nil }
}
