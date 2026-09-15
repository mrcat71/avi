import AppKit
import SwiftUI

/// Top-level view hosted by the app shell. Owns the open repository tabs and
/// routes commands to the selected repository.
public struct RootView: View {
    @State private var session = WorkspaceSession()
    private var repositories: [RepositoryStore] {
        session.repositories
    }

    private var openErrorMessage: String? {
        get { session.errorMessage }
        nonmutating set { session.errorMessage = newValue }
    }

    @State private var showingPicker: Bool = false
    @State private var showingCloneSheet: Bool = false

    public init() {}

    public var body: some View {
        Group {
            if let selectedStore {
                RepositoryView(
                    store: selectedStore,
                    repositories: repositories,
                    selectedRepositoryID: Binding(get: { session.selectedRepositoryID }, set: { session.select($0) }),
                    openRepositoryPicker: openRepositoryPicker,
                    closeRepository: closeRepository
                )
                .id(selectedStore.id)
                .sheet(isPresented: $showingPicker) {
                    RepositoryPickerView(
                        openRepository: { url in
                            openRepository(url)
                        },
                        onClone: { showingPicker = false; showingCloneSheet = true },
                        onDismiss: { showingPicker = false },
                        presentation: .sheet
                    )
                }
            } else {
                RepositoryPickerView(
                    openRepository: openRepository,
                    onClone: { showingCloneSheet = true },
                    onDismiss: nil,
                    presentation: .standalone
                )
            }
        }
        .sheet(isPresented: $showingCloneSheet) {
            CloneSheet(
                onClone: { url in openRepository(url) },
                onDismiss: { showingCloneSheet = false }
            )
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
        session.selectedRepository
    }

    private var openErrorPresented: Binding<Bool> {
        Binding(
            get: { openErrorMessage != nil },
            set: {
                presented in if !presented {
                    openErrorMessage = nil
                }
            }
        )
    }

    private func openRepositoryPicker() {
        if selectedStore == nil {
            // We're already on the picker (standalone empty state). Nothing to open.
            return
        }
        showingPicker = true
    }

    private func openRepository(_ url: URL) {
        Task { await session.open(url) }
    }

    private func closeRepository(_ id: RepositoryStore.ID) {
        session.close(id)
    }
}
