import Foundation
@testable import GitKit
import Testing

struct CommitGraphTests {
    @Test func linearHistoryStaysOnOneLane() {
        let rows = CommitGraph.assignRows(for: [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a")
        ])

        #expect(rows.map(\.lane) == [0, 0, 0])
        #expect(rows.map(\.laneCount) == [1, 1, 1])
    }

    @Test func mergeCommitCreatesAdditionalLane() {
        let rows = CommitGraph.assignRows(for: [
            commit("d", parents: ["b", "c"]),
            commit("b", parents: ["a"]),
            commit("c", parents: ["a"]),
            commit("a")
        ])

        #expect(rows[0].lane == 0)
        #expect(rows[0].parentLanes == [0, 1])
        #expect(rows[0].laneCount == 2)
        #expect(rows[2].lane == 1)
    }

    @Test func longBranchHoldsSameLane() {
        // main: m3 -> m2 -> m1
        // feature: f3 -> f2 -> f1 -> m1 (merge at m3)
        // History order:  m3 (merge), m2, f3, f2, f1, m1
        let rows = CommitGraph.assignRows(for: [
            commit("m3", parents: ["m2", "f3"]),
            commit("m2", parents: ["m1"]),
            commit("f3", parents: ["f2"]),
            commit("f2", parents: ["f1"]),
            commit("f1", parents: ["m1"]),
            commit("m1")
        ])

        // m3 is on lane 0; feature lane allocated at index 1.
        #expect(rows[0].lane == 0)
        #expect(rows[0].parentLanes == [0, 1])
        // m2 stays on lane 0
        #expect(rows[1].lane == 0)
        // f3, f2, f1 all on lane 1 - this is the key assertion (continuous lane).
        #expect(rows[2].lane == 1)
        #expect(rows[3].lane == 1)
        #expect(rows[4].lane == 1)
        // m1 (the shared base) lands on lane 0 because m2's parent picked up first.
        #expect(rows[5].lane == 0)
    }

    @Test func lanesDoNotShiftWhenABranchTerminates() {
        // Two parallel branches a and b. b terminates at its root.
        // After b's root, a should remain on lane 0 (no shift).
        let rows = CommitGraph.assignRows(for: [
            commit("a2", parents: ["a1"]),
            commit("b1"), // b's root, no parents
            commit("a1", parents: ["a0"]),
            commit("a0")
        ])

        #expect(rows[0].lane == 0) // a2 lane 0
        #expect(rows[1].lane == 1) // b1 lane 1 (new slot)
        // b1 terminates; lane 1 freed but a stays on lane 0.
        #expect(rows[2].lane == 0) // a1 lane 0
        #expect(rows[3].lane == 0) // a0 lane 0
    }

    @Test func parentLaneCountReflectsLaneIndexNotSize() {
        // After a branch ends, a new branch's lane is allocated to the lowest free slot.
        let rows = CommitGraph.assignRows(for: [
            commit("x"), // root, lane 0, lane freed
            commit("y") // root, should reuse lane 0
        ])

        #expect(rows[0].lane == 0)
        #expect(rows[1].lane == 0)
    }

    @Test func laneIdentitiesUseBranchTipNames() {
        let refs = RepositoryRefs(
            localBranches: [
                GitReference(name: "main", fullName: "refs/heads/main", oid: "m1", kind: .localBranch)
            ],
            remoteBranches: [],
            tags: []
        )

        let rows = CommitGraph.assignRows(for: [
            commit("m1", parents: [])
        ], refs: refs)

        #expect(rows[0].laneIdentities[0] == "local:main")
    }

    @Test func mergedDeletedBranchDoesNotLingerAsGhostLane() {
        // Real-world scenario: Renovate (or a feature PR) branched off the
        // previous main HEAD `b`, added one commit `r1`, was merged via merge
        // commit `m` (parents: [b, r1]), and then the branch was deleted on
        // GitHub. `c` is the newest main commit on top of the merge.
        //
        // Before the fix, the algorithm allowed two slots to expect `b`
        // simultaneously: main's slot (continuing down) and the side branch's
        // slot (heading to its parent). Only main's slot got consumed when
        // `b` was reached; the side branch's slot remained as a perpetual
        // through-lane all the way to the bottom of the log - the "orphan"
        // line the user reported.
        //
        // After the fix the side branch's lane terminates exactly at row `b`
        // (the common ancestor) by being reported as a `mergeInLane`, so the
        // renderer draws a curve from lane 1 (the side branch's tail) into
        // the dot at lane 0.
        let rows = CommitGraph.assignRows(for: [
            commit("c", parents: ["m"]), // newest main commit
            commit("m", parents: ["b", "r1"]), // merge of the deleted PR branch
            commit("r1", parents: ["b"]), // PR branch tip, branched off `b`
            commit("b", parents: ["a"]), // previous main HEAD = common ancestor
            commit("a") // root
        ])

        // Dot lanes: main at lane 0 throughout; the deleted branch sits on lane 1
        // for exactly one row (its own commit).
        #expect(rows.map(\.lane) == [0, 0, 1, 0, 0])

        // At `b`, the row that absorbs both lanes: dot stays on main (0) and
        // the side branch (lane 1) is reported as a mergeInLane so the
        // renderer draws its tail-into-dot curve.
        #expect(rows[3].mergeInLanes == [1])

        // After `b`, no through-lane at slot 1 - the orphan tail is gone.
        #expect(rows[4].throughLanes.contains(1) == false)
        #expect(rows[4].laneCount == 1)
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
