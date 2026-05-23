import Foundation
import GitKit

/// One node in the changed-files tree. Folders carry a display name (possibly
/// chain-collapsed like "AppUI/Views"), children, and aggregate counts.
struct FileTreeNode: Identifiable {
    enum Payload {
        case folder(name: String, children: [FileTreeNode])
        case file(FileStatus)
    }

    let id: String // full path: "Sources/AppUI/Views" or "Sources/AppUI/Views/Foo.swift"
    let depth: Int
    let payload: Payload
    let changedCount: Int
    let stagedCount: Int

    var isFolder: Bool {
        if case .folder = payload { return true }
        return false
    }

    var sortKey: String {
        id
    }
}

enum FileTreeBuilder {
    /// Builds a list of `FileTreeNode` flattened DFS (root nodes only at depth 0).
    /// Caller flattens further when rendering (respecting expanded state).
    static func build(entries: [FileStatus]) -> [FileTreeNode] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        // Build raw nested folder dict.
        var root = RawFolder(name: "", path: "")
        for entry in sorted {
            insert(entry, into: &root)
        }
        // Convert RawFolder -> [FileTreeNode], collapsing single-child chains.
        return convert(root, depth: 0).children
    }

    /// Flatten a tree honoring an expanded-paths set. Files always render; folders'
    /// children render only if the folder's id is in `expanded`.
    static func flatten(_ nodes: [FileTreeNode], expanded: Set<String>) -> [FileTreeNode] {
        var out: [FileTreeNode] = []
        for node in nodes {
            out.append(node)
            switch node.payload {
            case .folder(_, let children):
                if expanded.contains(node.id) {
                    out.append(contentsOf: flatten(children, expanded: expanded))
                }
            case .file:
                break
            }
        }
        return out
    }

    /// Returns the ids of every folder node in the trees produced from `entries`.
    /// Used to "expand everything" by default or via the Expand all action.
    static func allFolderIds(for entries: [FileStatus]) -> Set<String> {
        var ids: Set<String> = []
        collectFolderIds(build(entries: entries), into: &ids)
        return ids
    }

    private static func collectFolderIds(_ nodes: [FileTreeNode], into ids: inout Set<String>) {
        for node in nodes {
            if case .folder(_, let children) = node.payload {
                ids.insert(node.id)
                collectFolderIds(children, into: &ids)
            }
        }
    }

    // MARK: - Internal raw tree representation

    private struct RawFolder {
        var name: String
        var path: String
        var folders: [String: RawFolder] = [:]
        var files: [FileStatus] = []
    }

    private static func insert(_ entry: FileStatus, into folder: inout RawFolder) {
        let parts = entry.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return }
        insertParts(parts, fileIndex: 0, entry: entry, into: &folder, accumulated: "")
    }

    private static func insertParts(
        _ parts: [String],
        fileIndex: Int,
        entry: FileStatus,
        into folder: inout RawFolder,
        accumulated: String
    ) {
        if fileIndex == parts.count - 1 {
            folder.files.append(entry)
            return
        }
        let component = parts[fileIndex]
        let newPath = accumulated.isEmpty ? component : "\(accumulated)/\(component)"
        var child = folder.folders[component] ?? RawFolder(name: component, path: newPath)
        insertParts(parts, fileIndex: fileIndex + 1, entry: entry, into: &child, accumulated: newPath)
        folder.folders[component] = child
    }

    private struct ConvertResult {
        var children: [FileTreeNode]
        var totalChanged: Int
        var totalStaged: Int
    }

    private static func convert(_ folder: RawFolder, depth: Int) -> ConvertResult {
        var children: [FileTreeNode] = []
        var totalChanged = 0
        var totalStaged = 0

        let folderKeys = folder.folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        for key in folderKeys {
            var sub = folder.folders[key]!
            // Chain-collapse: while this folder has exactly one folder child and zero files,
            // collapse the chain into a single node.
            var displayName = sub.name
            var displayPath = sub.path
            while sub.files.isEmpty, sub.folders.count == 1, let onlyKey = sub.folders.keys.first {
                let only = sub.folders[onlyKey]!
                displayName += "/" + only.name
                displayPath = only.path
                sub = only
            }
            let nested = convert(sub, depth: depth + 1)
            let node = FileTreeNode(
                id: displayPath,
                depth: depth,
                payload: .folder(name: displayName, children: nested.children),
                changedCount: nested.totalChanged,
                stagedCount: nested.totalStaged
            )
            children.append(node)
            totalChanged += nested.totalChanged
            totalStaged += nested.totalStaged
        }

        for file in folder.files {
            let node = FileTreeNode(
                id: file.path,
                depth: depth,
                payload: .file(file),
                changedCount: 1,
                stagedCount: file.isStaged ? 1 : 0
            )
            children.append(node)
            totalChanged += 1
            totalStaged += file.isStaged ? 1 : 0
        }

        return ConvertResult(children: children, totalChanged: totalChanged, totalStaged: totalStaged)
    }
}
