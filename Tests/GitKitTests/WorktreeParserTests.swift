@testable import GitKit
import Testing

struct WorktreeParserTests {
    /// Shape captured from `git worktree list --porcelain` on git 2.55.0.
    private let listing = """
    worktree /repo
    HEAD 1111111111111111111111111111111111111111
    branch refs/heads/main

    worktree /repo-detached
    HEAD 2222222222222222222222222222222222222222
    detached
    locked

    worktree /repo-feature
    HEAD 3333333333333333333333333333333333333333
    branch refs/heads/feature/auth
    locked waiting for review
    prunable gitdir file points to non-existent location
    """

    @Test func parsesBranchDetachedAndLockState() throws {
        let worktrees = try WorktreeParser.parse(listing)

        #expect(worktrees.map(\.path.path) == ["/repo", "/repo-detached", "/repo-feature"])
        #expect(worktrees[0].branch == "main")
        #expect(worktrees[0].isDetached == false)
        #expect(worktrees[0].isLocked == false)

        #expect(worktrees[1].branch == nil)
        #expect(worktrees[1].isDetached)
        #expect(worktrees[1].isLocked)
        // `locked` with no reason must still read as locked.
        #expect(worktrees[1].lockReason == nil)

        #expect(worktrees[2].branch == "feature/auth")
        #expect(worktrees[2].lockReason == "waiting for review")
        #expect(worktrees[2].isPrunable)
        #expect(worktrees[2].prunableReason == "gitdir file points to non-existent location")
    }

    @Test func parsesBareMainWorktree() throws {
        let worktrees = try WorktreeParser.parse("worktree /repo.git\nbare")

        #expect(worktrees.count == 1)
        #expect(worktrees[0].isBare)
        #expect(worktrees[0].branch == nil)
        #expect(worktrees[0].isDetached == false)
        #expect(worktrees[0].headOID == nil)
    }

    @Test func keepsFullRefNameWhenItIsNotUnderRefsHeads() throws {
        let worktrees = try WorktreeParser.parse("worktree /repo\nbranch refs/remotes/origin/main")
        #expect(worktrees[0].branch == "refs/remotes/origin/main")
    }

    @Test func ignoresUnknownAttributesFromANewerGit() throws {
        let worktrees = try WorktreeParser.parse("worktree /repo\nHEAD 4444\nbranch refs/heads/main\nsomething new")
        #expect(worktrees[0].branch == "main")
    }

    @Test func emptyListingHasNoWorktrees() throws {
        #expect(try WorktreeParser.parse("").isEmpty)
        #expect(try WorktreeParser.parse("\n\n").isEmpty)
    }

    @Test func recordWithoutAPathIsRejected() {
        #expect(throws: GitError.self) {
            try WorktreeParser.parse("HEAD 5555\nbranch refs/heads/main")
        }
    }
}
