import Foundation

/// A commit plus the lane information needed by the history graph gutter.
public struct CommitGraphRow: Sendable, Equatable, Identifiable {
    public var id: String { commit.id }

    public let commit: CommitSummary
    public let lane: Int
    public let parentLanes: [Int]
    public let laneCount: Int
    /// Slots that pass through this row (vertical lines on the gutter).
    /// Excludes the slot at `lane`; that one is drawn separately so the dot can sit on top.
    public let throughLanes: [Int]
    /// Stable identity name (branch / remote-branch ref name) for each slot, when known.
    /// Used by the renderer to derive a stable color per branch.
    public let laneIdentities: [Int: String]

    public init(
        commit: CommitSummary,
        lane: Int,
        parentLanes: [Int],
        laneCount: Int,
        throughLanes: [Int] = [],
        laneIdentities: [Int: String] = [:]
    ) {
        self.commit = commit
        self.lane = lane
        self.parentLanes = parentLanes
        self.laneCount = laneCount
        self.throughLanes = throughLanes
        self.laneIdentities = laneIdentities
    }
}

/// Assigns visual lanes to commits in newest-to-oldest topological order.
///
/// Lanes use sparse indices that never shift mid-history: once a slot is allocated
/// it stays at the same index until its branch terminates. This produces continuous
/// vertical lanes when rendered.
public enum CommitGraph {
    public static func assignRows(for commits: [CommitSummary]) -> [CommitGraphRow] {
        assignRows(for: commits, refs: .empty)
    }

    public static func assignRows(for commits: [CommitSummary], refs: RepositoryRefs) -> [CommitGraphRow] {
        // Build OID -> identity map. Local branches take precedence over remotes when both point at the same commit.
        var tipIdentities: [String: String] = [:]
        for ref in refs.remoteBranches {
            tipIdentities[ref.oid] = "remote:\(ref.name)"
        }
        for ref in refs.localBranches {
            tipIdentities[ref.oid] = "local:\(ref.name)"
        }

        // slots is a sparse list; nil entries are free for reuse.
        struct Slot {
            var expectedOID: String
            var identity: String?
        }
        var slots: [Slot?] = []

        var rows: [CommitGraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            // 1. Find the slot expecting this commit, or allocate a new one.
            let lane: Int
            if let existing = slots.firstIndex(where: { $0?.expectedOID == commit.oid }) {
                lane = existing
            } else {
                let newSlot = Slot(expectedOID: commit.oid, identity: tipIdentities[commit.oid])
                if let freeIndex = slots.firstIndex(where: { $0 == nil }) {
                    slots[freeIndex] = newSlot
                    lane = freeIndex
                } else {
                    slots.append(newSlot)
                    lane = slots.count - 1
                }
            }

            // Capture identities BEFORE we mutate slots for this row.
            var identities: [Int: String] = [:]
            for (idx, slot) in slots.enumerated() {
                if let id = slot?.identity {
                    identities[idx] = id
                }
            }

            // 2. Resolve parents.
            var parentLanes: [Int] = []
            if let firstParent = commit.parentOIDs.first {
                // Continue the current lane through the first parent.
                slots[lane]?.expectedOID = firstParent
                parentLanes.append(lane)

                for parent in commit.parentOIDs.dropFirst() {
                    if let existing = slots.firstIndex(where: { $0?.expectedOID == parent }) {
                        parentLanes.append(existing)
                    } else {
                        let newSlot = Slot(expectedOID: parent, identity: tipIdentities[parent])
                        if let freeIndex = slots.firstIndex(where: { $0 == nil }) {
                            slots[freeIndex] = newSlot
                            parentLanes.append(freeIndex)
                        } else {
                            slots.append(newSlot)
                            parentLanes.append(slots.count - 1)
                        }
                    }
                }
            } else {
                // Root commit. Release this slot but keep the index reserved
                // (mark as nil) so other lanes keep their indices stable.
                slots[lane] = nil
            }

            // 3. Compute through-lanes: slots that pass straight down without
            // being involved in this row's commit or parents.
            let involvedLanes = Set([lane] + parentLanes)
            var throughLanes: [Int] = []
            for (idx, slot) in slots.enumerated() {
                if slot != nil && !involvedLanes.contains(idx) {
                    throughLanes.append(idx)
                }
            }

            // 4. Trim trailing free slots so laneCount stays compact at the end.
            // Only trim if no future row could revive them; here we just trim trailing nils each row.
            while slots.last == nil, !slots.isEmpty {
                slots.removeLast()
            }

            let laneCount = max(slots.count, (parentLanes + [lane]).max().map { $0 + 1 } ?? 1)

            rows.append(CommitGraphRow(
                commit: commit,
                lane: lane,
                parentLanes: parentLanes,
                laneCount: laneCount,
                throughLanes: throughLanes,
                laneIdentities: identities
            ))
        }

        return rows
    }
}
