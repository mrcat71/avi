@testable import AppUI
import Foundation
@testable import GitKit
import Testing

struct HistorySearchTests {
    struct MatchCase: Sendable, CustomTestStringConvertible {
        let name: String
        let query: String
        let expected: Bool

        var testDescription: String {
            name
        }
    }

    private static let commit = CommitSummary(
        oid: "4f2a9c1e0b7d3a5f6e8c9b0a1d2e3f4a5b6c7d8e",
        parentOIDs: [],
        authorName: "Zoë Müller",
        authorEmail: "zoe@example.com",
        authorDate: Date(timeIntervalSince1970: 1_700_000_000),
        subject: "fix(graph): keep lane colors stable",
        body: "Refreshes used to reshuffle the palette."
    )

    static let matchCases: [MatchCase] = [
        MatchCase(name: "a word of the subject", query: "lane", expected: true),
        MatchCase(name: "case is ignored", query: "LANE Colors", expected: true),
        MatchCase(name: "every word has to match somewhere", query: "lane missing", expected: false),
        MatchCase(name: "words can match different fields", query: "palette zoe", expected: true),
        MatchCase(name: "diacritics are ignored", query: "muller", expected: true),
        MatchCase(name: "the author email", query: "example.com", expected: true),
        MatchCase(name: "the body", query: "reshuffle", expected: true),
        MatchCase(name: "a SHA prefix", query: "4f2a9c", expected: true),
        MatchCase(name: "an uppercase SHA prefix", query: "4F2A9C1E", expected: true),
        MatchCase(name: "three hex digits are too short for a SHA", query: "4f2", expected: false),
        MatchCase(name: "the middle of the SHA does not match", query: "9c1e0b", expected: false),
        MatchCase(name: "an empty query matches nothing", query: "   ", expected: false)
    ]

    @Test(arguments: matchCases)
    func matches(_ testCase: MatchCase) {
        let terms = HistorySearch.terms(in: testCase.query)
        #expect(HistorySearch.matches(Self.commit, terms: terms) == testCase.expected)
    }

    struct HighlightCase: Sendable, CustomTestStringConvertible {
        let name: String
        let text: String
        let query: String
        let expected: [String]

        var testDescription: String {
            name
        }
    }

    static let highlightCases: [HighlightCase] = [
        HighlightCase(name: "every occurrence", text: "fix the fix", query: "fix", expected: ["fix", "fix"]),
        HighlightCase(name: "keeps the text's case", text: "Fix lanes", query: "fix", expected: ["Fix"]),
        HighlightCase(name: "overlapping words merge", text: "lanes", query: "lan anes", expected: ["lanes"]),
        HighlightCase(name: "touching words merge", text: "abcd", query: "ab cd", expected: ["abcd"]),
        HighlightCase(name: "no match", text: "lanes", query: "graph", expected: [])
    ]

    @Test(arguments: highlightCases)
    func highlightRanges(_ testCase: HighlightCase) {
        let ranges = HistorySearch.highlightRanges(in: testCase.text, terms: HistorySearch.terms(in: testCase.query))
        #expect(ranges.map { String(testCase.text[$0]) } == testCase.expected)
    }

    struct StepCase: Sendable, CustomTestStringConvertible {
        let name: String
        let selected: Int?
        let matches: [Int]
        let step: Int
        let expected: Int?

        var testDescription: String {
            name
        }
    }

    static let stepCases: [StepCase] = [
        StepCase(name: "next after the selection", selected: 3, matches: [1, 4, 8], step: 1, expected: 4),
        StepCase(name: "next from a match", selected: 4, matches: [1, 4, 8], step: 1, expected: 8),
        StepCase(name: "next wraps to the first", selected: 8, matches: [1, 4, 8], step: 1, expected: 1),
        StepCase(name: "previous before the selection", selected: 5, matches: [1, 4, 8], step: -1, expected: 4),
        StepCase(name: "previous wraps to the last", selected: 1, matches: [1, 4, 8], step: -1, expected: 8),
        StepCase(name: "no selection starts at the top", selected: nil, matches: [1, 4, 8], step: 1, expected: 1),
        StepCase(name: "no selection goes back from the bottom", selected: nil, matches: [1, 4, 8], step: -1, expected: 8),
        StepCase(name: "no matches", selected: 2, matches: [], step: 1, expected: nil)
    ]

    @Test(arguments: stepCases)
    func nextMatch(_ testCase: StepCase) {
        #expect(HistorySearch.nextMatch(after: testCase.selected, in: testCase.matches, step: testCase.step) == testCase.expected)
    }

    @Test @MainActor
    func searchStateCountsPositionsInDisplayOrder() {
        let rows = ["add lanes", "fix docs", "fix lanes"].enumerated().map { index, subject in
            CommitGraphRow(
                commit: CommitSummary(
                    oid: "c\(index)", parentOIDs: [], authorName: "A", authorEmail: "a@example.com",
                    authorDate: Date(timeIntervalSince1970: 0), subject: subject, body: ""
                ),
                lane: 0, parentLanes: [], laneCount: 1
            )
        }
        let state = HistorySearchState(terms: HistorySearch.terms(in: "lanes"), rows: rows)
        #expect(state.matchIndices == [0, 2])
        #expect(state.position(of: "c2") == 2)
        #expect(state.position(of: "c1") == nil)
    }

    @Test @MainActor
    func loadOlderHistoryGrowsTheWindow() async {
        let commits = (0 ..< 1250).map { index in
            CommitSummary(
                oid: String(format: "%040x", 1250 - index), parentOIDs: [],
                authorName: "A", authorEmail: "a@example.com",
                authorDate: Date(timeIntervalSince1970: 0), subject: "commit \(index)", body: ""
            )
        }
        let provider = FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: commits[0].oid, upstream: nil, ahead: 0, behind: 0), entries: []),
            commits: commits
        )
        let store = RepositoryStore(git: provider)
        await store.open(URL(fileURLWithPath: "/tmp/avi-history-window"))
        await store.refresh()
        #expect(store.historyRows.count == RepositoryStore.historyPageSize)
        #expect(store.hasOlderHistory)

        await store.loadOlderHistory()
        #expect(store.historyRows.count == RepositoryStore.historyPageSize + RepositoryStore.historyOlderStep)
        #expect(store.hasOlderHistory)

        // A refresh keeps the larger window.
        await store.refresh()
        #expect(store.historyRows.count == RepositoryStore.historyPageSize + RepositoryStore.historyOlderStep)

        await store.loadOlderHistory()
        #expect(store.historyRows.count == commits.count)
        #expect(!store.hasOlderHistory)
    }
}
