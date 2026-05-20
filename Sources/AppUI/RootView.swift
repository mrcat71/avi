import AppKit
import SwiftUI

/// Top-level view hosted by the app shell. Owns the open repository tabs and
/// routes commands to the selected repository.
public struct RootView: View {
    @State private var repositories: [RepositoryStore] = []
    @State private var selectedRepositoryID: RepositoryStore.ID?
    @State private var openErrorMessage: String?

    public init() {}

    public var body: some View {
        Group {
            if let selectedStore {
                RepositoryView(
                    store: selectedStore,
                    repositories: repositories,
                    selectedRepositoryID: $selectedRepositoryID,
                    openRepositoryPicker: openRepositoryPicker,
                    closeRepository: closeRepository
                )
            } else {
                WelcomeView(openRepository: openRepository)
            }
        }
        .frame(minWidth: 1120, minHeight: 700)
        .alert("Git Error", isPresented: openErrorPresented) {
            Button("OK", role: .cancel) { openErrorMessage = nil }
        } message: {
            Text(openErrorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviOpenRepository)) { _ in
            openRepositoryPicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviRefreshRepository)) { _ in
            Task { await selectedStore?.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviStageAll)) { _ in
            Task { await selectedStore?.stageAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviUnstageAll)) { _ in
            Task { await selectedStore?.unstageAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviCommit)) { _ in
            Task { await selectedStore?.commit() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviFetchRepository)) { _ in
            Task { await selectedStore?.fetch(remote: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviPullRepository)) { _ in
            Task { await selectedStore?.pull() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviPushRepository)) { _ in
            Task { await selectedStore?.push() }
        }
    }

    private var selectedStore: RepositoryStore? {
        if let selectedRepositoryID,
           let store = repositories.first(where: { $0.id == selectedRepositoryID }) {
            return store
        }
        return repositories.first
    }

    private var openErrorPresented: Binding<Bool> {
        Binding(
            get: { openErrorMessage != nil },
            set: { presented in if !presented { openErrorMessage = nil } }
        )
    }

    private func openRepositoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRepository(url)
    }

    private func openRepository(_ url: URL) {
        Task { @MainActor in
            let candidate = RepositoryStore()
            await candidate.open(url)

            guard let root = candidate.root else {
                openErrorMessage = candidate.errorMessage ?? "Not a git repository: \(url.path)"
                return
            }

            if let existing = repositories.first(where: { store in
                guard let existingRoot = store.root else { return false }
                return sameRepository(existingRoot, root)
            }) {
                selectedRepositoryID = existing.id
                return
            }

            repositories.append(candidate)
            selectedRepositoryID = candidate.id
        }
    }

    private func closeRepository(_ id: RepositoryStore.ID) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories.remove(at: index)

        guard selectedRepositoryID == id else { return }
        if repositories.indices.contains(index) {
            selectedRepositoryID = repositories[index].id
        } else {
            selectedRepositoryID = repositories.last?.id
        }
    }

    private func sameRepository(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}
