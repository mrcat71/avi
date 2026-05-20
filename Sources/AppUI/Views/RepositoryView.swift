import GitKit
import SwiftUI

struct RepositoryView: View {
    let store: RepositoryStore
    let repositories: [RepositoryStore]
    @Binding var selectedRepositoryID: RepositoryStore.ID?
    let openRepositoryPicker: () -> Void
    let closeRepository: (RepositoryStore.ID) -> Void

    @State private var selection: RepositorySelection = .allCommits

    var body: some View {
        VStack(spacing: 0) {
            RepositoryTabsBar(
                repositories: repositories,
                selectedRepositoryID: $selectedRepositoryID,
                openRepositoryPicker: openRepositoryPicker,
                closeRepository: closeRepository
            )

            HSplitView {
                RepositorySidebarView(selection: $selection, store: store)
                    .frame(minWidth: 260, idealWidth: 286, maxWidth: 340)

                VStack(spacing: 0) {
                    RepositoryActionToolbarView(
                        store: store,
                        openRepositoryPicker: openRepositoryPicker
                    )
                    Divider()
                    ForkWorkspaceView(store: store, selection: selection)
                }
                .frame(minWidth: 760)
            }
        }
        .background(AviWorkspaceBackground())
        .navigationTitle(store.root?.lastPathComponent ?? "Avi")
        .task(id: store.id) { await store.refresh() }
        .alert("Git Error", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.dismissError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { presented in if !presented { store.dismissError() } }
        )
    }
}

enum RepositorySelection: Hashable {
    case localChanges
    case allCommits
    case remotes
}

private struct RepositoryTabsBar: View {
    let repositories: [RepositoryStore]
    @Binding var selectedRepositoryID: RepositoryStore.ID?
    let openRepositoryPicker: () -> Void
    let closeRepository: (RepositoryStore.ID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(repositories) { repository in
                        RepositoryTabButton(
                            repository: repository,
                            isSelected: repository.id == selectedRepositoryID,
                            canClose: repositories.count > 1,
                            select: { selectedRepositoryID = repository.id },
                            close: { closeRepository(repository.id) }
                        )
                    }
                }
                .padding(.vertical, 7)
            }

            Button(action: openRepositoryPicker) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .help("Open another repository")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
        }
    }
}

private struct RepositoryTabButton: View {
    let repository: RepositoryStore
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(repository.root?.lastPathComponent ?? "Repository")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(tabDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, canClose ? 4 : 10)
                .frame(width: 172, height: 32, alignment: .leading)
            }
            .buttonStyle(.plain)

            if canClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .help("Close repository")
            }
        }
        .background(isSelected ? .regularMaterial : .thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : .white.opacity(0.08), lineWidth: 1)
        }
    }

    private var tabDetail: String {
        if let name = repository.branch?.name {
            let changes = repository.entries.count
            return changes == 0 ? name : "\(name), \(changes) changes"
        }
        if repository.branch?.isDetached == true { return "Detached HEAD" }
        return "Loading"
    }
}

private struct RepositoryActionToolbarView: View {
    let store: RepositoryStore
    let openRepositoryPicker: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            toolbarButton("Open", systemImage: "folder", action: openRepositoryPicker)

            toolbarDivider

            toolbarButton("Fetch", systemImage: "arrow.down.circle") {
                Task { await store.fetch(remote: nil) }
            }
            .disabled(store.remotes.isEmpty || store.isRemoteOperationRunning)

            toolbarButton("Pull", systemImage: "arrow.down.to.line") {
                Task { await store.pull() }
            }
            .disabled(store.isRemoteOperationRunning || store.branch?.isUnborn != false)

            toolbarButton("Push", systemImage: "arrow.up.to.line") {
                Task { await store.push() }
            }
            .disabled(store.isRemoteOperationRunning || store.branch?.isUnborn != false)

            toolbarDivider

            toolbarButton("Refresh", systemImage: "arrow.clockwise") {
                Task { await store.refresh() }
            }
            .disabled(store.isLoading)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(store.root?.lastPathComponent ?? "Avi")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(branchSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(.thinMaterial)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1, height: 34)
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .medium))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 64, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var branchSummary: String {
        guard let branch = store.branch else { return "Loading" }
        if let name = branch.name {
            var parts = [name]
            if branch.ahead > 0 { parts.append("ahead \(branch.ahead)") }
            if branch.behind > 0 { parts.append("behind \(branch.behind)") }
            return parts.joined(separator: ", ")
        }
        if branch.isDetached { return "Detached HEAD" }
        return "No commits"
    }
}

private struct ForkWorkspaceView: View {
    let store: RepositoryStore
    let selection: RepositorySelection

    var body: some View {
        VSplitView {
            HistoryListView(store: store, refBadgesByOID: refBadgesByOID)
                .frame(minHeight: 180, idealHeight: 320)
                .aviPane()

            bottomContent
                .frame(minHeight: 320, idealHeight: 380)
                .aviPane()
        }
    }

    @ViewBuilder
    private var bottomContent: some View {
        switch selection {
        case .localChanges:
            LocalChangesInspectorView(store: store)
        case .allCommits:
            CommitDetailView(store: store)
        case .remotes:
            HSplitView {
                RemotesView(store: store)
                    .frame(minWidth: 260, idealWidth: 320)
                RemoteDetailView(store: store)
                    .frame(minWidth: 460)
            }
        }
    }

    private var refBadgesByOID: [String: [HistoryRefBadge]] {
        var badges: [String: [HistoryRefBadge]] = [:]

        func append(_ label: String, ref: GitReference, to oid: String) {
            badges[oid, default: []].append(HistoryRefBadge(label: label, ref: ref))
        }

        for ref in store.refs.localBranches {
            append(ref.isCurrent ? "✓ \(ref.name)" : ref.name, ref: ref, to: ref.oid)
        }
        for ref in store.refs.remoteBranches {
            append(ref.name, ref: ref, to: ref.oid)
        }
        for ref in store.refs.tags {
            append("tag \(ref.name)", ref: ref, to: ref.oid)
        }

        return badges
    }
}

private struct LocalChangesInspectorView: View {
    let store: RepositoryStore

    var body: some View {
        VSplitView {
            HSplitView {
                ChangeListView(store: store)
                    .frame(minWidth: 300, idealWidth: 380)
                DiffDetailView(store: store)
                    .frame(minWidth: 460)
            }
            .frame(minHeight: 220, idealHeight: 280)

            CommitPanelView(store: store)
                .frame(minHeight: 158, idealHeight: 178, maxHeight: 220)
        }
    }
}

private struct AviWorkspaceBackground: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.10)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                    Color.black.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private extension View {
    func aviPane() -> some View {
        background(.thinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 1)
            }
    }
}
