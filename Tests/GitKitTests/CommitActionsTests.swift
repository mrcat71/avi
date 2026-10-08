import Foundation
@testable import GitKit
import Testing

/// History's commit menu, run against real throwaway repositories.
struct CommitActionsTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    private func head(_ repo: GitFixture, _ revision: String = "HEAD") async throws -> String {
        try await repo.git("rev-parse", revision).stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func subject(_ repo: GitFixture) async throws -> String {
        try await repo.git("log", "-1", "--format=%s").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// main: "base" with a.txt = "one"; feature: one more commit from `featureEdit`.
    private func makeBranches(_ repo: GitFixture, mainEdit: String? = nil, featureEdit: (String, String)) async throws -> String {
        try repo.write("a.txt", "one\n")
        try await repo.git("add", ".")
        try await repo.git("commit", "-q", "-m", "base")
        try await repo.git("branch", "-M", "main")
        try await repo.git("switch", "-q", "-c", "feature")
        try repo.write(featureEdit.0, featureEdit.1)
        try await repo.git("add", ".")
        try await repo.git("commit", "-q", "-m", "feature change")
        let picked = try await head(repo)
        try await repo.git("switch", "-q", "main")
        if let mainEdit {
            try repo.write("a.txt", mainEdit)
            try await repo.git("commit", "-q", "-am", "main change")
        }
        return picked
    }

    @Test func cherryPickCopiesTheCommitOntoHead() async throws {
        try await withTempRepo { repo in
            let picked = try await makeBranches(repo, featureEdit: ("b.txt", "new\n"))

            let outcome = try await provider(repo).cherryPick(commit: picked, isMerge: false, in: repo.url)

            #expect(outcome == .completed)
            #expect(try repo.read("b.txt") == "new\n")
            #expect(try await subject(repo) == "feature change")
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
        }
    }

    @Test func cherryPickConflictStopsThenAborts() async throws {
        try await withTempRepo { repo in
            let picked = try await makeBranches(repo, mainEdit: "main\n", featureEdit: ("a.txt", "feature\n"))
            let before = try await head(repo)

            let outcome = try await provider(repo).cherryPick(commit: picked, isMerge: false, in: repo.url)

            guard case .stopped = outcome else {
                Issue.record("expected the cherry-pick to stop, got \(outcome)")
                return
            }
            #expect(try await provider(repo).operationState(in: repo.url) == .cherryPick)
            try await provider(repo).abortOperation(.cherryPick, in: repo.url)
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
            #expect(try await head(repo) == before)
            #expect(try repo.read("a.txt") == "main\n")
        }
    }

    @Test func cherryPickConflictSkips() async throws {
        try await withTempRepo { repo in
            let picked = try await makeBranches(repo, mainEdit: "main\n", featureEdit: ("a.txt", "feature\n"))
            _ = try await provider(repo).cherryPick(commit: picked, isMerge: false, in: repo.url)

            let outcome = try await provider(repo).skipOperation(.cherryPick, in: repo.url)

            #expect(outcome == .completed)
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
            #expect(try repo.read("a.txt") == "main\n")
        }
    }

    @Test func revertUndoesTheCommit() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "one\n")
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "base")
            try repo.write("a.txt", "two\n")
            try await repo.git("commit", "-q", "-am", "change")
            let change = try await head(repo)

            let outcome = try await provider(repo).revert(commit: change, isMerge: false, in: repo.url)

            #expect(outcome == .completed)
            #expect(try repo.read("a.txt") == "one\n")
            #expect(try await subject(repo) == "Revert \"change\"")
        }
    }

    @Test func revertConflictStopsAndContinuesOnceResolved() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "one\n")
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "base")
            try repo.write("a.txt", "two\n")
            try await repo.git("commit", "-q", "-am", "first")
            let first = try await head(repo)
            try repo.write("a.txt", "three\n")
            try await repo.git("commit", "-q", "-am", "second")

            let outcome = try await provider(repo).revert(commit: first, isMerge: false, in: repo.url)
            guard case .stopped = outcome else {
                Issue.record("expected the revert to stop, got \(outcome)")
                return
            }
            #expect(try await provider(repo).operationState(in: repo.url) == .revert)

            try repo.write("a.txt", "resolved\n")
            try await repo.git("add", "a.txt")
            let resumed = try await provider(repo).continueOperation(.revert, in: repo.url)

            #expect(resumed == .completed)
            #expect(try await provider(repo).operationState(in: repo.url) == nil)
            #expect(try await subject(repo) == "Revert \"first\"")
        }
    }

    @Test func formatPatchExportsTheCommit() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "one\n")
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "base")
            let oid = try await head(repo)

            let patch = try await String(decoding: provider(repo).formatPatch(commit: oid, in: repo.url), as: UTF8.self)

            #expect(patch.hasPrefix("From \(oid)"))
            #expect(patch.contains("Subject: [PATCH] base"))
            #expect(patch.contains("+one"))
        }
    }

    @Test func checkoutDetachedDetachesHeadAtTheCommit() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "one\n")
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "base")
            let base = try await head(repo)
            try repo.write("a.txt", "two\n")
            try await repo.git("commit", "-q", "-am", "next")

            try await provider(repo).checkoutDetached(commit: base, in: repo.url)

            #expect(try await head(repo) == base)
            let symbolic = try await repo.git("rev-parse", "--abbrev-ref", "HEAD").stdoutString
            #expect(symbolic.trimmingCharacters(in: .whitespacesAndNewlines) == "HEAD")
        }
    }

    @Test func compareWithWorkingTreeListsLaterAndLocalChanges() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "one\n")
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "base")
            let base = try await head(repo)
            try repo.write("b.txt", "later\n")
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "later")
            try repo.write("a.txt", "local\n")

            let files = try await provider(repo).changedFilesAgainstWorkingTree(from: base, in: repo.url)
            #expect(files.map(\.path).sorted() == ["a.txt", "b.txt"])

            let diff = try await provider(repo).diffAgainstWorkingTree(from: base, path: "a.txt", oldPath: nil, options: .standard, in: repo.url)
            let lines = diff.hunks.flatMap(\.lines)
            #expect(lines.contains { $0.kind == .deletion && $0.text == "one" })
            #expect(lines.contains { $0.kind == .addition && $0.text == "local" })
        }
    }

    @Test func rebaseCandidatesFromACommitListTheCommitsAfterIt() async throws {
        try await withTempRepo { repo in
            for name in ["base", "second", "third"] {
                try repo.write("\(name).txt", name)
                try await repo.git("add", ".")
                try await repo.git("commit", "-q", "-m", name)
            }
            let base = try await head(repo, "HEAD~2")

            let commits = try await provider(repo).rebaseCandidates(ontoRevision: base, in: repo.url)

            #expect(commits.map(\.subject) == ["second", "third"])
        }
    }
}
