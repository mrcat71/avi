import Foundation
import Testing
@testable import GitKit

@Suite struct DiffTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    @Test func unstagedDiffShowsAddedAndRemovedLines() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "line1\nline2\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "line1\nline2 changed\n")

            let diff = try await provider(repo).diff(path: "a.txt", source: .unstaged, in: repo.url)
            let kinds = diff.hunks.flatMap { $0.lines.map(\.kind) }
            #expect(kinds.contains(.deletion))
            #expect(kinds.contains(.addition))
        }
    }

    @Test func stagedDiffShowsStagedContent() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "line1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "init")
            try repo.write("a.txt", "line1\nadded\n")
            try await repo.git("add", "a.txt")

            let diff = try await provider(repo).diff(path: "a.txt", source: .staged, in: repo.url)
            let additions = diff.hunks.flatMap { $0.lines }.filter { $0.kind == .addition }
            #expect(additions.contains { $0.text == "added" })
        }
    }

    @Test func untrackedDiffRendersFileAsAdditions() async throws {
        try await withTempRepo { repo in
            try repo.write("u.txt", "new content\n")

            let diff = try await provider(repo).diff(path: "u.txt", source: .untracked, in: repo.url)
            let additions = diff.hunks.flatMap { $0.lines }.filter { $0.kind == .addition }
            #expect(additions.contains { $0.text == "new content" })
        }
    }

    @Test func repositoryRootResolvesToFixture() async throws {
        try await withTempRepo { repo in
            let root = try await provider(repo).repositoryRoot(for: repo.url)
            #expect(root.resolvingSymlinksInPath().path == repo.url.resolvingSymlinksInPath().path)
        }
    }

    @Test func repositoryRootFailsOutsideRepo() async throws {
        let dir = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-nonrepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        await #expect(throws: GitError.self) {
            _ = try await CLIGitProvider().repositoryRoot(for: dir)
        }
    }
}
