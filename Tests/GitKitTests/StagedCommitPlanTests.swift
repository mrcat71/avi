import Foundation
@testable import GitKit
import XCTest

final class StagedCommitPlanTests: XCTestCase {
    func testAcceptsExactPartitionAndUnrelatedUntrackedFiles() throws {
        let status = status([
            file("a.swift"), file("b.swift"),
            FileStatus(path: "notes", index: .untracked, worktree: .untracked)
        ])
        try plan([["a.swift"], ["b.swift"]]).validate(status: status, currentDiff: "reviewed")
    }

    func testRejectsUnsafeGroupsBeforeMutations() {
        let status = status([file("a.swift"), file("b.swift")])
        for groups in [[], [["a.swift"]], [["a.swift"], ["a.swift", "b.swift"]],
                       [["a.swift", "b.swift", "other"]], [[":(glob)*"]],
                       [["a.swift", "b.swift"], []]] as [[[String]]] {
            XCTAssertThrowsError(try plan(groups).validate(status: status, currentDiff: "reviewed"))
        }
        let emptyMessage = StagedCommitPlan(groups: [.init(files: ["a.swift", "b.swift"], message: " \n")], expectedDiff: "reviewed")
        XCTAssertThrowsError(try emptyMessage.validate(status: status, currentDiff: "reviewed"))
    }

    func testRejectsStaleDiffPartialStagingRenamesAndConflicts() {
        XCTAssertThrowsError(try plan([["a.swift"]]).validate(status: status([file("a.swift")]), currentDiff: "changed"))
        let unsafe = [
            FileStatus(path: "a.swift", index: .modified, worktree: .modified),
            FileStatus(path: "a.swift", originalPath: "old.swift", index: .renamed, worktree: .unmodified),
            FileStatus(path: "a.swift", index: .updatedButUnmerged, worktree: .updatedButUnmerged)
        ]
        for file in unsafe {
            XCTAssertThrowsError(try plan([["a.swift"]]).validate(status: status([file]), currentDiff: "reviewed"))
        }
    }

    func testLiteralLookingFilenameIsAllowedWhenActuallyStaged() throws {
        try plan([["[draft]*.swift"]]).validate(status: status([file("[draft]*.swift")]), currentDiff: "reviewed")
    }

    private func plan(_ groups: [[String]]) -> StagedCommitPlan {
        StagedCommitPlan(groups: groups.map { .init(files: $0, message: "Commit") }, expectedDiff: "reviewed")
    }

    private func file(_ path: String) -> FileStatus {
        FileStatus(path: path, index: .modified, worktree: .unmodified)
    }

    private func status(_ entries: [FileStatus]) -> WorkingCopyStatus {
        WorkingCopyStatus(branch: BranchInfo(name: "main", oid: String(repeating: "a", count: 40)), entries: entries)
    }
}
