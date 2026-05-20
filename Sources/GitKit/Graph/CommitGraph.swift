/// A commit plus the lane information needed by the history graph gutter.
public struct CommitGraphRow: Sendable, Equatable, Identifiable {
    public var id: String { commit.id }

    public let commit: CommitSummary
    public let lane: Int
    public let parentLanes: [Int]
    public let laneCount: Int

    public init(commit: CommitSummary, lane: Int, parentLanes: [Int], laneCount: Int) {
        self.commit = commit
        self.lane = lane
        self.parentLanes = parentLanes
        self.laneCount = laneCount
    }
}

/// Assigns visual lanes to commits in newest-to-oldest topological order.
public enum CommitGraph {
    public static func assignRows(for commits: [CommitSummary]) -> [CommitGraphRow] {
        var activeLanes: [String] = []
        var rows: [CommitGraphRow] = []

        for commit in commits {
            let lane: Int
            if let existing = activeLanes.firstIndex(of: commit.oid) {
                lane = existing
            } else {
                activeLanes.append(commit.oid)
                lane = activeLanes.count - 1
            }

            let laneCountBeforeUpdate = activeLanes.count
            var parentLanes: [Int] = []

            if let firstParent = commit.parentOIDs.first {
                activeLanes[lane] = firstParent
                parentLanes.append(lane)

                for parent in commit.parentOIDs.dropFirst() {
                    if let existing = activeLanes.firstIndex(of: parent) {
                        parentLanes.append(existing)
                    } else {
                        activeLanes.append(parent)
                        parentLanes.append(activeLanes.count - 1)
                    }
                }
            } else {
                activeLanes.remove(at: lane)
            }

            let laneCount = max(laneCountBeforeUpdate, activeLanes.count, (parentLanes.max() ?? lane) + 1)
            rows.append(CommitGraphRow(commit: commit, lane: lane, parentLanes: parentLanes, laneCount: laneCount))
        }

        return rows
    }
}
