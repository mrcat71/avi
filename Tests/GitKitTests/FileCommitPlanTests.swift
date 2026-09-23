@testable import GitKit
import Testing

struct FileCommitPlanTests {
    @Test func acceptsDisjointCommitsAndLeavesUnlistedChangesAlone() throws {
        let status = status([
            modified("a.swift"), modified("b.swift"), untracked("new.swift"),
            FileStatus(path: "gone.swift", index: .unmodified, worktree: .deleted),
            untracked("notes.txt")
        ])
        let resolved = try plan([["a.swift", "new.swift"], ["b.swift", "gone.swift"]]).resolved(against: status)
        #expect(resolved.map(\.files) == [["a.swift", "new.swift"], ["b.swift", "gone.swift"]])
    }

    @Test(arguments: [
        ([], FileCommitPlan.ValidationError.noCommits),
        ([["a.swift"], []], .noFiles(commit: 2)),
        ([["a.swift", "other.swift"]], .unknownPaths(["other.swift"])),
        ([["a.swift"], ["b.swift", "a.swift"]], .duplicatePaths(["a.swift"])),
        ([[":(glob)*"]], .unknownPaths([":(glob)*"]))
    ] as [([[String]], FileCommitPlan.ValidationError)])
    func rejectsUnsafePlans(files: [[String]], expected: FileCommitPlan.ValidationError) {
        let status = status([modified("a.swift"), modified("b.swift")])
        #expect(throws: expected) { try plan(files).resolved(against: status) }
    }

    @Test func rejectsBlankMessages() {
        let blank = FileCommitPlan(commits: [.init(files: ["a.swift"], message: " \n")])
        #expect(throws: FileCommitPlan.ValidationError.emptyMessage(commit: 1)) {
            try blank.resolved(against: status([modified("a.swift")]))
        }
    }

    @Test func rejectsAnyConflictInTheWorkingCopy() {
        let status = status([
            modified("a.swift"),
            FileStatus(path: "c.swift", index: .updatedButUnmerged, worktree: .updatedButUnmerged)
        ])
        #expect(throws: FileCommitPlan.ValidationError.conflicts(["c.swift"])) {
            try plan([["a.swift"]]).resolved(against: status)
        }
    }

    @Test(arguments: [["new.swift"], ["old.swift"]])
    func eitherSideOfAStagedRenameBringsTheOther(listed: [String]) throws {
        let rename = FileStatus(path: "new.swift", originalPath: "old.swift", index: .renamed, worktree: .unmodified)
        let resolved = try plan([listed]).resolved(against: status([rename]))
        #expect(Set(resolved[0].files) == ["new.swift", "old.swift"])
    }

    @Test func renameSidesCannotBeSplitAcrossCommits() {
        let rename = FileStatus(path: "new.swift", originalPath: "old.swift", index: .renamed, worktree: .unmodified)
        #expect(throws: FileCommitPlan.ValidationError.self) {
            try plan([["new.swift"], ["old.swift"]]).resolved(against: status([rename]))
        }
    }

    @Test func repeatedPathInOneCommitIsKeptOnce() throws {
        let resolved = try plan([["a.swift", "a.swift"]]).resolved(against: status([modified("a.swift")]))
        #expect(resolved[0].files == ["a.swift"])
    }

    @Test func literalLookingNameIsAcceptedWhenItReallyChanged() throws {
        _ = try plan([["[draft]*.swift"]]).resolved(against: status([modified("[draft]*.swift")]))
    }

    private func plan(_ files: [[String]]) -> FileCommitPlan {
        FileCommitPlan(commits: files.map { .init(files: $0, message: "Commit") })
    }

    private func modified(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .unmodified, worktree: .modified)
    }

    private func untracked(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .untracked, worktree: .untracked)
    }

    private func status(_ entries: [FileStatus]) -> WorkingCopyStatus {
        WorkingCopyStatus(branch: BranchInfo(name: "main", oid: String(repeating: "a", count: 40)), entries: entries)
    }
}
