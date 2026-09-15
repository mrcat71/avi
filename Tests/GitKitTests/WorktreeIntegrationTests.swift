import Foundation
@testable import GitKit
import XCTest

/// Exercises real `git worktree` output against a disposable fixture repository.
final class WorktreeIntegrationTests: XCTestCase {
    func testListsMainAndLinkedWorktreeAndReportsSharedCommonDir() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.removeDirectory() }
        try fixture.write("file.txt", "one\n")
        try await fixture.git("add", "file.txt")
        try await fixture.git("commit", "-m", "first")
        try await fixture.git("branch", "feature")

        let linked = fixture.url.deletingLastPathComponent()
            .appendingPathComponent("\(fixture.url.lastPathComponent)-feature", isDirectory: true)
        try await fixture.git("worktree", "add", linked.path, "feature")
        defer { try? FileManager.default.removeItem(at: linked) }

        let provider = CLIGitProvider()
        let worktrees = try await provider.worktrees(in: fixture.url)
        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees.last?.branch, "feature")
        XCTAssertEqual(
            worktrees.last?.path.resolvingSymlinksInPath().standardizedFileURL.path,
            linked.resolvingSymlinksInPath().standardizedFileURL.path
        )

        let main = try await provider.location(of: fixture.url)
        XCTAssertFalse(main.isLinkedWorktree)

        let linkedLocation = try await provider.location(of: linked)
        XCTAssertTrue(linkedLocation.isLinkedWorktree)
        // Refs are shared, which is why both must queue against one key.
        XCTAssertEqual(
            linkedLocation.commonDir.resolvingSymlinksInPath().standardizedFileURL.path,
            main.commonDir.resolvingSymlinksInPath().standardizedFileURL.path
        )
        XCTAssertEqual(
            GitCommandQueue.queueKey(for: linked),
            GitCommandQueue.queueKey(for: fixture.url)
        )
    }

    func testCheckoutOfABranchHeldElsewhereFailsWithAReadableMessage() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.removeDirectory() }
        try fixture.write("file.txt", "one\n")
        try await fixture.git("add", "file.txt")
        try await fixture.git("commit", "-m", "first")
        try await fixture.git("branch", "feature")

        let linked = fixture.url.deletingLastPathComponent()
            .appendingPathComponent("\(fixture.url.lastPathComponent)-held", isDirectory: true)
        try await fixture.git("worktree", "add", linked.path, "feature")
        defer { try? FileManager.default.removeItem(at: linked) }

        let ref = GitReference(
            name: "feature", fullName: "refs/heads/feature",
            oid: String(repeating: "a", count: 40), kind: .localBranch
        )
        do {
            try await CLIGitProvider().checkout(ref, in: fixture.url)
            XCTFail("Git must refuse a branch already checked out in another worktree")
        } catch let error as GitError {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains("another worktree"), description)
            XCTAssertTrue(description.contains(linked.lastPathComponent), description)
            // The raw fatal text is replaced by the explanation.
            XCTAssertFalse(description.contains("fatal:"), description)
        }
    }

    func testQueueKeyFallsBackToTheWorkingTreeForAnOrdinaryRepository() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.removeDirectory() }
        XCTAssertEqual(
            GitCommandQueue.queueKey(for: fixture.url),
            fixture.url.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }
}
