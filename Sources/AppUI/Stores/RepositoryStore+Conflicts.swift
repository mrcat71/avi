import Foundation
import GitKit

/// A pull that found both the branch and its upstream with new commits, and
/// no Git setting that says whether to rebase or merge.
public struct DivergedPull: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let branch: String
    public let upstream: String
    /// Commits only the branch has.
    public let ahead: Int
    /// Commits only the upstream has.
    public let behind: Int
}

/// The conflicted file selected in Changes, as the working tree has it.
public struct SelectedConflict: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        /// Text whose conflicts can be resolved one by one; none may be left.
        case text(ConflictDocument)
        /// Binary, not UTF-8, or markers that do not pair up: only whole-file
        /// choices and a merge tool.
        case unreadable
        /// One side deleted the file and the other changed it; nil when both
        /// sides deleted it.
        case deleted(by: ConflictSide?)
    }

    public let path: String
    public let content: Content

    /// Reads `file` from the working tree, off the main thread.
    static func read(_ file: FileStatus, in root: URL) async -> SelectedConflict {
        // For a conflict, X is what HEAD's side did and Y the incoming side.
        switch (file.index, file.worktree) {
        case (.deleted, .deleted):
            return SelectedConflict(path: file.path, content: .deleted(by: nil))
        case (.deleted, _):
            return SelectedConflict(path: file.path, content: .deleted(by: .current))
        case (_, .deleted):
            return SelectedConflict(path: file.path, content: .deleted(by: .incoming))
        default:
            break
        }
        let url = root.appendingPathComponent(file.path)
        let content = await Task.detached(priority: .userInitiated) { () -> Content in
            guard let data = try? Data(contentsOf: url), !data.contains(0),
                  let text = String(data: data, encoding: .utf8),
                  let document = ConflictDocument(text: text)
            else { return .unreadable }
            return .text(document)
        }.value
        return SelectedConflict(path: file.path, content: content)
    }
}

/// Files you asked to mark resolved while they still have conflict markers.
public struct PendingResolve: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let files: [FileStatus]
    public let withMarkers: [String]
}

/// Conflicted files waiting for you to confirm taking one side's whole
/// version, which drops the other side's changes and your edits to them.
public struct PendingSideChoice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let files: [FileStatus]
    public let side: ConflictSide
}

public extension RepositoryStore {
    /// The conflicted files, in the order Changes lists them.
    var conflictedEntries: [FileStatus] {
        entries.filter(\.isConflicted)
    }

    /// Your answer to a diverged pull: rebase onto the fetched upstream, or
    /// merge it. A conflict stops it, and the banner takes over.
    func reconcileDivergedPull(_ how: PullReconcile) async {
        divergedPull = nil
        await runIntegration { try await $0.reconcileWithUpstream(how, in: $1) }
    }

    /// Replaces one conflict in the selected file with the lines you chose.
    /// `expected` is the conflict as you saw it: if the file changed since,
    /// it is read again and nothing is written.
    func resolveConflict(at index: Int, expected: ConflictDocument.Conflict, with resolution: ConflictDocument.Resolution, in file: FileStatus) async {
        guard let root else { return }
        let url = root.appendingPathComponent(file.path)
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let document = ConflictDocument(text: text),
                  document.conflicts.indices.contains(index), document.conflicts[index] == expected
            else {
                await loadDiff(for: file)
                return
            }
            // Written in place, not replaced, so the file keeps its permissions.
            try Data(document.resolving(conflictAt: index, with: resolution).text.utf8).write(to: url)
        } catch {
            errorMessage = "Could not update \(file.path): \(error.localizedDescription)"
        }
        await loadDiff(for: file)
    }

    /// Resolves whole files with one side's version and stages them.
    func resolveConflicts(_ files: [FileStatus], taking side: ConflictSide) async {
        let paths = files.filter(\.isConflicted).map(\.path)
        guard !paths.isEmpty else { return }
        await perform { try await $0.resolveConflicts(paths: paths, taking: side, in: $1) }
    }

    /// Stages conflicted files as resolved. Files that still have conflict
    /// markers wait in `pendingResolve` for you to confirm, unless `force`.
    func markResolved(_ files: [FileStatus], force: Bool = false) async {
        let conflicted = files.filter(\.isConflicted)
        guard !conflicted.isEmpty, let root else { return }
        if !force {
            let withMarkers = await Task.detached(priority: .userInitiated) {
                conflicted.map(\.path).filter { Self.hasConflictMarkers(at: root.appendingPathComponent($0)) }
            }.value
            if !withMarkers.isEmpty {
                pendingResolve = PendingResolve(files: conflicted, withMarkers: withMarkers)
                return
            }
        }
        await perform { try await $0.markResolved(paths: conflicted.map(\.path), in: $1) }
    }

    /// Opens a conflicted file in the merge tool from Settings > External
    /// Tools, or Git's `merge.tool`. Git stages the file if the tool merged it.
    func openMergeTool(for file: FileStatus) {
        guard let root, file.isConflicted, !mergeToolPaths.contains(file.path) else { return }
        let launch: MergeToolLaunch?
        do {
            launch = try MergeToolCatalog.launch(for: ConfigStore.shared.config.externalTools)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        mergeToolPaths.insert(file.path)
        Task {
            defer { mergeToolPaths.remove(file.path) }
            do {
                _ = try await git.launchMergeTool(path: file.path, tool: launch, in: root)
            } catch {
                errorMessage = "Could not open the merge tool: \(error.localizedDescription)\n\n"
                    + "Choose a tool in Settings > External Tools > Merge Tool, or set Git's merge.tool."
            }
            guard self.root == root else { return }
            await refresh()
        }
    }

    /// A line opening a conflict, as Git writes it.
    nonisolated static func hasConflictMarkers(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return false }
        if let document = ConflictDocument(text: text) {
            return !document.conflicts.isEmpty
        }
        // Markers that do not pair up are still unresolved.
        return text.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.hasPrefix("<<<<<<<") }
    }
}
