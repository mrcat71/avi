import Foundation
@testable import GitKit
import Testing

struct OperationsTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    @Test func stageMovesFileToIndex() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "hello\n")
            try await provider(repo).stage(path: "a.txt", in: repo.url)

            let entry = try #require(try await provider(repo).status(in: repo.url).entries.first { $0.path == "a.txt" })
            #expect(entry.isStaged)
            #expect(entry.index == .added)
        }
    }

    @Test func stageAllStagesMultipleChanges() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try repo.write("b.txt", "v1\n")
            try await repo.git("add", "a.txt", "b.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")
            try repo.write("c.txt", "new\n")

            try await provider(repo).stageAll(in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            let staged = status.entries.filter(\.isStaged).map(\.path).sorted()
            #expect(staged == ["a.txt", "c.txt"])
        }
    }

    @Test func stagePathsStagesEverySelectedFileInOneCall() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "1\n")
            try repo.write("b.txt", "2\n")
            try repo.write("c.txt", "3\n")

            try await provider(repo).stage(paths: ["a.txt", "b.txt", "c.txt"], in: repo.url)

            let staged = try await provider(repo).status(in: repo.url)
                .entries.filter(\.isStaged).map(\.path).sorted()
            #expect(staged == ["a.txt", "b.txt", "c.txt"])
        }
    }

    @Test func unstagePathsUnstagesEverySelectedFile() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try repo.write("b.txt", "v1\n")
            try await repo.git("add", "a.txt", "b.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")
            try repo.write("b.txt", "v2\n")
            try await repo.git("add", "a.txt", "b.txt")

            try await provider(repo).unstage(paths: ["a.txt", "b.txt"], in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            for path in ["a.txt", "b.txt"] {
                let entry = try #require(status.entries.first { $0.path == path })
                #expect(entry.index == .unmodified)
                #expect(entry.worktree == .modified)
            }
        }
    }

    @Test func stashContentsListAndDiffChangedFiles() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")
            try await repo.git("stash", "push", "-m", "wip")

            let files = try await provider(repo).stashChangedFiles(ref: "stash@{0}", in: repo.url)
            #expect(files.map(\.path) == ["a.txt"])

            let diff = try await provider(repo).stashDiff(ref: "stash@{0}", path: "a.txt", in: repo.url)
            #expect(!diff.isBinary)
            #expect(!diff.hunks.isEmpty)
        }
    }

    @Test func unstageKeepsWorkingTreeChange() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")
            try await repo.git("add", "a.txt")

            try await provider(repo).unstage(path: "a.txt", in: repo.url)

            let entry = try #require(try await provider(repo).status(in: repo.url).entries.first { $0.path == "a.txt" })
            #expect(entry.index == .unmodified)
            #expect(entry.worktree == .modified)
        }
    }

    @Test func unstageAllKeepsWorkingTreeChanges() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try repo.write("b.txt", "v1\n")
            try await repo.git("add", "a.txt", "b.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")
            try repo.write("b.txt", "v2\n")
            try await repo.git("add", "a.txt", "b.txt")

            try await provider(repo).unstageAll(in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.entries.allSatisfy { !$0.isStaged })
            #expect(status.entries.map(\.path).sorted() == ["a.txt", "b.txt"])
            #expect(status.entries.allSatisfy { $0.hasUnstagedChanges })
        }
    }

    @Test func discardTrackedRestoresContent() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")

            let file = FileStatus(path: "a.txt", index: .unmodified, worktree: .modified)
            try await provider(repo).discard(file, in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.entries.isEmpty)
            let restored = try String(contentsOf: repo.url.appendingPathComponent("a.txt"), encoding: .utf8)
            #expect(restored == "v1\n")
        }
    }

    @Test func discardUntrackedDeletesFile() async throws {
        try await withTempRepo { repo in
            try repo.write("u.txt", "junk\n")

            let file = FileStatus(path: "u.txt", index: .unmodified, worktree: .untracked)
            try await provider(repo).discard(file, in: repo.url)

            #expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("u.txt").path))
            #expect(try await provider(repo).status(in: repo.url).entries.isEmpty)
        }
    }

    @Test func commitCreatesCommitAndCleansIndex() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "hello\n")
            try await provider(repo).stage(path: "a.txt", in: repo.url)

            try await provider(repo).commit(message: "add a", in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.entries.isEmpty)
            #expect(status.branch.oid != nil)
            let lastMessage = try await provider(repo).lastCommitMessage(in: repo.url)
            #expect(lastMessage == "add a")
        }
    }

    @Test func amendReplacesLastCommitMessage() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "hello\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "initial")

            try await provider(repo).amend(message: "amended", in: repo.url)

            let lastMessage = try await provider(repo).lastCommitMessage(in: repo.url)
            #expect(lastMessage == "amended")
        }
    }

    @Test func lastCommitMessageIsNilOnUnbornBranch() async throws {
        try await withTempRepo { repo in
            let lastMessage = try await provider(repo).lastCommitMessage(in: repo.url)
            #expect(lastMessage == nil)
        }
    }
}
