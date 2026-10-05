import Foundation
@testable import GitKit
import Testing

/// The changed-file menu's actions against real repositories under /tmp.
struct FileActionTests {
    @Test func stashTakesOnlyTheChosenFiles() async throws {
        try await withCommittedFiles { repo in
            try repo.write("a.txt", "a2\n")
            try repo.write("b.txt", "b2\n")
            try repo.write("new.txt", "new\n")

            try await provider(repo).stash(paths: ["a.txt", "new.txt"], message: "two files", includeUntracked: true, in: repo.url)

            let changed = try await provider(repo).status(in: repo.url).entries.map(\.path)
            #expect(changed == ["b.txt"])
            let stashes = try await provider(repo).stashes(in: repo.url)
            #expect(stashes.count == 1)
            #expect(stashes.first?.subject.hasSuffix("two files") == true)
        }
    }

    @Test func stashTreatsPathsLiterally() async throws {
        try await withCommittedFiles { repo in
            try repo.write("a.txt", "a2\n")
            try repo.write("[ab].txt", "glob\n")
            try await repo.git("add", "[ab].txt")

            try await provider(repo).stash(paths: ["[ab].txt"], message: nil, includeUntracked: false, in: repo.url)

            // A glob would have matched a.txt too.
            #expect(try await provider(repo).status(in: repo.url).entries.map(\.path) == ["a.txt"])
        }
    }

    @Test func unstagedPatchRecreatesTheChangesIncludingNewFiles() async throws {
        try await withCommittedFiles { repo in
            try repo.write("a.txt", "a2\n")
            try repo.write("new.txt", "new\n")
            let files = try await provider(repo).status(in: repo.url).entries

            let patch = try await provider(repo).patch(for: files, staged: false, in: repo.url)

            try await repo.git("restore", "a.txt")
            try FileManager.default.removeItem(at: repo.url.appendingPathComponent("new.txt"))
            let patchURL = repo.url.appendingPathComponent("../avi-\(UUID().uuidString).patch").standardizedFileURL
            defer { try? FileManager.default.removeItem(at: patchURL) }
            try patch.write(to: patchURL)
            try await repo.git("apply", patchURL.path)
            #expect(try repo.read("a.txt") == "a2\n")
            #expect(try repo.read("new.txt") == "new\n")
        }
    }

    @Test func stagedPatchHoldsOnlyWhatIsStaged() async throws {
        try await withCommittedFiles { repo in
            try repo.write("a.txt", "staged\n")
            try await repo.git("add", "a.txt")
            try repo.write("a.txt", "staged and more\n")
            let files = try await provider(repo).status(in: repo.url).entries

            let patch = try await String(decoding: provider(repo).patch(for: files, staged: true, in: repo.url), as: UTF8.self)

            #expect(patch.contains("+staged\n"))
            #expect(!patch.contains("and more"))
        }
    }

    @Test func fileHistoryFollowsARename() async throws {
        try await withTempRepo { repo in
            try await commit(repo, "old.txt", "1\n", "create")
            try await commit(repo, "old.txt", "1\n2\n", "extend")
            try await repo.git("mv", "old.txt", "new.txt")
            try await repo.git("commit", "-q", "-m", "rename")
            try await commit(repo, "new.txt", "1\n2\n3\n", "extend again")
            try await commit(repo, "other.txt", "x\n", "unrelated")

            let history = try await provider(repo).fileHistory(path: "new.txt", limit: 50, in: repo.url)

            #expect(history.map(\.commit.subject) == ["extend again", "rename", "extend", "create"])
            #expect(history.map(\.path) == ["new.txt", "new.txt", "old.txt", "old.txt"])
            #expect(history[1].kind == .renamed)
            #expect(history[1].oldPath == "old.txt")
            #expect(history[3].kind == .added)

            let renameDiff = try await provider(repo).diff(
                commitOID: history[2].commit.oid, path: history[2].path, oldPath: history[2].oldPath, in: repo.url
            )
            #expect(renameDiff.hunks.flatMap(\.lines).contains { $0.kind == .addition && $0.text == "2" })
        }
    }

    @Test func fileHistoryIsEmptyBeforeTheFirstCommit() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "a\n")
            #expect(try await provider(repo).fileHistory(path: "a.txt", limit: 10, in: repo.url).isEmpty)
        }
    }

    @Test func blameMarksLinesYouHaveNotCommitted() async throws {
        try await withTempRepo { repo in
            try await commit(repo, "a.txt", "one\ntwo\nthree\n", "first")
            try repo.write("a.txt", "one\nTWO\nthree\n")

            let lines = try await provider(repo).blame(path: "a.txt", revision: nil, in: repo.url)

            #expect(lines.map(\.content) == ["one", "TWO", "three"])
            #expect(lines.map(\.lineNumber) == [1, 2, 3])
            #expect(lines[1].commit.isUncommitted)
            #expect(!lines[0].commit.isUncommitted)
            #expect(lines[0].commit.summary == "first")
            #expect(lines[0].commit.author == "Avi Test")
            #expect(lines[0].commit.authorDate != nil)
        }
    }

    @Test func blameAtACommitShowsThatVersion() async throws {
        try await withTempRepo { repo in
            try await commit(repo, "a.txt", "one\n", "first")
            let first = try await repo.git("rev-parse", "HEAD").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            try await commit(repo, "a.txt", "one\ntwo\n", "second")

            let lines = try await provider(repo).blame(path: "a.txt", revision: first, in: repo.url)

            #expect(lines.map(\.content) == ["one"])
            #expect(lines[0].commit.oid == first)
        }
    }

    @Test func blameTakesOnlyFullCommitIDs() async throws {
        try await withCommittedFiles { repo in
            for revision in ["HEAD", "--reverse", "main"] {
                await #expect(throws: GitError.self) {
                    try await provider(repo).blame(path: "a.txt", revision: revision, in: repo.url)
                }
            }
        }
    }

    @Test func externalDiffRunsTheConfiguredToolWithBothVersions() async throws {
        try await withCommittedFiles { repo in
            try repo.write("a.txt", "changed\n")
            let scratch = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-difftool-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let tool = scratch.appendingPathComponent("record tool.sh")
            let record = scratch.appendingPathComponent("args")
            try "#!/bin/sh\nprintf '%s\\n' \"$1\" \"$2\" > '\(record.path)'\n".write(to: tool, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

            try await provider(repo).launchDiffTool(path: "a.txt", staged: false, toolPath: tool.path, in: repo.url)

            let arguments = try String(contentsOf: record, encoding: .utf8).split(separator: "\n")
            #expect(arguments.count == 2)
            #expect(arguments.last?.hasSuffix("a.txt") == true)
        }
    }

    @Test func detectsAMergeOrRebaseFromTheGitDir() throws {
        let gitDir = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-gitdir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: gitDir) }
        #expect(GitOperationState.detect(gitDir: gitDir) == nil)

        FileManager.default.createFile(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path, contents: Data())
        #expect(GitOperationState.detect(gitDir: gitDir) == .merge)

        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("rebase-apply"), withIntermediateDirectories: true)
        #expect(GitOperationState.detect(gitDir: gitDir) == .rebase)

        // `git am` uses the same folder; Avi does not drive it.
        FileManager.default.createFile(atPath: gitDir.appendingPathComponent("rebase-apply/applying").path, contents: Data())
        #expect(GitOperationState.detect(gitDir: gitDir) == .merge)
    }

    // MARK: Helpers

    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    private func commit(_ repo: GitFixture, _ file: String, _ content: String, _ message: String) async throws {
        try repo.write(file, content)
        try await repo.git("add", "--", file)
        try await repo.git("commit", "-q", "-m", message)
    }

    private func withCommittedFiles(_ body: (GitFixture) async throws -> Void) async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "a\n")
            try repo.write("b.txt", "b\n")
            try await repo.git("add", "a.txt", "b.txt")
            try await repo.git("commit", "-q", "-m", "initial")
            try await repo.git("branch", "-M", "main")
            try await body(repo)
        }
    }
}
