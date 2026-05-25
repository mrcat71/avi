import AppKit
import GitKit
import SwiftUI

struct RepositoryView: View {
    let store: RepositoryStore
    let repositories: [RepositoryStore]
    @Binding var selectedRepositoryID: RepositoryStore.ID?
    let openRepositoryPicker: () -> Void
    let closeRepository: (RepositoryStore.ID) -> Void

    @State private var selection: RepositorySelection? = nil
    @State private var hasAppliedInitialSelection = false
    @State private var showingCreateBranch = false
    @State private var createBranchStartPoint: String? = nil
    @State private var createTagTargetOID: String? = nil
    @State private var showingCommandPalette = false

    var body: some View {
        VStack(spacing: 0) {
            RepositoryTabsBar(
                repositories: repositories,
                selectedRepositoryID: $selectedRepositoryID,
                openRepositoryPicker: openRepositoryPicker,
                closeRepository: closeRepository
            )

            HSplitView {
                RepositorySidebarView(
                    selection: selectionBinding,
                    store: store
                )
                .frame(
                    minWidth: AppPreferences.minSidebarWidth,
                    idealWidth: AppPreferences.sidebarWidth,
                    maxWidth: AppPreferences.maxSidebarWidth
                )

                VStack(spacing: 0) {
                    RepositoryActionToolbarView(
                        store: store,
                        openRepositoryPicker: openRepositoryPicker
                    )
                    Divider()
                    workspace
                }
                .frame(minWidth: 760)
            }
        }
        .background(AviWorkspaceBackground())
        .navigationTitle(store.root?.lastPathComponent ?? "Avi")
        .observeDensity()
        .task(id: store.id) {
            await store.refresh()
            applyInitialSelectionIfNeeded()
        }
        .onChange(of: store.entries.isEmpty) { _, _ in
            applyInitialSelectionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviCreateBranch)) { notification in
            createBranchStartPoint = notification.object as? String
            showingCreateBranch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviCreateTag)) { notification in
            createTagTargetOID = notification.object as? String
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviOpenCommandPalette)) { _ in
            showingCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviGoToLocalChanges)) { _ in
            selection = .localChanges
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviGoToAllCommits)) { _ in
            selection = .allCommits
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviToggleHistoryScope)) { _ in
            let next: HistoryFilter.Scope
            switch store.historyFilter.scope {
            case .currentBranch: next = .allBranches
            case .allBranches, .ref: next = .currentBranch
            }
            Task { await store.setHistoryFilter(HistoryFilter(scope: next, hideMerges: store.historyFilter.hideMerges)) }
        }
        .sheet(isPresented: $showingCreateBranch, onDismiss: { createBranchStartPoint = nil }) {
            CreateBranchSheet(store: store, startPoint: createBranchStartPoint)
        }
        .sheet(item: Binding(
            get: { createTagTargetOID.map { CreateTagSheet.Target(oid: $0) } },
            set: { createTagTargetOID = $0?.oid }
        )) { target in
            CreateTagSheet(store: store, targetOID: target.oid)
        }
        .sheet(isPresented: $showingCommandPalette) {
            CommandPalette(
                commands: CommandRegistry.commands(
                    store: store,
                    setSelection: { selection = $0 },
                    openCreateBranch: { showingCommandPalette = false; showingCreateBranch = true }
                ),
                isPresented: $showingCommandPalette
            )
            .padding(.top, 80)
            .background(Color.clear)
        }
        .alert("Git Error", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.dismissError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(isPresented: aiRewordPresented) {
            if let preview = store.aiRewordPreview {
                AIRewordSheet(store: store, preview: preview)
            }
        }
        .sheet(isPresented: aiSplitLoadingPresented) {
            AISplitLoadingSheet(onCancel: { store.dismissAISplitPreview() })
        }
        .sheet(isPresented: aiSplitPresented) {
            if let preview = store.aiSplitPreview {
                AISplitSheet(store: store, preview: preview)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.rebaseInProgress {
                rebaseBanner
            }
        }
    }

    private var aiRewordPresented: Binding<Bool> {
        Binding(
            get: { store.aiRewordPreview != nil },
            set: { presented in
                if !presented { store.dismissAIRewordPreview() }
            }
        )
    }

    private var aiSplitPresented: Binding<Bool> {
        Binding(
            get: { store.aiSplitPreview != nil && !store.isAIWorking },
            set: { presented in
                if !presented { store.dismissAISplitPreview() }
            }
        )
    }

    private var aiSplitLoadingPresented: Binding<Bool> {
        Binding(
            get: { store.isAIWorking && store.aiSplitPreview == nil },
            set: { _ in }
        )
    }

    private var rebaseBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Rebase in progress")
                    .font(.system(size: 12, weight: .semibold))
                Text("Resolve any conflicts in the working tree, then run `git rebase --continue` in a terminal.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Terminal") {
                if let root = store.root {
                    NSWorkspace.shared.open(root)
                }
            }
            .controlSize(.small)
            Button("Abort rebase", role: .destructive) {
                store.cancelOngoingRebase()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Glass.edgeStroke).frame(height: 0.6)
        }
    }

    private var selectionBinding: Binding<RepositorySelection> {
        Binding(
            get: { selection ?? .allCommits },
            set: { newValue in
                selection = newValue
                if let persisted = newValue.persisted {
                    AppPreferences.lastSelectedView = persisted
                }
            }
        )
    }

    @ViewBuilder
    private var workspace: some View {
        switch selection ?? .allCommits {
        case .localChanges:
            LocalChangesWorkspaceView(
                store: store,
                switchToAllCommits: { selection = .allCommits }
            )
        case .allCommits, .branch, .remoteBranch, .tag:
            HistoryWorkspaceView(store: store)
        }
    }

    private func applyInitialSelectionIfNeeded() {
        guard !hasAppliedInitialSelection else { return }
        guard !store.isLoading else { return }
        guard store.root != nil else { return }

        hasAppliedInitialSelection = true

        if let saved = AppPreferences.lastSelectedView {
            switch saved {
            case .localChanges where !store.entries.isEmpty:
                selection = .localChanges
                return
            case .allCommits:
                selection = .allCommits
                return
            default:
                break
            }
        }

        selection = store.entries.isEmpty ? .allCommits : .localChanges
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
    case branch(name: String)
    case remoteBranch(name: String)
    case tag(name: String)

    var persisted: PersistedView? {
        switch self {
        case .localChanges: return .localChanges
        case .allCommits, .branch, .remoteBranch, .tag: return .allCommits
        }
    }
}

private struct RepositoryTabsBar: View {
    let repositories: [RepositoryStore]
    @Binding var selectedRepositoryID: RepositoryStore.ID?
    let openRepositoryPicker: () -> Void
    let closeRepository: (RepositoryStore.ID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
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
                .padding(.vertical, 4)
            }

            Button(action: openRepositoryPicker) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open another repository")
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Glass.edgeStroke)
                .frame(height: 0.6)
        }
    }
}

private struct RepositoryTabButton: View {
    let repository: RepositoryStore
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Button(action: select) {
                    HStack(spacing: 6) {
                        if repository.entries.count > 0 {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .help("\(repository.entries.count) uncommitted change\(repository.entries.count == 1 ? "" : "s")")
                        } else {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                        Text(repository.root?.lastPathComponent ?? "Repository")
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, canClose ? 2 : 9)
                    .frame(height: 24, alignment: .leading)
                    .frame(minWidth: 110, maxWidth: 180)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tabDetail)

                if canClose {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering || isSelected ? 1 : 0)
                    .help("Close repository")
                    .accessibilityLabel("Close repository")
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.06) : (isHovering ? Color.primary.opacity(0.04) : Color.clear))
            )
            .onHover { isHovering = $0 }

            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
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

    @State private var showingPushSheet = false

    var body: some View {
        HStack(spacing: 2) {
            ToolbarPillButton(title: "Open", systemImage: "folder", action: openRepositoryPicker)

            toolbarDivider

            ToolbarPillButton(
                title: "Fetch",
                systemImage: "arrow.down",
                helpText: fetchHelp
            ) {
                Task { await store.fetch(remote: nil) }
            }
            .disabled(store.remotes.isEmpty || store.isRemoteOperationRunning)

            ToolbarPillButton(
                title: "Pull",
                systemImage: "arrow.down.to.line",
                badge: behindBadge,
                badgeTint: .blue,
                helpText: pullHelp
            ) {
                Task { await store.pull() }
            }
            .disabled(!canPullPush)

            ToolbarPillButton(
                title: "Push",
                systemImage: "arrow.up.to.line",
                badge: aheadBadge,
                badgeTint: .green,
                helpText: pushHelp
            ) {
                showingPushSheet = true
            }
            .disabled(!canPullPush)

            if let providerURL = providerWebURL {
                toolbarDivider
                ToolbarPillButton(
                    title: providerName,
                    systemImage: "safari",
                    helpText: "Open repository on \(providerName) in browser"
                ) {
                    NSWorkspace.shared.open(providerURL)
                }
            }

            Spacer()

            SyncStatusPill(store: store)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Glass.edgeStroke)
                .frame(height: 0.6)
        }
        .sheet(isPresented: $showingPushSheet) {
            PushSheet(store: store, dismiss: { showingPushSheet = false })
        }
        .overlay(alignment: .topTrailing) {
            if store.isLoading || store.isRemoteOperationRunning {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                    .opacity(0.75)
            }
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var canPullPush: Bool {
        !store.isRemoteOperationRunning && store.branch?.isUnborn == false
    }

    private var aheadBadge: String? {
        guard let ahead = store.branch?.ahead, ahead > 0 else { return nil }
        return "\(ahead)"
    }

    private var behindBadge: String? {
        guard let behind = store.branch?.behind, behind > 0 else { return nil }
        return "\(behind)"
    }

    private var fetchHelp: String {
        store.remotes.isEmpty ? "No remotes configured" : "Fetch from all remotes"
    }

    private var pullHelp: String {
        guard let branch = store.branch else { return "Pull" }
        let name = branch.name ?? "current branch"
        if branch.isUnborn { return "No commits yet" }
        guard let upstream = branch.upstream else { return "Set upstream for \(name) first" }
        if branch.behind > 0 {
            return "Pull \(branch.behind) commit\(branch.behind == 1 ? "" : "s") from \(upstream) into \(name)"
        }
        return "\(name) is up to date with \(upstream)"
    }

    private var pushHelp: String {
        guard let branch = store.branch else { return "Push" }
        let name = branch.name ?? "current branch"
        if branch.isUnborn { return "No commits yet" }
        guard let upstream = branch.upstream else { return "Push \(name) and set upstream to origin/\(name)" }
        if branch.ahead > 0 {
            return "Push \(branch.ahead) commit\(branch.ahead == 1 ? "" : "s") from \(name) to \(upstream)"
        }
        return "\(name) is in sync with \(upstream)"
    }

    private var providerHint: ProviderHint {
        guard let remote = store.remotes.first(where: { $0.name == "origin" }) ?? store.remotes.first else {
            return .unknown
        }
        return RemoteURLParser.hint(from: remote)
    }

    private var providerName: String {
        switch providerHint {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .unknown: return ""
        }
    }

    private var providerWebURL: URL? {
        switch providerHint {
        case .github(let owner, let repo):
            return GitHubAPI.repoWebURL(owner: owner, repo: repo)
        case .gitlab(let host, let projectPath):
            return GitLabAPI.projectWebURL(host: host, projectPath: projectPath)
        case .unknown:
            return nil
        }
    }
}

struct ToolbarPillButton: View {
    let title: String
    let systemImage: String
    var badge: String?
    var badgeTint: Color = .accentColor
    var helpText: String?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: DS.IconScale.lg, weight: .medium))
                Text(title)
                    .font(.system(size: DS.IconScale.lg, weight: .medium))
                if let badge {
                    Text(badge)
                        .font(.system(size: DS.IconScale.sm, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DS.Spacing.sm + 1)
                        .frame(minWidth: 18, minHeight: 14)
                        .background(
                            Capsule().fill(badgeTint.opacity(0.20))
                        )
                        .foregroundStyle(badgeTint)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .frame(height: 28)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(isHovering && isEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
                    if isHovering, isEnabled {
                        Capsule(style: .continuous)
                            .fill(Glass.hoverTint())
                    }
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isHovering && isEnabled ? Glass.edgeStroke : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isHovering && isEnabled ? 1.0 : 1.0)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .animation(Glass.Motion.snappy, value: isHovering)
        .help(helpText ?? title)
        .accessibilityLabel(helpText ?? title)
    }
}

private struct SyncStatusPill: View {
    let store: RepositoryStore
    @State private var showingPicker = false
    @State private var isHovering = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(branchName)
                    .font(.system(size: 12, weight: .semibold))

                if let upstream = store.branch?.upstream {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(upstream)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let aheadBehind = aheadBehindText {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(aheadBehind)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if store.entries.count > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(store.entries.count) dirty")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule().fill(isHovering ? Color.primary.opacity(0.10) : Color.primary.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            BranchSwitcherPopover(store: store, isPresented: $showingPicker)
        }
    }

    private var branchName: String {
        if let name = store.branch?.name { return name }
        if store.branch?.isDetached == true { return "Detached HEAD" }
        if store.branch?.isUnborn == true { return "No commits" }
        return store.branch == nil ? "Loading" : "Unknown"
    }

    private var statusColor: Color {
        guard let branch = store.branch else { return .gray }
        if branch.isDetached { return .red }
        if store.entries.count > 0 { return .orange }
        return .green
    }

    private var aheadBehindText: String? {
        guard let branch = store.branch else { return nil }
        var parts: [String] = []
        if branch.ahead > 0 { parts.append("↑\(branch.ahead)") }
        if branch.behind > 0 { parts.append("↓\(branch.behind)") }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " ")
    }

    private var tooltip: String {
        var parts = [branchName]
        if let upstream = store.branch?.upstream {
            parts.append("tracks \(upstream)")
        }
        if let branch = store.branch {
            if branch.ahead > 0 { parts.append("ahead \(branch.ahead)") }
            if branch.behind > 0 { parts.append("behind \(branch.behind)") }
        }
        if store.entries.count > 0 {
            parts.append("\(store.entries.count) uncommitted change\(store.entries.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

struct HistoryWorkspaceView: View {
    let store: RepositoryStore

    var body: some View {
        VSplitView {
            HistoryListView(store: store, refBadgesByOID: refBadgesByOID)
                .frame(minHeight: 180, idealHeight: 320)
                .aviPane()

            CommitDetailView(store: store)
                .frame(minHeight: 320, idealHeight: 380)
                .aviPane()
        }
    }

    private var refBadgesByOID: [String: [HistoryRefBadge]] {
        var badges: [String: [HistoryRefBadge]] = [:]

        for ref in store.refs.localBranches {
            badges[ref.oid, default: []].append(HistoryRefBadge(label: ref.name, ref: ref))
        }
        for ref in store.refs.remoteBranches {
            badges[ref.oid, default: []].append(HistoryRefBadge(label: ref.name, ref: ref))
        }
        for ref in store.refs.tags {
            badges[ref.oid, default: []].append(HistoryRefBadge(label: ref.name, ref: ref))
        }

        return badges
    }
}

struct LocalChangesWorkspaceView: View {
    let store: RepositoryStore
    let switchToAllCommits: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LocalChangesStatusBar(store: store)
            Divider()
            HSplitView {
                ChangeListView(store: store, switchToAllCommits: switchToAllCommits)
                    .frame(minWidth: 300, idealWidth: 380)
                    .aviPane()

                VSplitView {
                    DiffDetailView(store: store)
                        .frame(minHeight: 240)
                        .aviPane()
                    CommitPanelView(store: store)
                        .frame(minHeight: 158, idealHeight: 220)
                        .aviPane()
                }
                .frame(minWidth: 460)
            }
        }
    }
}

private struct LocalChangesStatusBar: View {
    let store: RepositoryStore

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if let branchName = store.branch?.name {
                Text("·")
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branchName)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }

            if let upstream = store.branch?.upstream {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(upstream)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let aheadBehind = aheadBehindText {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(aheadBehind)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10))
                Text(fetchedLabel)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
            .help(fetchedTooltip)

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Glass.edgeStroke)
                .frame(height: 0.6)
        }
    }

    private var statusLabel: String {
        if store.branch?.isDetached == true { return "detached" }
        let n = store.entries.count
        if n == 0 { return "clean" }
        return n == 1 ? "1 change" : "\(n) changes"
    }

    private var statusColor: Color {
        if store.branch?.isDetached == true { return .red }
        if store.entries.isEmpty { return .green }
        return .orange
    }

    private var aheadBehindText: String? {
        guard let branch = store.branch else { return nil }
        var parts: [String] = []
        if branch.ahead > 0 { parts.append("↑\(branch.ahead)") }
        if branch.behind > 0 { parts.append("↓\(branch.behind)") }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " ")
    }

    private var fetchedLabel: String {
        guard let last = store.lastFetched else { return "never fetched" }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed < 30 { return "fetched just now" }
        if elapsed < 60 * 60 { return "fetched \(Int(elapsed / 60)) min ago" }
        if elapsed < 60 * 60 * 24 { return "fetched \(Int(elapsed / 3600)) h ago" }
        if elapsed < 60 * 60 * 24 * 7 { return "fetched \(Int(elapsed / 86400)) d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "fetched \(formatter.string(from: last))"
    }

    private var fetchedTooltip: String {
        guard let last = store.lastFetched else { return "No fetch has been recorded for this repository." }
        return last.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}

private struct AviWorkspaceBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .underPageBackgroundColor)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func aviPane() -> some View {
        background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Glass.edgeStroke)
                    .frame(height: 0.6)
            }
    }
}

struct BranchSwitcherPopover: View {
    let store: RepositoryStore
    @Binding var isPresented: Bool

    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Switch to branch", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color.primary.opacity(0.04))
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if !filteredLocal.isEmpty {
                        sectionHeader("Local")
                        ForEach(filteredLocal) { ref in
                            BranchSwitcherRow(
                                ref: ref,
                                isCurrent: ref.isCurrent,
                                select: { selectRef(ref) }
                            )
                        }
                    }
                    if !filteredRemote.isEmpty {
                        sectionHeader("Remote")
                        ForEach(filteredRemote) { ref in
                            BranchSwitcherRow(
                                ref: ref,
                                isCurrent: false,
                                select: { selectRef(ref) }
                            )
                        }
                    }
                    if filteredLocal.isEmpty, filteredRemote.isEmpty {
                        Text("No matching branches")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)

            Divider()

            HStack(spacing: 6) {
                Button {
                    isPresented = false
                    NotificationCenter.default.post(name: .aviCreateBranch, object: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Branch")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var filteredLocal: [GitReference] {
        let sorted = store.refs.localBranches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return filtered(sorted)
    }

    private var filteredRemote: [GitReference] {
        filtered(store.refs.remoteBranches)
    }

    private func filtered(_ refs: [GitReference]) -> [GitReference] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return refs }
        return refs.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private func selectRef(_ ref: GitReference) {
        if !ref.isCurrent {
            Task { await store.checkout(ref) }
        }
        isPresented = false
    }
}

private struct BranchSwitcherRow: View {
    let ref: GitReference
    let isCurrent: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                Image(systemName: ref.kind == .tag ? "tag.fill" : (ref.kind == .remoteBranch ? "network" : "arrow.triangle.branch"))
                    .font(.system(size: 10, weight: isCurrent ? .bold : .regular))
                    .frame(width: 14)
                    .foregroundStyle(isCurrent ? Color.accentColor : ref.kind == .remoteBranch ? .purple : .blue)

                Text(displayName)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var displayName: String {
        if ref.kind == .remoteBranch {
            return ref.name
        }
        return ref.name
    }
}

struct CreateBranchSheet: View {
    let store: RepositoryStore
    var startPoint: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var checkout = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Branch")
                .font(.system(size: 14, weight: .semibold))

            if let startPoint {
                Text("From \(startPoint)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let current = store.branch?.name {
                Text("From \(current)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            Toggle("Check out after creating", isOn: $checkout)
                .controlSize(.small)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func create() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        Task {
            await store.createBranch(named: cleaned, startPoint: startPoint, checkout: checkout)
            dismiss()
        }
    }
}

struct CreateTagSheet: View {
    struct Target: Identifiable, Equatable {
        let oid: String
        var id: String {
            oid
        }
    }

    let store: RepositoryStore
    let targetOID: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message = ""
    @State private var pushTag = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Tag")
                .font(.system(size: 14, weight: .semibold))

            Text("At \(String(targetOID.prefix(7)))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField("Name (e.g. v1.2.3)", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            VStack(alignment: .leading, spacing: 4) {
                Text("Message (optional)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .frame(minHeight: 60, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                Text(message.isEmpty ? "Lightweight tag" : "Annotated tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Toggle("Push tag to origin after creating", isOn: $pushTag)
                .controlSize(.small)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func create() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }
        let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldPush = pushTag
        Task {
            await store.createTag(
                name: cleanedName,
                targetOID: targetOID,
                message: cleanedMessage.isEmpty ? nil : cleanedMessage
            )
            if shouldPush {
                await store.pushTag(name: cleanedName)
            }
            dismiss()
        }
    }
}
