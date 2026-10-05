import Foundation
@testable import GitKit
import Testing

struct BlameParserTests {
    private let first = String(repeating: "a", count: 40)
    private let uncommitted = String(repeating: "0", count: 40)

    @Test func reusesCommitDetailsGitPrintsOnlyOnce() throws {
        let output = """
        \(first) 1 1 2
        author Ada
        author-mail <ada@example.com>
        author-time 1700000000
        author-tz +0000
        summary First commit
        filename a.txt
        \tline one
        \(first) 2 2
        \tline two
        \(uncommitted) 3 3 1
        author Not Committed Yet
        author-mail <not.committed.yet>
        author-time 1700000100
        summary Version of a.txt from a.txt
        filename a.txt
        \t
        """

        let lines = try BlameParser.parse(Data(output.utf8))

        #expect(lines.map(\.lineNumber) == [1, 2, 3])
        #expect(lines.map(\.content) == ["line one", "line two", ""])
        #expect(lines[1].commit.author == "Ada")
        #expect(lines[1].commit.authorEmail == "ada@example.com")
        #expect(lines[1].commit.summary == "First commit")
        #expect(lines[1].commit.authorDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!lines[0].commit.isUncommitted)
        #expect(lines[2].commit.isUncommitted)
    }

    @Test func keepsTabsInsideALine() throws {
        let output = "\(first) 1 1 1\nauthor Ada\nsummary s\n\t\tindented\twith tabs\n"
        #expect(try BlameParser.parse(Data(output.utf8)).first?.content == "\tindented\twith tabs")
    }

    @Test func rejectsAHeaderThatIsNotACommit() {
        #expect(throws: GitError.self) {
            try BlameParser.parse(Data("HEAD 1 1 1\n\tline\n".utf8))
        }
    }
}

struct FileHistoryParserTests {
    private let newer = String(repeating: "b", count: 40)
    private let older = String(repeating: "a", count: 40)

    @Test func readsPathsAcrossARename() throws {
        let data = record(newer, parents: older, subject: "rename", body: "why\n", fields: ["\nR100", "old.txt", "new.txt"])
            + record(older, parents: "", subject: "create", body: "", fields: ["\nA", "old.txt"])

        let entries = try FileHistoryParser.parse(data, path: "new.txt")

        #expect(entries.map(\.commit.oid) == [newer, older])
        #expect(entries[0].kind == .renamed)
        #expect(entries[0].path == "new.txt")
        #expect(entries[0].oldPath == "old.txt")
        #expect(entries[0].commit.body == "why")
        #expect(entries[1].path == "old.txt")
        #expect(entries[1].kind == .added)
        #expect(entries[1].commit.parentOIDs.isEmpty)
    }

    @Test func aCommitWithoutAChangeKeepsTheNewerName() throws {
        let data = record(newer, parents: older, subject: "rename", body: "", fields: ["\nR090", "old.txt", "new.txt"])
            + record(older, parents: "", subject: "merge", body: "", fields: [])

        let entries = try FileHistoryParser.parse(data, path: "new.txt")

        #expect(entries[1].path == "old.txt")
        #expect(entries[1].kind == .unknown)
    }

    private func record(_ oid: String, parents: String, subject: String, body: String, fields: [String]) -> Data {
        var data = Data("\u{1E}\(oid)\u{1F}\(parents)\u{1F}Ada\u{1F}ada@example.com\u{1F}2026-01-02T03:04:05+00:00\u{1F}\(subject)\u{1F}\(body)\u{1D}".utf8)
        data.append(0)
        for field in fields {
            data.append(Data(field.utf8))
            data.append(0)
        }
        return data
    }
}

struct GitIgnoreTests {
    @Test func exactPatternsAreAnchoredAndEscaped() throws {
        #expect(try GitIgnore.pattern(forPath: "docs/README.md", isDirectory: false) == "/docs/README.md")
        #expect(try GitIgnore.pattern(forPath: "build", isDirectory: true) == "/build/")
        #expect(try GitIgnore.pattern(forPath: "a/[draft]*?.txt", isDirectory: false) == "/a/\\[draft]\\*\\?.txt")
        #expect(try GitIgnore.pattern(forPath: "!important", isDirectory: false) == "/!important")
        #expect(try GitIgnore.pattern(forPath: "trailing  ", isDirectory: false) == "/trailing\\ \\ ")
        #expect(throws: GitError.self) {
            try GitIgnore.pattern(forPath: "bad\nname", isDirectory: false)
        }
    }

    @Test func extensionPatternsSkipNamesWithoutOne() {
        #expect(GitIgnore.extensionPattern(forPath: "a/b/c.log") == "*.log")
        #expect(GitIgnore.extensionPattern(forPath: "archive.tar.gz") == "*.gz")
        #expect(GitIgnore.extensionPattern(forPath: "Makefile") == nil)
        #expect(GitIgnore.extensionPattern(forPath: "config/.env") == nil)
    }

    @Test func parentFoldersAreNearestFirst() {
        #expect(GitIgnore.parentFolders(of: "a/b/c.txt") == ["a/b", "a"])
        #expect(GitIgnore.parentFolders(of: "top.txt").isEmpty)
    }

    @Test func appendAddsALineOnceAndKeepsTheFileIntact() throws {
        let folder = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-ignore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("info/exclude")

        #expect(try GitIgnore.append("*.log", to: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "*.log\n")

        // A file without a final newline gets one before the new line.
        try "*.log\n/build".write(to: file, atomically: true, encoding: .utf8)
        #expect(try GitIgnore.append("/dist/", to: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "*.log\n/build\n/dist/\n")

        #expect(try !GitIgnore.append("/build", to: file))
        #expect(try String(contentsOf: file, encoding: .utf8) == "*.log\n/build\n/dist/\n")
    }
}

struct InteractiveRebasePlanTests {
    private let a = String(repeating: "a", count: 40)
    private let b = String(repeating: "b", count: 40)
    private let c = String(repeating: "c", count: 40)

    @Test func writesTheTodoInYourOrderWithAnAmendForEachReword() throws {
        let plan = try InteractiveRebasePlan(original: [a, b, c], items: [
            RebaseTodoItem(oid: c, action: .reword("New message")),
            RebaseTodoItem(oid: a, action: .pick),
            RebaseTodoItem(oid: b, action: .squash)
        ])

        #expect(plan.todo == """
        pick \(c)
        exec \(InteractiveRebasePlan.amendCommand(for: c))
        pick \(a)
        squash \(b)

        """)
        #expect(plan.messages == [c: "New message"])
        #expect(plan.expectedListing == "\(a)\n\(b)\n\(c)\n")
    }

    @Test func refusesPlansGitCannotRunOrThatLoseCommits() {
        let invalid: [[RebaseTodoItem]] = [
            [RebaseTodoItem(oid: a, action: .squash), RebaseTodoItem(oid: b)],
            [RebaseTodoItem(oid: a, action: .drop), RebaseTodoItem(oid: b, action: .fixup)],
            [RebaseTodoItem(oid: a, action: .reword("  \n")), RebaseTodoItem(oid: b)],
            [RebaseTodoItem(oid: a)],
            [RebaseTodoItem(oid: a), RebaseTodoItem(oid: a)],
            [RebaseTodoItem(oid: a), RebaseTodoItem(oid: c)]
        ]
        for items in invalid {
            #expect(throws: GitError.self) {
                try InteractiveRebasePlan(original: [a, b], items: items)
            }
        }
        #expect(throws: GitError.self) {
            try InteractiveRebasePlan(original: ["HEAD"], items: [RebaseTodoItem(oid: "HEAD")])
        }
    }

    @Test func sequenceEditorRefusesAChangedListAndInstallsThePlanOtherwise() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("avi-irebase-\(UUID().uuidString)")
        let rebaseState = directory.appendingPathComponent("rebase-merge")
        try FileManager.default.createDirectory(at: rebaseState, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try InteractiveRebasePlan(original: [a, b], items: [
            RebaseTodoItem(oid: b, action: .reword("B")),
            RebaseTodoItem(oid: a, action: .drop)
        ])
        let script = directory.appendingPathComponent("editor.sh")
        let expected = directory.appendingPathComponent("expected")
        let todo = directory.appendingPathComponent("todo")
        let messages = directory.appendingPathComponent("messages")
        let live = rebaseState.appendingPathComponent("git-rebase-todo")
        try InteractiveRebasePlan.sequenceEditorScript.write(to: script, atomically: true, encoding: .utf8)
        try plan.expectedListing.write(to: expected, atomically: true, encoding: .utf8)
        try plan.todo.write(to: todo, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        try "B".write(to: messages.appendingPathComponent(b), atomically: true, encoding: .utf8)
        let arguments = [script.path, expected.path, todo.path, messages.path, live.path]

        let moved = "pick \(a) A\npick \(b) B\npick \(c) new\n"
        try moved.write(to: live, atomically: true, encoding: .utf8)
        let refused = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: arguments)
        #expect(refused.exitCode != 0)
        #expect(try String(contentsOf: live, encoding: .utf8) == moved)

        try "pick \(a) A # empty\n\n# Commands:\npick \(b) B\n".write(to: live, atomically: true, encoding: .utf8)
        let accepted = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: arguments)
        #expect(accepted.exitCode == 0)
        #expect(try String(contentsOf: live, encoding: .utf8) == plan.todo)
        #expect(FileManager.default.fileExists(atPath: rebaseState.appendingPathComponent("avi-messages/\(b)").path))
    }
}
