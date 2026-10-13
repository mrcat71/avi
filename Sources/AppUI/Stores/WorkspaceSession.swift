import Foundation
import GitKit
import Observation
import OSLog

/// Owns repository lifetimes independently of whichever SwiftUI view is visible.
@MainActor
@Observable
final class WorkspaceSession {
    private(set) var repositories: [RepositoryStore] = [] {
        didSet { saveWorkspace() }
    }

    private(set) var selectedRepositoryID: RepositoryStore.ID? {
        didSet {
            if let selected = selectedRepository {
                lastActive[Self.tabID(of: selected)] = selected.id
            }
            saveWorkspace()
        }
    }

    /// The worktree each tab showed last, by tab id, so coming back to a tab
    /// returns to the worktree you left it on.
    private var lastActive: [RepositoryTab.ID: RepositoryStore.ID] = [:]

    var errorMessage: String?
    private var openingPaths: [String: UUID] = [:]
    private var latestOpenRequest = UUID()
    private let git: GitProviding
    private let defaults: UserDefaults
    private let startupSnapshot: Snapshot?
    private var hasRestored = false
    private var isRestoring = false
    private static let storageKey = "avi.workspaceSession"
    private static let log = Logger(subsystem: "com.svinarenko.avi", category: "workspace")

    private struct Snapshot: Codable {
        let paths: [String]
        let selectedPath: String?
    }

    init(git: GitProviding = CLIGitProvider(), defaults: UserDefaults = .standard) {
        self.git = git
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                startupSnapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            } catch {
                startupSnapshot = nil
                errorMessage = "Unable to restore the previous workspace: \(error.localizedDescription)"
                Self.log.error("Unable to read saved workspace: \(error.localizedDescription)")
            }
        } else {
            startupSnapshot = nil
        }
    }

    /// Restore once per window lifetime. Saving waits until all tabs have been
    /// attempted, so a partial restore never replaces the saved session.
    func restore() async {
        guard !hasRestored else { return }
        hasRestored = true
        guard let snapshot = startupSnapshot else { return }
        let requestID = latestOpenRequest
        let alreadySelected = selectedRepositoryID != nil
        isRestoring = true
        defer {
            isRestoring = false
            if !Task.isCancelled {
                saveWorkspace()
            }
        }

        var failures: [String] = []
        for path in snapshot.paths {
            guard !Task.isCancelled else { return }
            // A worktree removed while Avi was closed left nothing to reopen,
            // which is no failure to report.
            guard FileManager.default.fileExists(atPath: path) else {
                Self.log.notice("Not reopening a deleted folder: \(path, privacy: .private)")
                continue
            }
            let restored = await openInBackground(URL(fileURLWithPath: path, isDirectory: true))
            guard !Task.isCancelled else { return }
            if restored == nil {
                failures.append(path)
                Self.log.error("Unable to reopen repository: \(path, privacy: .private)")
            }
        }
        // A click or explicit open during restoration wins over the old selection.
        if !alreadySelected, latestOpenRequest == requestID, let path = snapshot.selectedPath {
            selectedRepositoryID = repository(at: URL(fileURLWithPath: path))?.id ?? repositories.first?.id
        }
        if !failures.isEmpty, errorMessage == nil {
            errorMessage = "Some repositories could not be reopened:\n\n" + failures.joined(separator: "\n")
        }
    }

    private func saveWorkspace() {
        guard !isRestoring else { return }
        let snapshot = Snapshot(paths: repositories.compactMap { $0.root?.path }, selectedPath: selectedRepository?.root?.path)
        do {
            try defaults.set(JSONEncoder().encode(snapshot), forKey: Self.storageKey)
        } catch {
            Self.log.error("Unable to save workspace: \(error.localizedDescription)")
            errorMessage = "Unable to save the workspace: \(error.localizedDescription)"
        }
    }

    var selectedRepository: RepositoryStore? {
        repositories.first { $0.id == selectedRepositoryID } ?? repositories.first
    }

    func select(_ id: RepositoryStore.ID?) {
        latestOpenRequest = UUID()
        selectedRepositoryID = id
    }

    func open(_ url: URL) async {
        let requestID = UUID()
        latestOpenRequest = requestID
        do {
            let root = try await git.repositoryRoot(for: url).resolvingSymlinksInPath().standardizedFileURL
            if let existing = repositories.first(where: { $0.root?.resolvingSymlinksInPath().standardizedFileURL == root }) {
                if latestOpenRequest == requestID {
                    selectedRepositoryID = existing.id
                }
                return
            }
            if let pendingRequest = openingPaths[root.path] {
                if latestOpenRequest == requestID {
                    latestOpenRequest = pendingRequest
                }
                return
            }
            openingPaths[root.path] = requestID
            defer { openingPaths.removeValue(forKey: root.path) }
            let candidate = RepositoryStore(git: git)
            await candidate.open(root)
            guard candidate.root != nil else {
                errorMessage = candidate.errorMessage ?? "Unable to open repository."
                return
            }
            // Startup restoration can finish opening this path while the
            // explicit request is loading its candidate.
            if let existing = repository(at: root) {
                candidate.stopBackgroundObservation()
                if latestOpenRequest == requestID {
                    selectedRepositoryID = existing.id
                }
                return
            }
            append(candidate)
            if latestOpenRequest == requestID || selectedRepositoryID == nil {
                selectedRepositoryID = candidate.id
            }
        } catch {
            if latestOpenRequest == requestID {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Opens `url` as a tab without switching to it, for requests that arrive
    /// from an agent rather than from you. Failures are returned as nil, never
    /// shown as alerts over whatever you are doing.
    func openInBackground(_ url: URL) async -> RepositoryStore? {
        guard let root = try? await git.repositoryRoot(for: url).resolvingSymlinksInPath().standardizedFileURL else {
            return nil
        }
        if let existing = repository(at: root) {
            return existing
        }
        let candidate = RepositoryStore(git: git)
        await candidate.open(root)
        guard candidate.root != nil else { return nil }
        // Another request may have opened the same path while this one waited.
        if let existing = repository(at: root) {
            candidate.stopBackgroundObservation()
            return existing
        }
        append(candidate)
        if selectedRepositoryID == nil {
            selectedRepositoryID = candidate.id
        }
        return candidate
    }

    /// Adds `store` to its repository's tab, or as the last tab when it is
    /// the repository's first. It closes on its own once its folder is
    /// deleted, such as a worktree an agent or another app removed.
    private func append(_ store: RepositoryStore) {
        store.onFolderRemoved = { [weak self, weak store] in
            guard let self, let store else { return }
            close(store.id)
        }
        let tab = Self.tabID(of: store)
        if let last = repositories.lastIndex(where: { Self.tabID(of: $0) == tab }) {
            repositories.insert(store, at: last + 1)
        } else {
            repositories.append(store)
        }
    }

    // MARK: - Tabs

    /// The open repositories as tabs. Worktrees of one repository share its
    /// tab, which shows the selected one, else the one you left it on. Tabs
    /// keep the order their first worktree has in `repositories`.
    var tabs: [RepositoryTab] {
        var order: [RepositoryTab.ID] = []
        var members: [RepositoryTab.ID: [RepositoryStore]] = [:]
        for store in repositories {
            let id = Self.tabID(of: store)
            if members[id] == nil {
                order.append(id)
            }
            members[id, default: []].append(store)
        }
        let selected = selectedRepository?.id
        return order.compactMap { id in
            guard let group = members[id], let first = group.first else { return nil }
            let active = group.first { $0.id == selected } ?? group.first { $0.id == lastActive[id] } ?? first
            return RepositoryTab(id: id, members: group, active: active)
        }
    }

    var selectedTabID: RepositoryTab.ID? {
        selectedRepository.map(Self.tabID(of:))
    }

    /// Worktrees of one repository share its common git dir, so they share a tab.
    static func tabID(of store: RepositoryStore) -> RepositoryTab.ID {
        let folder = store.location?.commonDir ?? store.root
        return folder?.resolvingSymlinksInPath().standardizedFileURL.path ?? store.id.uuidString
    }

    func selectTab(_ id: RepositoryTab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        select(tab.active.id)
    }

    /// Moves the tab `id`, with all its worktrees, into the place of `target`.
    func moveTab(_ id: RepositoryTab.ID, toPlaceOf target: RepositoryTab.ID) {
        var order = tabs.map(\.id)
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return }
        order.insert(order.remove(at: from), at: to)
        let groups = Dictionary(grouping: repositories, by: Self.tabID(of:))
        repositories = order.flatMap { groups[$0] ?? [] }
    }

    /// Closes the tab with every worktree of it that is open.
    func closeTab(_ id: RepositoryTab.ID) {
        let before = tabs
        guard let position = before.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        let neighbor = before.indices.contains(position + 1) ? before[position + 1] : (position > 0 ? before[position - 1] : nil)
        let closing = Set(before[position].members.map(\.id))
        for store in before[position].members {
            store.stopBackgroundObservation()
        }
        repositories.removeAll { closing.contains($0.id) }
        lastActive[id] = nil
        if wasSelected {
            selectedRepositoryID = neighbor?.active.id
        }
    }

    func repository(at root: URL) -> RepositoryStore? {
        let wanted = root.resolvingSymlinksInPath().standardizedFileURL
        return repositories.first { $0.root?.resolvingSymlinksInPath().standardizedFileURL == wanted }
    }

    /// Moves the tab `id` into the place of the tab `target`, the others
    /// keeping their order, so a tab dragged onto another takes its place.
    func moveRepository(_ id: RepositoryStore.ID, toPlaceOf target: RepositoryStore.ID) {
        guard id != target,
              let from = repositories.firstIndex(where: { $0.id == id }),
              let to = repositories.firstIndex(where: { $0.id == target }) else { return }
        repositories.insert(repositories.remove(at: from), at: to)
    }

    /// Closes one worktree. When the tab has others, it shows one of them.
    func close(_ id: RepositoryStore.ID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        let tab = Self.tabID(of: repositories[index])
        repositories[index].stopBackgroundObservation()
        repositories.remove(at: index)
        if lastActive[tab] == id {
            lastActive[tab] = nil
        }
        if selectedRepositoryID == id {
            if let sibling = repositories.first(where: { Self.tabID(of: $0) == tab }) {
                selectedRepositoryID = sibling.id
            } else {
                selectedRepositoryID = repositories.indices.contains(index) ? repositories[index].id : repositories.last?.id
            }
        }
    }
}

/// One repository tab: the worktrees of a repository you have open, and the
/// one it shows.
@MainActor
struct RepositoryTab: Identifiable {
    /// The repository's common git dir.
    let id: String
    /// Open worktrees, in the order they were opened.
    let members: [RepositoryStore]
    let active: RepositoryStore

    /// The main worktree's folder name, which names the repository even when
    /// only a linked worktree is open.
    var name: String {
        if let main = active.worktrees.first(where: { !$0.isBare }) {
            return main.path.lastPathComponent
        }
        let commonDir = URL(fileURLWithPath: id)
        if commonDir.lastPathComponent == ".git" {
            return commonDir.deletingLastPathComponent().lastPathComponent
        }
        if let root = active.root, commonDir.path == root.resolvingSymlinksInPath().standardizedFileURL.path {
            return root.lastPathComponent
        }
        let name = commonDir.lastPathComponent
        return name.hasSuffix(".git") ? String(name.dropLast(4)) : name
    }

    /// The repository's worktrees you can switch to: all of them Git lists,
    /// main first, without bare ones.
    var worktrees: [Worktree] {
        active.worktrees.filter { !$0.isBare }
    }

    /// Whether the tab shows `worktree`.
    func isActive(_ worktree: Worktree) -> Bool {
        active.root?.resolvingSymlinksInPath().standardizedFileURL.path == worktree.path.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The open worktree at `worktree`'s path, if any.
    func member(for worktree: Worktree) -> RepositoryStore? {
        let path = worktree.path.resolvingSymlinksInPath().standardizedFileURL.path
        return members.first { $0.root?.resolvingSymlinksInPath().standardizedFileURL.path == path }
    }

    var hasUnseenProposal: Bool {
        members.contains { $0.hasUnseenProposal }
    }

    /// Uncommitted changes across the open worktrees.
    var changeCount: Int {
        members.reduce(0) { $0 + $1.entries.count }
    }
}
