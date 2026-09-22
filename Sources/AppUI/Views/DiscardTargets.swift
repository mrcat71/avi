import GitKit

/// Resolves which files a row-level destructive action applies to.
///
/// A context-menu action on a row that is part of the current multi-selection
/// acts on the whole selection, the way Finder and other Mac apps behave.
/// A row outside the selection acts on itself alone, so a right-click never
/// destroys files the user cannot see highlighted.
enum DiscardTargets {
    static func resolve(row: FileStatus, selection: Set<String>, entries: [FileStatus]) -> [FileStatus] {
        guard selection.contains(row.path) else { return [row] }
        let selected = entries.filter { selection.contains($0.path) }
        return selected.count > 1 ? selected : [row]
    }
}
