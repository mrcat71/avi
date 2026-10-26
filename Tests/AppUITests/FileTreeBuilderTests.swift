@testable import AppUI
import GitKit
import Testing

struct FileTreeBuilderTests {
    @Test(arguments: [false, true]) func buildsLargeTree(separateFolders: Bool) {
        let entries = (0 ..< 8000).map { index in
            FileStatus(
                path: "Sources/\(separateFolders ? "Folder\(index)/" : "")File\(index).swift",
                index: index.isMultiple(of: 2) ? .added : .unmodified, worktree: .modified
            )
        }
        let start = ContinuousClock.now
        let tree = FileTreeBuilder.build(entries: entries)
        print("Large file tree (separate folders: \(separateFolders)): \(start.duration(to: .now))")
        #expect(tree.reduce(0) { $0 + $1.changedCount } == entries.count)
        #expect(tree.reduce(0) { $0 + $1.stagedCount } == entries.count / 2)
        let expanded = FileTreeBuilder.allFolderIds(for: entries)
        let files = FileTreeBuilder.flatten(tree, expanded: expanded).compactMap { node -> String? in
            guard case .file(let file) = node.payload else { return nil }
            return file.path
        }
        #expect(Set(files) == Set(entries.map(\.path)))
        #expect(files.count == entries.count)
    }

    @Test func emptyEntriesProduceEmptyTree() {
        let tree = FileTreeBuilder.build(entries: [])
        #expect(tree.isEmpty)
        #expect(FileTreeBuilder.allFolderIds(for: []).isEmpty)
    }

    @Test func chainCollapseFlattensSingleChildFolders() {
        // A single nested file under a chain of folders collapses into one
        // folder node with a combined display name.
        let file = FileStatus(path: "Sources/AppUI/Views/Foo.swift", index: .modified, worktree: .unmodified)
        let tree = FileTreeBuilder.build(entries: [file])
        #expect(tree.count == 1)
        guard case .folder(let name, let children) = tree[0].payload else {
            Issue.record("expected folder root")
            return
        }
        #expect(name == "Sources/AppUI/Views")
        #expect(children.count == 1)
        guard case .file(let leaf) = children[0].payload else {
            Issue.record("expected file leaf")
            return
        }
        #expect(leaf.path == "Sources/AppUI/Views/Foo.swift")
    }

    @Test func allFolderIdsCollectsEveryFolder() {
        let entries = [
            FileStatus(path: "a/b/c.swift", index: .modified, worktree: .unmodified),
            FileStatus(path: "a/d/e.swift", index: .modified, worktree: .unmodified),
            FileStatus(path: "f.swift", index: .modified, worktree: .unmodified)
        ]
        let ids = FileTreeBuilder.allFolderIds(for: entries)
        // Top-level "a" + the two branches under it. Chain-collapse keeps
        // each branch as a single folder node ("a/b", "a/d"); the root "a"
        // remains because it has two children.
        #expect(ids.contains("a"))
        #expect(ids.contains("a/b"))
        #expect(ids.contains("a/d"))
        // Leaf paths must not appear.
        #expect(!ids.contains("a/b/c.swift"))
        #expect(!ids.contains("f.swift"))
    }

    @Test func flattenHonorsExpandedSet() {
        let entries = [
            FileStatus(path: "a/b/c.swift", index: .modified, worktree: .unmodified),
            FileStatus(path: "a/d/e.swift", index: .modified, worktree: .unmodified)
        ]
        let tree = FileTreeBuilder.build(entries: entries)
        let collapsed = FileTreeBuilder.flatten(tree, expanded: [])
        // Only the top-level "a" folder is visible.
        #expect(collapsed.count == 1)
        let expanded = FileTreeBuilder.flatten(tree, expanded: ["a"])
        // Expanding "a" reveals both branch folders.
        #expect(expanded.count == 3) // a, a/b, a/d
        let fullyExpanded = FileTreeBuilder.flatten(tree, expanded: ["a", "a/b", "a/d"])
        // Expanding the branch folders reveals their files.
        #expect(fullyExpanded.count == 5)
    }
}
