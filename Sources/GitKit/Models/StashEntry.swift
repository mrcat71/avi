import Foundation

public struct StashEntry: Sendable, Equatable, Identifiable {
    public var id: String { ref }

    /// Short ref of the stash, e.g. "stash@{0}".
    public let ref: String
    /// Numeric stash index parsed from `ref` (0 = top of the stash stack).
    public let index: Int
    /// Full commit OID of the stash commit.
    public let oid: String
    /// Reflog subject, e.g. "WIP on main: abc1234 some commit".
    public let subject: String
    /// Branch the stash was created on, when parseable from `subject`.
    public let branch: String?
    /// Committer date of the stash commit.
    public let date: Date?

    public init(
        ref: String,
        index: Int,
        oid: String,
        subject: String,
        branch: String? = nil,
        date: Date? = nil
    ) {
        self.ref = ref
        self.index = index
        self.oid = oid
        self.subject = subject
        self.branch = branch
        self.date = date
    }
}
