import Foundation
import Testing
@testable import GitKit

@Suite struct HistoryTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    @Test func historyReturnsNewestFirstWithParents() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "first")

            try repo.write("a.txt", "v2\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "second")

            let commits = try await provider(repo).history(in: repo.url, limit: 10)

            #expect(commits.count == 2)
            #expect(commits[0].subject == "second")
            #expect(commits[1].subject == "first")
            #expect(commits[0].parentOIDs == [commits[1].oid])
            #expect(commits[0].authorName == "Avi Test")
        }
    }

    @Test func historyIsEmptyOnUnbornBranch() async throws {
        try await withTempRepo { repo in
            let commits = try await provider(repo).history(in: repo.url, limit: 10)
            #expect(commits.isEmpty)
        }
    }

    @Test func changedFilesIncludesRootCommitAdditions() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "first")

            let commit = try #require(try await provider(repo).history(in: repo.url, limit: 10).first)
            let files = try await provider(repo).changedFiles(in: commit.oid, in: repo.url)

            #expect(files == [CommitFileChange(path: "a.txt", kind: .added)])
        }
    }

    @Test func commitDiffParsesChangedFilePatch() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "first")

            try repo.write("a.txt", "v2\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "second")

            let commit = try #require(try await provider(repo).history(in: repo.url, limit: 10).first)
            let files = try await provider(repo).changedFiles(in: commit.oid, in: repo.url)
            let file = try #require(files.first)
            let diff = try await provider(repo).diff(commitOID: commit.oid, path: file.path, in: repo.url)
            let additions = diff.hunks.flatMap(\.lines).filter { $0.kind == .addition }

            #expect(file.kind == .modified)
            #expect(additions.contains { $0.text == "v2" })
        }
    }
}
