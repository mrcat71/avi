import Foundation
@testable import GitKit
import Testing

struct DiffOptionsTests {
    @Test(arguments: [
        (DiffOptions.standard, ["--unified=3"]),
        (DiffOptions(contextLines: 0), ["--unified=0"]),
        (DiffOptions(contextLines: -2), ["--unified=0"]),
        (DiffOptions(contextLines: 10, wholeFile: true), ["--unified=1000000"]),
        (DiffOptions(contextLines: 5, ignoreWhitespace: true), ["--unified=5", "--ignore-all-space"])
    ])
    func optionsBecomeGitArguments(options: DiffOptions, expected: [String]) {
        #expect(options.arguments == expected)
    }

    /// Twelve lines; line 4's text changes and line 10 only gains indentation.
    private func changedFile(_ repo: GitFixture) async throws {
        let lines = (1 ... 12).map { "line \($0)" }
        try repo.write("f.txt", lines.joined(separator: "\n") + "\n")
        try await repo.git("add", "f.txt")
        try await repo.git("commit", "-q", "-m", "init")
        var changed = lines
        changed[3] = "line 4 changed"
        changed[9] = "    line 10"
        try repo.write("f.txt", changed.joined(separator: "\n") + "\n")
    }

    private func changes(_ diff: FileDiff) -> [String] {
        diff.hunks.flatMap(\.lines).filter { $0.kind == .addition }.map(\.text)
    }

    private func contextCount(_ diff: FileDiff) -> Int {
        diff.hunks.flatMap(\.lines).filter { $0.kind == .context }.count
    }

    @Test func contextWhitespaceAndWholeFileReachGit() async throws {
        try await withTempRepo { repo in
            try await changedFile(repo)
            let git = CLIGitProvider(gitURL: repo.gitURL)

            let standard = try await git.diff(path: "f.txt", source: .unstaged, options: .standard, in: repo.url)
            #expect(changes(standard) == ["line 4 changed", "    line 10"])

            let tight = try await git.diff(path: "f.txt", source: .unstaged, options: DiffOptions(contextLines: 0), in: repo.url)
            #expect(tight.hunks.count == 2)
            #expect(contextCount(tight) == 0)

            let noWhitespace = try await git.diff(
                path: "f.txt", source: .unstaged, options: DiffOptions(contextLines: 0, ignoreWhitespace: true), in: repo.url
            )
            #expect(changes(noWhitespace) == ["line 4 changed"])

            let whole = try await git.diff(path: "f.txt", source: .unstaged, options: DiffOptions(wholeFile: true), in: repo.url)
            #expect(whole.hunks.count == 1)
            // Every unchanged line comes back: 12 lines, two of them changed.
            #expect(contextCount(whole) == 10)

            try await repo.git("commit", "-q", "-am", "change")
            let head = try await repo.git("rev-parse", "HEAD").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let commit = try await git.diff(commitOID: head, path: "f.txt", options: DiffOptions(ignoreWhitespace: true), in: repo.url)
            #expect(changes(commit) == ["line 4 changed"])
            let renamedView = try await git.diff(commitOID: head, path: "f.txt", oldPath: nil, options: DiffOptions(contextLines: 0), in: repo.url)
            #expect(contextCount(renamedView) == 0)
        }
    }
}
