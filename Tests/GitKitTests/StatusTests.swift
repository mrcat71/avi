import Foundation
@testable import GitKit
import Testing

struct StatusTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    @Test func cleanRepoHasNoEntries() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "hello\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.entries.isEmpty)
        }
    }

    @Test func untrackedFileDetected() async throws {
        try await withTempRepo { repo in
            try repo.write("new.txt", "x\n")

            let status = try await provider(repo).status(in: repo.url)
            let entry = try #require(status.entries.first { $0.path == "new.txt" })
            #expect(entry.isUntracked)
            #expect(entry.worktree == .untracked)
            #expect(entry.index == .unmodified)
        }
    }

    @Test func stagedNewFileIsAdded() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "hello\n")
            try await repo.git("add", "a.txt")

            let status = try await provider(repo).status(in: repo.url)
            let entry = try #require(status.entries.first { $0.path == "a.txt" })
            #expect(entry.index == .added)
            #expect(entry.isStaged)
        }
    }

    @Test func unstagedModificationDetected() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")

            let status = try await provider(repo).status(in: repo.url)
            let entry = try #require(status.entries.first { $0.path == "a.txt" })
            #expect(entry.worktree == .modified)
            #expect(entry.index == .unmodified)
            #expect(entry.hasUnstagedChanges)
        }
    }

    @Test func stagedModificationDetected() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "v2\n")
            try await repo.git("add", "a.txt")

            let status = try await provider(repo).status(in: repo.url)
            let entry = try #require(status.entries.first { $0.path == "a.txt" })
            #expect(entry.index == .modified)
            #expect(entry.worktree == .unmodified)
            #expect(entry.isStaged)
        }
    }

    @Test func renameDetectedWithOriginalPath() async throws {
        try await withTempRepo { repo in
            try repo.write("old.txt", "content\n")
            try await repo.git("add", "old.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try await repo.git("mv", "old.txt", "new.txt")

            let status = try await provider(repo).status(in: repo.url)
            let entry = try #require(status.entries.first { $0.path == "new.txt" })
            #expect(entry.index == .renamed)
            #expect(entry.originalPath == "old.txt")
        }
    }
}
