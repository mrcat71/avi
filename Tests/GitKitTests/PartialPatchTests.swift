import Foundation
@testable import GitKit
import Testing

/// Staging, unstaging, and discarding picked lines, applied by real Git.
struct PartialPatchTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    private static let base = (1 ... 20).map { "line \($0)" }

    private func file(_ lines: [String], trailingNewline: Bool = true) -> String {
        lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    }

    /// Commits the twenty-line file, then writes `edited` over it.
    private func commitBase(_ repo: GitFixture, edited: [String], trailingNewline: Bool = true) async throws {
        try repo.write("a.txt", file(Self.base))
        try await repo.git("add", ".")
        try await repo.git("commit", "-q", "-m", "base")
        try repo.write("a.txt", file(edited, trailingNewline: trailingNewline))
    }

    private func index(_ repo: GitFixture) async throws -> String {
        try await repo.git("show", ":a.txt").stdoutString
    }

    /// The keys of the diff's lines whose text is in `texts`.
    private func keys(_ diff: FileDiff, _ texts: Set<String>, side: DiffLineKey.Side? = nil) -> Set<DiffLineKey> {
        Set(diff.hunks.flatMap(\.lines).compactMap { line in
            guard texts.contains(line.text), let key = DiffLineKey(line), side == nil || key.side == side else { return nil }
            return key
        })
    }

    private func apply(_ repo: GitFixture, source: DiffSource, picking texts: Set<String>, side: DiffLineKey.Side? = nil,
                       direction: PartialPatch.Direction, toIndex: Bool) async throws {
        let diff = try await provider(repo).diff(path: "a.txt", source: source, options: .standard, in: repo.url)
        let patch = try #require(PartialPatch.make(diff: diff, path: "a.txt", selection: keys(diff, texts, side: side), direction: direction))
        try await provider(repo).applyPatch(patch, toIndex: toIndex, reverse: direction == .reverse, in: repo.url)
    }

    @Test func stagingOneAdditionLeavesTheOtherUnstaged() async throws {
        try await withTempRepo { repo in
            var edited = Self.base
            edited.insert("added early", at: 3)
            edited.insert("added late", at: 17)
            try await commitBase(repo, edited: edited)

            try await apply(repo, source: .unstaged, picking: ["added early"], direction: .forward, toIndex: true)

            var staged = Self.base
            staged.insert("added early", at: 3)
            #expect(try await index(repo) == file(staged))
            #expect(try repo.read("a.txt") == file(edited))
        }
    }

    @Test func stagingALineInTheSecondHunkOnly() async throws {
        try await withTempRepo { repo in
            var edited = Self.base
            edited.insert("added early", at: 3)
            edited.insert("added late", at: 17)
            try await commitBase(repo, edited: edited)

            try await apply(repo, source: .unstaged, picking: ["added late"], direction: .forward, toIndex: true)

            var staged = Self.base
            staged.insert("added late", at: 16)
            #expect(try await index(repo) == file(staged))
        }
    }

    @Test func stagingOneRemovalKeepsTheOtherLineInTheIndex() async throws {
        try await withTempRepo { repo in
            let edited = Self.base.filter { $0 != "line 2" && $0 != "line 16" }
            try await commitBase(repo, edited: edited)

            try await apply(repo, source: .unstaged, picking: ["line 2"], direction: .forward, toIndex: true)

            #expect(try await index(repo) == file(Self.base.filter { $0 != "line 2" }))
        }
    }

    @Test func stagingOnlyTheNewSideOfAReplacementKeepsTheOldLine() async throws {
        try await withTempRepo { repo in
            var edited = Self.base
            edited[4] = "LINE 5"
            try await commitBase(repo, edited: edited)

            try await apply(repo, source: .unstaged, picking: ["LINE 5"], side: .added, direction: .forward, toIndex: true)

            var staged = Self.base
            staged.insert("LINE 5", at: 5)
            #expect(try await index(repo) == file(staged))
        }
    }

    @Test func stagingTheLastLineOfAFileWithoutATrailingNewline() async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", file(Self.base, trailingNewline: false))
            try await repo.git("add", ".")
            try await repo.git("commit", "-q", "-m", "base")
            try repo.write("a.txt", file(Self.base + ["line 21"], trailingNewline: false))

            let diff = try await provider(repo).diff(path: "a.txt", source: .unstaged, options: .standard, in: repo.url)
            let picks = Set(diff.hunks.flatMap(\.lines).compactMap(DiffLineKey.init))
            let patch = try #require(PartialPatch.make(diff: diff, path: "a.txt", selection: picks, direction: .forward))
            try await provider(repo).applyPatch(patch, toIndex: true, reverse: false, in: repo.url)

            #expect(try await index(repo) == file(Self.base + ["line 21"], trailingNewline: false))
        }
    }

    @Test func unstagingOneLineKeepsTheRestStaged() async throws {
        try await withTempRepo { repo in
            var edited = Self.base
            edited.insert("added early", at: 3)
            edited.insert("added late", at: 17)
            try await commitBase(repo, edited: edited)
            try await repo.git("add", "a.txt")

            try await apply(repo, source: .staged, picking: ["added early"], direction: .reverse, toIndex: true)

            var staged = Self.base
            staged.insert("added late", at: 16)
            #expect(try await index(repo) == file(staged))
            #expect(try repo.read("a.txt") == file(edited))
        }
    }

    @Test func discardingOneLineLeavesTheOtherChange() async throws {
        try await withTempRepo { repo in
            var edited = Self.base.filter { $0 != "line 2" }
            edited.insert("added late", at: 16)
            try await commitBase(repo, edited: edited)

            try await apply(repo, source: .unstaged, picking: ["line 2"], direction: .reverse, toIndex: false)

            var kept = Self.base
            kept.insert("added late", at: 17)
            #expect(try repo.read("a.txt") == file(kept))
            #expect(try await index(repo) == file(Self.base))
        }
    }

    @Test func noPickedChangeMakesNoPatch() async throws {
        try await withTempRepo { repo in
            var edited = Self.base
            edited.insert("added", at: 3)
            try await commitBase(repo, edited: edited)
            let diff = try await provider(repo).diff(path: "a.txt", source: .unstaged, options: .standard, in: repo.url)

            #expect(PartialPatch.make(diff: diff, path: "a.txt", selection: [], direction: .forward) == nil)
            #expect(PartialPatch.make(diff: diff, path: "a.txt", selection: [DiffLineKey(side: .added, number: 99)], direction: .forward) == nil)
        }
    }
}
