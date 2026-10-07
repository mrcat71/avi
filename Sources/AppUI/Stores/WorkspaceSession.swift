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
        didSet { saveWorkspace() }
    }

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
            repositories.append(candidate)
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
        repositories.append(candidate)
        if selectedRepositoryID == nil {
            selectedRepositoryID = candidate.id
        }
        return candidate
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

    func close(_ id: RepositoryStore.ID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].stopBackgroundObservation()
        repositories.remove(at: index)
        if selectedRepositoryID == id {
            selectedRepositoryID = repositories.indices.contains(index) ? repositories[index].id : repositories.last?.id
        }
    }
}
