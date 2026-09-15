@testable import AppUI
import Testing

@Suite("Push outcome description")
struct PushOutcomeTests {
    struct Case: Sendable {
        let name: String
        let branch: String?
        let remote: String
        let upstream: String?
        let remoteBranches: [String]
        let expected: String
    }

    static let cases: [Case] = [
        Case(
            name: "tracked branch updates its upstream",
            branch: "main", remote: "origin", upstream: "origin/main",
            remoteBranches: ["origin/main"],
            expected: "Updates origin/main, the upstream of main."
        ),
        Case(
            name: "untracked branch that already exists on the remote adopts it",
            branch: "feature", remote: "origin", upstream: nil,
            remoteBranches: ["origin/main", "origin/feature"],
            expected: "Updates the existing origin/feature and makes it the upstream of feature."
        ),
        Case(
            name: "a name the remote has never seen is created",
            branch: "feature", remote: "origin", upstream: nil,
            remoteBranches: ["origin/main"],
            expected: "Creates origin/feature and makes it the upstream of feature."
        ),
        Case(
            name: "pushing to a second remote creates the branch there",
            branch: "main", remote: "fork", upstream: "origin/main",
            remoteBranches: ["origin/main"],
            expected: "Creates fork/main and makes it the upstream of main."
        ),
        Case(
            name: "detached HEAD has nothing to push",
            branch: nil, remote: "origin", upstream: nil, remoteBranches: [],
            expected: "HEAD is detached, so there is no branch to push."
        ),
        Case(
            name: "no remote selected yet",
            branch: "main", remote: "", upstream: nil, remoteBranches: [],
            expected: "Choose a remote to push to."
        )
    ]

    @Test(arguments: cases)
    func describesTheOutcome(_ testCase: Case) {
        let outcome = PushSheet.outcome(
            branch: testCase.branch,
            remote: testCase.remote,
            upstream: testCase.upstream,
            remoteBranches: testCase.remoteBranches
        )
        #expect(outcome == testCase.expected, "\(testCase.name)")
    }
}
