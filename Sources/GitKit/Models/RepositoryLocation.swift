import Foundation

/// Where a repository's parts live. A linked worktree has its own working tree
/// and git dir, but shares the common dir - refs, objects, packed-refs - with
/// the repository it was created from.
public struct RepositoryLocation: Sendable, Equatable {
    public let workingTree: URL
    public let gitDir: URL
    public let commonDir: URL

    public init(workingTree: URL, gitDir: URL, commonDir: URL) {
        self.workingTree = workingTree
        self.gitDir = gitDir
        self.commonDir = commonDir
    }

    public var isLinkedWorktree: Bool {
        gitDir.standardizedFileURL.path != commonDir.standardizedFileURL.path
    }
}
