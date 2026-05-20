import Foundation
import Testing
@testable import GitKit

@Suite struct CommitGraphTests {
    @Test func linearHistoryStaysOnOneLane() {
        let rows = CommitGraph.assignRows(for: [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        #expect(rows.map(\.lane) == [0, 0, 0])
        #expect(rows.map(\.laneCount) == [1, 1, 1])
    }

    @Test func mergeCommitCreatesAdditionalLane() {
        let rows = CommitGraph.assignRows(for: [
            commit("d", parents: ["b", "c"]),
            commit("b", parents: ["a"]),
            commit("c", parents: ["a"]),
            commit("a"),
        ])

        #expect(rows[0].lane == 0)
        #expect(rows[0].parentLanes == [0, 1])
        #expect(rows[0].laneCount == 2)
        #expect(rows[2].lane == 1)
    }

    private func commit(_ oid: String, parents: [String] = []) -> CommitSummary {
        CommitSummary(
            oid: oid,
            parentOIDs: parents,
            authorName: "Avi Test",
            authorEmail: "test@example.com",
            authorDate: Date(timeIntervalSince1970: 0),
            subject: oid,
            body: ""
        )
    }
}
