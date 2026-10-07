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

    init(session: WorkspaceSession) {
        _session = State(initialValue: session)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if AgentSkillsTip.shared.isShowing {
                AgentSkillsTipBanner(tip: AgentSkillsTip.shared)
                Divider()
            }
            workspace
        }
        .task {
            await session.restore()
        }
    }

    /// The open repository or the picker, with the window's sheets, alerts,
    /// and menu commands.
    private var workspace: some View {
        Group {
            if let selectedStore {
                RepositoryView(
                    store: selectedStore,
                    repositories: repositories,
                    selectedRepositoryID: Binding(get: { session.selectedRepositoryID }, set: { session.select($0) }),
                    openRepositoryPicker: openRepositoryPicker,
                    closeRepository: closeRepository,
                    moveRepository: { session.moveRepository($0, toPlaceOf: $1) }
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
        .onAppear {
            AgentBridge.shared.register(session)
        }
        .onDisappear {
            AgentBridge.shared.unregister(session)
        }
        .onChange(of: unseenProposalCount) { _, _ in
            AgentBridge.shared.updateDockBadge()
        }
        .alert(
            approvalTitle,
            isPresented: approvalPresented,
            presenting: AgentBridge.shared.pendingApproval
        ) { _ in
            Button("Open") {
                AgentBridge.shared.resolveApproval(open: true, in: session)
            }
            Button("Cancel", role: .cancel) {
                AgentBridge.shared.resolveApproval(open: false, in: session)
            }
        } message: { approval in
            Text("\(approval.path)\n\nOpening a repository runs Git in it, and its settings can make Git run other programs. Open only repositories you trust.")
        }
        .alert("Git Error", isPresented: openErrorPresented) {
            Button("OK", role: .cancel) { openErrorMessage = nil }
        } message: {
            Text(openErrorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviOpenRepository)) { notification in
            // A URL means "open this path", such as a sibling worktree. The
            // menu command carries nothing and still opens the picker.
            if let url = notification.object as? URL {
                openRepository(url)
            } else {
                openRepositoryPicker()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviWorktreeRemoved)) { notification in
            // A tab on a removed worktree has nothing left to show.
            guard let removed = notification.object as? URL else { return }
            for repository in repositories where repository.root?.standardizedFileURL.path == removed.standardizedFileURL.path {
                closeRepository(repository.id)
            }
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
            guard let store = selectedStore else { return }
            // One commit or several: Commit 1 first, then each planned commit.
            Task { await store.commitStack() }
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

    private var unseenProposalCount: Int {
        repositories.filter(\.hasUnseenProposal).count
    }

    private var approvalTitle: String {
        guard let approval = AgentBridge.shared.pendingApproval else { return "" }
        return "Open this repository for \(approval.requester)?"
    }

    private var approvalPresented: Binding<Bool> {
        Binding(
            get: { AgentBridge.shared.pendingApproval != nil && AgentBridge.shared.presentsApprovals(in: session) },
            set: { presented in
                if !presented, AgentBridge.shared.pendingApproval != nil {
                    AgentBridge.shared.resolveApproval(open: false, in: session)
                }
            }
        )
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
