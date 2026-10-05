import Foundation
@testable import GitKit
import Testing

/// Detached HEAD and worktree housekeeping, the states AI agents leave behind.
struct WorktreeActionTests {
    @Test func countsCommitsADetachedHeadHasOnNoBranch() async throws {
        try await withTempRepo { repo in
            try await commit(repo, "a.txt", "1\n", "on main")
            try await repo.git("branch", "-M", "main")
            #expect(try await provider(repo).unreferencedCommitCount(in: repo.url) == 0)

            try await repo.git("switch", "-q", "--detach")
            try await commit(repo, "a.txt", "2\n", "detached one")
            try await commit(repo, "a.txt", "3\n", "detached two")
            #expect(try await provider(repo).unreferencedCommitCount(in: repo.url) == 2)

            // A tag keeps them as well as a branch does.
            try await repo.git("tag", "kept")
            #expect(try await provider(repo).unreferencedCommitCount(in: repo.url) == 0)
        }
    }

    @Test func removesACleanWorktreeAndAsksBeforeDeletingChanges() async throws {
        try await withTempRepo { repo in
            try await commit(repo, "a.txt", "1\n", "base")
            try await repo.git("branch", "feature")
            let path = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-wt-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: path) }
            try await provider(repo).addWorktree(at: path, branch: "feature", in: repo.url)
            try "work in progress\n".write(to: path.appendingPathComponent("wip.txt"), atomically: true, encoding: .utf8)

            do {
                try await provider(repo).removeWorktree(at: path, force: false, in: repo.url)
                Issue.record("A worktree with changes must not be removed without force")
            } catch let GitError.commandFailed(_, _, stderr) {
                #expect(GitError.indicatesDirtyWorktree(stderr))
            }
            #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("wip.txt").path))

            try await provider(repo).removeWorktree(at: path, force: true, in: repo.url)

            #expect(!FileManager.default.fileExists(atPath: path.path))
            #expect(try await provider(repo).worktrees(in: repo.url).count == 1)
            // The branch outlives its worktree.
            #expect(try await provider(repo).refs(in: repo.url).localBranches.contains { $0.name == "feature" })
        }
    }

    @Test func pruneForgetsAWorktreeWhoseFolderIsGone() async throws {
        try await withTempRepo { repo in
            try await commit(repo, "a.txt", "1\n", "base")
            try await repo.git("branch", "feature")
            let path = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-wt-\(UUID().uuidString)")
            try await provider(repo).addWorktree(at: path, branch: "feature", in: repo.url)
            try FileManager.default.removeItem(at: path)
            #expect(try await provider(repo).worktrees(in: repo.url).contains(where: \.isPrunable))

            _ = try await provider(repo).pruneWorktrees(in: repo.url)

            #expect(try await provider(repo).worktrees(in: repo.url).count == 1)
        }
    }

    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    private func commit(_ repo: GitFixture, _ file: String, _ content: String, _ message: String) async throws {
        try repo.write(file, content)
        try await repo.git("add", "--", file)
        try await repo.git("commit", "-q", "-m", message)
    }
}
