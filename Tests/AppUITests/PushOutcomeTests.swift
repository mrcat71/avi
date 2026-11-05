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
            name: "a branch still tracking the branch it started from gets its own",
            branch: "feature", remote: "origin", upstream: "origin/main",
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
            name: "an upstream deleted on the remote is created again",
            branch: "feature", remote: "origin", upstream: "origin/feature",
            remoteBranches: ["origin/main"],
            expected: "Creates origin/feature and makes it the upstream of feature."
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

@Suite("Push route status")
struct PushRouteStatusTests {
    struct Case: Sendable {
        let name: String
        var branch: String? = "feature"
        var remote = "origin"
        var upstream: String? = "origin/feature"
        var remoteBranches = ["origin/main", "origin/feature"]
        var ahead: Int?
        var behind: Int?
        let expected: PushRouteStatus
    }

    static let cases: [Case] = [
        Case(name: "detached HEAD", branch: nil, expected: .detached),
        Case(name: "no remote chosen", remote: "", expected: .noRemote),
        Case(name: "a name the remote has never seen", upstream: nil, remoteBranches: ["origin/main"], expected: .creates),
        Case(name: "an upstream deleted on the remote", remoteBranches: ["origin/main"], ahead: 2, expected: .creates),
        Case(name: "the branch tracks the one it started from", upstream: "origin/main", remoteBranches: ["origin/main"], expected: .creates),
        Case(name: "the remote has the branch, untracked", upstream: nil, expected: .adopts),
        Case(name: "nothing the upstream lacks", ahead: 0, behind: 0, expected: .upToDate),
        Case(name: "counts unknown", expected: .upToDate),
        Case(name: "commits to send", ahead: 3, behind: 0, expected: .sends(3)),
        Case(name: "the upstream moved on", ahead: 0, behind: 2, expected: .behind(2)),
        Case(name: "diverged warns before it counts", ahead: 3, behind: 1, expected: .behind(1)),
        Case(name: "another remote gets a new branch", remote: "fork", ahead: 3, expected: .creates)
    ]

    @Test(arguments: cases)
    func summarizesTheRoute(_ testCase: Case) {
        let status = PushSheet.routeStatus(
            branch: testCase.branch,
            remote: testCase.remote,
            upstream: testCase.upstream,
            remoteBranches: testCase.remoteBranches,
            ahead: testCase.ahead,
            behind: testCase.behind
        )
        #expect(status == testCase.expected, "\(testCase.name)")
    }

    @Test
    func countsReadAsWords() {
        #expect(PushRouteStatus.sends(1).title == "1 commit")
        #expect(PushRouteStatus.sends(4).title == "4 commits")
        #expect(PushRouteStatus.behind(2).title == "2 behind")
        #expect(PushRouteStatus.creates.title == "New branch")
    }
}
