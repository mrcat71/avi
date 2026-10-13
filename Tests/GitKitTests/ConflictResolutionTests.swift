import Foundation
@testable import GitKit
import Testing

/// Resolving a stopped merge's conflicts, against real repositories under /tmp.
struct ConflictResolutionTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    /// main and topic both changed a.txt; topic also changed b.txt, which
    /// main deleted. Merging topic stops on both.
    private func conflictedMerge(_ repo: GitFixture) async throws {
        try repo.write("a.txt", "base\n")
        try repo.write("b.txt", "base\n")
        try await repo.git("add", ".")
        try await repo.git("commit", "-q", "-m", "base")
        try await repo.git("branch", "-M", "main")
        try await repo.git("switch", "-q", "-c", "topic")
        try repo.write("a.txt", "topic\n")
        try repo.write("b.txt", "topic\n")
        try await repo.git("commit", "-q", "-am", "topic")
        try await repo.git("switch", "-q", "main")
        try repo.write("a.txt", "main\n")
        try await repo.git("rm", "-q", "b.txt")
        try await repo.git("commit", "-q", "-am", "main")
        let merge = try await ProcessRunner.run(executable: repo.gitURL, arguments: ["merge", "topic"], workingDirectory: repo.url)
        #expect(merge.exitCode != 0)
    }

    private func conflictedPaths(_ repo: GitFixture) async throws -> [String] {
        try await provider(repo).status(in: repo.url).entries.filter(\.isConflicted).map(\.path).sorted()
    }

    @Test func takingASideWritesItsVersionAndStagesIt() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)
            #expect(try await conflictedPaths(repo) == ["a.txt", "b.txt"])

            try await provider(repo).resolveConflicts(paths: ["a.txt"], taking: .incoming, in: repo.url)

            #expect(try repo.read("a.txt") == "topic\n")
            #expect(try await conflictedPaths(repo) == ["b.txt"])
        }
    }

    @Test func takingTheSideThatDeletedAFileDeletesIt() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)

            try await provider(repo).resolveConflicts(paths: ["b.txt"], taking: .current, in: repo.url)

            #expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("b.txt").path))
            #expect(try await conflictedPaths(repo) == ["a.txt"])
        }
    }

    @Test func takingTheSideThatKeptAFileRestoresIt() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)

            try await provider(repo).resolveConflicts(paths: ["b.txt"], taking: .incoming, in: repo.url)

            #expect(try repo.read("b.txt") == "topic\n")
            #expect(try await conflictedPaths(repo) == ["a.txt"])
        }
    }

    @Test func markingResolvedStagesEditsAndDeletions() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)
            try repo.write("a.txt", "both\n")
            try FileManager.default.removeItem(at: repo.url.appendingPathComponent("b.txt"))

            try await provider(repo).markResolved(paths: ["a.txt", "b.txt"], in: repo.url)

            #expect(try await conflictedPaths(repo).isEmpty)
            let staged = try await repo.git("diff", "--cached", "--name-status").stdoutString
            #expect(staged.contains("M\ta.txt"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aMergeToolThatSucceedsLeavesTheFileResolved() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)
            let tool = MergeToolLaunch(name: "avi-test", command: #"printf 'merged\n' > "$MERGED""#, trustExitCode: true)

            let outcome = try await provider(repo).launchMergeTool(path: "a.txt", tool: tool, in: repo.url)

            #expect(outcome == .resolved)
            #expect(try repo.read("a.txt") == "merged\n")
            #expect(try await conflictedPaths(repo) == ["b.txt"])
            // No .orig backups or temporary copies are left in the repository.
            let untracked = try await repo.git("ls-files", "--others", "--exclude-standard").stdoutString
            #expect(untracked.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aMergeToolClosedWithoutMergingLeavesTheConflict() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)
            // Not trusting the exit code, Git asks whether the unchanged file
            // merged; with no one to answer, the answer is no.
            let tool = MergeToolLaunch(name: "avi-test", command: "true", trustExitCode: false)

            let outcome = try await provider(repo).launchMergeTool(path: "a.txt", tool: tool, in: repo.url)

            #expect(outcome == .unresolved)
            #expect(try await conflictedPaths(repo) == ["a.txt", "b.txt"])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aMergeToolGitDoesNotKnowIsAnError() async throws {
        try await withTempRepo { repo in
            try await conflictedMerge(repo)

            await #expect(throws: GitError.self) {
                _ = try await provider(repo).launchMergeTool(path: "a.txt", tool: MergeToolLaunch(name: "no-such-tool"), in: repo.url)
            }
        }
    }
}
