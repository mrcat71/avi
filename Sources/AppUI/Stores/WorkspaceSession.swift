import Foundation
import GitKit
import Observation

/// Owns repository lifetimes independently of whichever SwiftUI view is visible.
@MainActor
@Observable
final class WorkspaceSession {
    private(set) var repositories: [RepositoryStore] = []
    var selectedRepositoryID: RepositoryStore.ID?
    var errorMessage: String?
    private var openingPaths: [String: UUID] = [:]
    private var latestOpenRequest = UUID()
    private let git: GitProviding

    init(git: GitProviding = CLIGitProvider()) {
        self.git = git
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

    func close(_ id: RepositoryStore.ID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].stopBackgroundObservation()
        repositories.remove(at: index)
        if selectedRepositoryID == id {
            selectedRepositoryID = repositories.indices.contains(index) ? repositories[index].id : repositories.last?.id
        }
    }
}
