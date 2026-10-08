@testable import AppUI
import Foundation
@testable import GitKit
import Testing

@MainActor
struct CommitMenuTests {
    private static func commit(_ oid: String, _ parents: [String]) -> CommitSummary {
        CommitSummary(
            oid: oid, parentOIDs: parents, authorName: "A", authorEmail: "a@example.com",
            authorDate: Date(timeIntervalSince1970: 0), subject: oid, body: ""
        )
    }

    @Test func headAncestryFollowsMergedBranches() async {
        let store = RepositoryStore(git: Fixtures.multibranch())
        await store.open(URL(fileURLWithPath: "/tmp/avi-commit-menu"))
        await store.refresh()

        #expect(store.headAncestry() == ["m3", "m2", "f3", "f2", "f1", "m1"])
    }

    @Test func headAncestryLeavesOutUnmergedBranches() async {
        let provider = FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "b", upstream: nil, ahead: 0, behind: 0), entries: []),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: "main", fullName: "refs/heads/main", oid: "b", kind: .localBranch, isCurrent: true),
                    GitReference(name: "feature", fullName: "refs/heads/feature", oid: "x", kind: .localBranch)
                ],
                remoteBranches: [],
                tags: []
            ),
            commits: [Self.commit("x", ["a"]), Self.commit("b", ["a"]), Self.commit("a", [])]
        )
        let store = RepositoryStore(git: provider)
        await store.open(URL(fileURLWithPath: "/tmp/avi-commit-menu"))
        await store.refresh()

        #expect(store.headAncestry() == ["b", "a"])
    }

    struct NameCase: Sendable, CustomTestStringConvertible {
        let subject: String
        let expected: String

        var testDescription: String {
            subject
        }
    }

    nonisolated static let names: [NameCase] = [
        NameCase(subject: "feat(history): search commits", expected: "feat-history-search-commits"),
        NameCase(subject: "Fix: émoji & spaces  ", expected: "fix-émoji-spaces"),
        NameCase(subject: "", expected: "commit"),
        NameCase(subject: "!!!", expected: "commit")
    ]

    @Test(arguments: names)
    func patchName(_ testCase: NameCase) {
        #expect(RepositoryStore.patchName(testCase.subject) == testCase.expected)
    }
}
