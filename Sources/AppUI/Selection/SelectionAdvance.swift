import Foundation

/// Computes which path the selection should move to after some files leave a
/// pane (for example after staging or unstaging them).
///
/// - Parameters:
///   - visibleOrder: the pane's file paths in the order they were displayed
///     *before* the action (flat order, or the flattened tree order).
///   - acted: the paths that were acted on and have now left the pane.
///   - surviving: the paths still present in the pane after the action.
/// - Returns: the nearest surviving neighbour AFTER the acted block; failing
///   that, the nearest surviving neighbour BEFORE it; `nil` if nothing is left
///   to select (the pane emptied). Mirrors the forward/backward neighbour walk
///   used by `RepositoryStore.preserveSelection`.
func nextSelection(visibleOrder: [String], acted: Set<String>, surviving: Set<String>) -> String? {
    guard !acted.isEmpty else { return nil }

    let actedIndices = visibleOrder.indices.filter { acted.contains(visibleOrder[$0]) }
    guard let firstActed = actedIndices.first, let lastActed = actedIndices.last else { return nil }

    if lastActed + 1 < visibleOrder.count,
       let forward = visibleOrder[(lastActed + 1)...].first(where: { surviving.contains($0) }) {
        return forward
    }
    if firstActed > 0,
       let backward = visibleOrder[..<firstActed].last(where: { surviving.contains($0) }) {
        return backward
    }
    return nil
}
