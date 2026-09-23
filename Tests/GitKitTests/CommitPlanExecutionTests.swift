import Foundation
@testable import GitKit
import Testing

/// Runs commit plans against real throwaway repositories under /tmp.
struct CommitPlanExecutionTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    private func seed(_ repo: GitFixture, _ files: [String]) async throws {
        for file in files {
            try repo.write(file, "v1\n")
        }
        try await repo.git("add", "-A")
        try await repo.git("commit", "-q", "-m", "init")
    }

    private func changes(_ repo: GitFixture, at rev: String) async throws -> [String] {
        try await repo.git("show", "--name-status", "--format=", "--no-renames", rev)
            .stdoutString.split(separator: "\n").map { $0.replacingOccurrences(of: "\t", with: " ") }.sorted()
    }

    private func subjects(_ repo: GitFixture, count: Int) async throws -> [String] {
        try await repo.git("log", "-\(count)", "--format=%s").stdoutString.split(separator: "\n").map(String.init)
    }

    @Test func eachCommitTakesExactlyItsFiles() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt", "b.txt", "c.txt"])
            try repo.write("a.txt", "v2\n")
            try repo.write("b.txt", "v2\n")
            try repo.write("d.txt", "new\n")
            try FileManager.default.removeItem(at: repo.url.appendingPathComponent("c.txt"))

            let plan = FileCommitPlan(commits: [
                .init(files: ["a.txt", "d.txt"], message: "feat: first"),
                .init(files: ["b.txt", "c.txt"], message: "fix: second")
            ])
            try await provider(repo).commitFiles(plan, in: repo.url)

            #expect(try await subjects(repo, count: 2) == ["fix: second", "feat: first"])
            #expect(try await changes(repo, at: "HEAD~1") == ["A d.txt", "M a.txt"])
            #expect(try await changes(repo, at: "HEAD") == ["D c.txt", "M b.txt"])
            #expect(try await provider(repo).status(in: repo.url).entries.isEmpty)
        }
    }

    @Test func unrelatedStagedChangesStayStaged() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt", "e.txt"])
            try repo.write("a.txt", "v2\n")
            try repo.write("e.txt", "v2\n")
            try await repo.git("add", "e.txt")

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["a.txt"], message: "only a")]), in: repo.url)

            #expect(try await changes(repo, at: "HEAD") == ["M a.txt"])
            let e = try #require(try await provider(repo).status(in: repo.url).entries.first { $0.path == "e.txt" })
            #expect(e.index == .modified)
            #expect(e.worktree == .unmodified)
        }
    }

    @Test func partiallyStagedFileCommitsItsWorkingTreeContent() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt"])
            try repo.write("a.txt", "v2\n")
            try await repo.git("add", "a.txt")
            try repo.write("a.txt", "v3\n")

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["a.txt"], message: "a")]), in: repo.url)

            #expect(try await repo.git("show", "HEAD:a.txt").stdoutString == "v3\n")
            #expect(try await provider(repo).status(in: repo.url).entries.isEmpty)
        }
    }

    @Test func stagedRenameCommitsBothSides() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["old.txt"])
            try await repo.git("mv", "old.txt", "new.txt")

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["new.txt"], message: "rename")]), in: repo.url)

            #expect(try await repo.git("ls-tree", "--name-only", "HEAD").stdoutString == "new.txt\n")
            #expect(try await provider(repo).status(in: repo.url).entries.isEmpty)
        }
    }

    @Test func literalNamesAreNeverTreatedAsGlobs() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["[ab].txt", "a.txt"])
            try repo.write("[ab].txt", "v2\n")
            try repo.write("a.txt", "v2\n")

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["[ab].txt"], message: "literal")]), in: repo.url)

            #expect(try await changes(repo, at: "HEAD") == ["M [ab].txt"])
        }
    }

    @Test func filesInANewFolderAreListedAndCommittable() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["keep.txt"])
            try repo.write("Agents/One.swift", "1\n")
            try repo.write("Agents/Two.swift", "2\n")

            let paths = try await provider(repo).status(in: repo.url).entries.map(\.path).sorted()
            #expect(paths == ["Agents/One.swift", "Agents/Two.swift"])

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["Agents/One.swift"], message: "one")]), in: repo.url)
            #expect(try await changes(repo, at: "HEAD") == ["A Agents/One.swift"])
            #expect(try await provider(repo).status(in: repo.url).entries.map(\.path) == ["Agents/Two.swift"])
        }
    }

    @Test func workingTreeDiffCoversExactlyTheNamedFiles() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt", "b.txt", "gone.txt"])
            try repo.write("a.txt", "a changed\n")
            try await repo.git("add", "a.txt")
            try repo.write("a.txt", "a changed twice\n")
            try repo.write("b.txt", "b changed\n")
            try repo.write("new/c.txt", "brand new\n")
            try FileManager.default.removeItem(at: repo.url.appendingPathComponent("gone.txt"))

            let diff = try await provider(repo).workingTreeDiff(paths: ["a.txt", "gone.txt", "new/c.txt"], in: repo.url)

            #expect(diff.contains("+a changed twice"))
            #expect(diff.contains("deleted file mode"))
            #expect(diff.contains("+brand new"))
            #expect(!diff.contains("b changed"))
        }
    }

    @Test func longFileListsCommitThroughAPathspecFile() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["keep.txt"])
            let files = (0 ..< CLIGitProvider.inlinePathspecLimit + 20).map { "f\($0).txt" }
            for file in files {
                try repo.write(file, "x\n")
            }

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: files, message: "many")]), in: repo.url)

            #expect(try await changes(repo, at: "HEAD").count == files.count)
        }
    }

    @Test func firstCommitsOnAnUnbornBranch() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "a\n")
            try repo.write("b.txt", "b\n")

            let plan = FileCommitPlan(commits: [.init(files: ["a.txt"], message: "one"), .init(files: ["b.txt"], message: "two")])
            try await provider(repo).commitFiles(plan, in: repo.url)

            #expect(try await subjects(repo, count: 2) == ["two", "one"])
        }
    }

    @Test func failingHookStopsWithTheCompletedCount() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt", "b.txt", "c.txt"])
            let hooks = FileManager.default.temporaryDirectory.appendingPathComponent("avi-hooks-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: hooks) }
            let hook = hooks.appendingPathComponent("commit-msg")
            try "#!/bin/sh\nif grep -q reject \"$1\"; then echo 'rejected by hook' >&2; exit 1; fi\n"
                .write(to: hook, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            try await repo.git("config", "--local", "core.hooksPath", hooks.path)
            for file in ["a.txt", "b.txt", "c.txt"] {
                try repo.write(file, "v2\n")
            }

            let plan = FileCommitPlan(commits: [
                .init(files: ["a.txt"], message: "ok"),
                .init(files: ["b.txt"], message: "reject me"),
                .init(files: ["c.txt"], message: "never")
            ])
            do {
                try await provider(repo).commitFiles(plan, in: repo.url)
                Issue.record("The hook must stop the plan")
            } catch let error as CommitPlanError {
                #expect(error.completed == 1)
                #expect(error.total == 3)
                #expect(error.reason.contains("rejected by hook"))
            }
            #expect(try await subjects(repo, count: 1) == ["ok"])
            let remaining = try await provider(repo).status(in: repo.url).entries.map(\.path).sorted()
            #expect(remaining == ["b.txt", "c.txt"])
        }
    }

    @Test func invalidPlanNeverMutates() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt"])
            try repo.write("a.txt", "v2\n")
            let head = try await repo.git("rev-parse", "HEAD").stdoutString

            await #expect(throws: FileCommitPlan.ValidationError.unknownPaths(["missing.txt"])) {
                try await provider(repo).commitFiles(
                    FileCommitPlan(commits: [.init(files: ["a.txt", "missing.txt"], message: "x")]),
                    in: repo.url
                )
            }
            #expect(try await repo.git("rev-parse", "HEAD").stdoutString == head)
        }
    }

    @Test func unfinishedRebaseBlocksCommitting() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt"])
            try repo.write("a.txt", "v2\n")
            try FileManager.default.createDirectory(at: repo.url.appendingPathComponent(".git/rebase-merge"), withIntermediateDirectories: true)

            do {
                try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["a.txt"], message: "x")]), in: repo.url)
                Issue.record("An unfinished rebase must block the plan")
            } catch {
                #expect(error.localizedDescription.contains("Finish or abort"))
            }
            #expect(try await subjects(repo, count: 1) == ["init"])
        }
    }

    @Test func aLeftoverRebaseHeadDoesNotBlockCommitting() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt"])
            try repo.write("a.txt", "v2\n")
            // What a finished or abandoned rebase can leave behind for months.
            let head = try await repo.git("rev-parse", "HEAD").stdoutString
            try head.write(to: repo.url.appendingPathComponent(".git/REBASE_HEAD"), atomically: true, encoding: .utf8)

            try await provider(repo).commitFiles(FileCommitPlan(commits: [.init(files: ["a.txt"], message: "after an old rebase")]), in: repo.url)

            #expect(try await subjects(repo, count: 1) == ["after an old rebase"])
        }
    }

    @Test func progressReportsEachCommit() async throws {
        try await withTempRepo { repo in
            try await seed(repo, ["a.txt", "b.txt"])
            try repo.write("a.txt", "v2\n")
            try repo.write("b.txt", "v2\n")
            let reported = Reported()

            let plan = FileCommitPlan(commits: [.init(files: ["a.txt"], message: "a"), .init(files: ["b.txt"], message: "b")])
            try await provider(repo).commitFiles(plan, in: repo.url) { reported.append($0) }

            #expect(reported.values == [1, 2])
        }
    }
}

/// Holds the whole plan in one queue slot, so a concurrent read never lands
/// between two of its commits. Uses a recording executable, not Git.
struct CommitPlanQueueTests {
    @Test func planReservesTheQueueAcrossEveryStep() async throws {
        let fixture = try RecordingGit()
        let provider = CLIGitProvider(gitURL: fixture.executable)
        let plan = FileCommitPlan(commits: [
            .init(files: ["[draft]*.swift"], message: "first"),
            .init(files: ["b.swift"], message: "second")
        ])
        let apply = Task { try await provider.commitFiles(plan, in: fixture.root) }
        for _ in 0 ..< 200 {
            if FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("started").path) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let read = Task { try await CLIGitProvider(gitURL: fixture.executable).status(in: fixture.root) }
        try await apply.value
        _ = try await read.value

        let commands = try fixture.commands()
        #expect(commands.filter { $0.hasPrefix("--literal-pathspecs commit --only") }.count == 2)
        #expect(commands.contains("--literal-pathspecs commit --only -m first -- [draft]*.swift"))
        #expect(commands.last?.hasPrefix("status ") == true)
        #expect(commands.filter { $0.hasPrefix("status ") }.count == 2)
    }

    private struct RecordingGit {
        let root: URL
        let executable: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-plan-queue-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            executable = root.appendingPathComponent("recording-git")
            let script = """
            #!/bin/sh
            printf '%s\\n' "$*" >> commands
            case "$1" in
              status)
                if [ ! -e started ]; then touch started; sleep 0.2; fi
                printf '1 .M N... 100644 100644 100644 aaaaaaa bbbbbbb [draft]*.swift\\0001 .M N... 100644 100644 100644 aaaaaaa bbbbbbb b.swift\\000'
                ;;
              rev-parse)
                if [ "$2" = --verify ]; then exit 1; fi
                printf '%s/.git/%s\\n' "$PWD" "$4"
                ;;
              --literal-pathspecs) ;;
              *) printf 'unexpected fake command' >&2; exit 99 ;;
            esac
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func commands() throws -> [String] {
            try String(contentsOf: root.appendingPathComponent("commands"), encoding: .utf8)
                .split(separator: "\n").map(String.init)
        }
    }
}

private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int] = []

    func append(_ value: Int) {
        lock.withLock { storage.append(value) }
    }

    var values: [Int] {
        lock.withLock { storage }
    }
}
