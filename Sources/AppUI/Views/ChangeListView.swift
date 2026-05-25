import AppKit
import GitKit
import SwiftUI

struct ChangeListView: View {
    let store: RepositoryStore
    var switchToAllCommits: (() -> Void)?

    @Bindable private var config = ConfigStore.shared

    var body: some View {
        VStack(spacing: 0) {
            sectionToolbar
            Divider()
            content
        }
    }

    private var isTreeMode: Bool {
        config.config.appearance.fileListMode == "tree"
    }

    private var sectionToolbar: some View {
        HStack(spacing: 6) {
            Text("Changes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if isTreeMode {
                Button {
                    store.expandAllFolders()
                } label: {
                    Image(systemName: "chevron.down.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Expand all folders")
                .accessibilityLabel("Expand all folders")
                .disabled(store.entries.isEmpty)

                Button {
                    store.collapseAllFolders()
                } label: {
                    Image(systemName: "chevron.up.square")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse all folders")
                .accessibilityLabel("Collapse all folders")
                .disabled(store.expandedFolders.isEmpty)
            }
            Button {
                let next = isTreeMode ? "flat" : "tree"
                config.update { $0.appearance.fileListMode = next }
            } label: {
                Image(systemName: isTreeMode ? "list.bullet" : "rectangle.stack")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isTreeMode ? "Switch to flat list" : "Switch to tree view")
            .accessibilityLabel(isTreeMode ? "Switch to flat list" : "Switch to tree view")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            CleanTreeCard(store: store, switchToAllCommits: switchToAllCommits)
        } else if isTreeMode {
            treeList
        } else {
            flatList
        }
    }

    private var flatList: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                unstagedFlatSection
                stagedFlatSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(Glass.Motion.snappy, value: stagingAnimationKey)
            .onChange(of: store.selectedPath) { _, newValue in
                guard let newValue else { return }
                withAnimation(Glass.Motion.snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var treeList: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                unstagedTreeSection
                stagedTreeSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(Glass.Motion.snappy, value: stagingAnimationKey)
            .onChange(of: store.selectedPath) { _, newValue in
                guard let newValue else { return }
                withAnimation(Glass.Motion.snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var unstagedFlatSection: some View {
        Section {
            if store.unstagedEntries.isEmpty {
                Text("Nothing to stage")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(store.unstagedEntries) { file in
                    ChangeRow(file: file, staged: false, store: store)
                        .tag(file.path)
                        .id(file.path)
                }
            }
        } header: {
            StagingSectionHeader(
                title: "Changes",
                count: store.unstagedEntries.count,
                actionIcon: "plus.rectangle.on.rectangle",
                actionHelp: "Stage all",
                actionEnabled: store.canStageAll
            ) {
                Task { await store.stageAll() }
            }
        }
    }

    @ViewBuilder
    private var stagedFlatSection: some View {
        if !store.stagedEntries.isEmpty {
            Section {
                ForEach(store.stagedEntries) { file in
                    ChangeRow(file: file, staged: true, store: store)
                        .tag(file.path)
                        .id(file.path)
                }
            } header: {
                StagingSectionHeader(
                    title: "Staged",
                    count: store.stagedEntries.count,
                    actionIcon: "minus.rectangle",
                    actionHelp: "Unstage all",
                    actionEnabled: store.canUnstageAll
                ) {
                    Task { await store.unstageAll() }
                }
            }
        }
    }

    @ViewBuilder
    private var unstagedTreeSection: some View {
        Section {
            if store.unstagedEntries.isEmpty {
                Text("Nothing to stage")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                treeRows(for: store.unstagedEntries, staged: false)
            }
        } header: {
            StagingSectionHeader(
                title: "Changes",
                count: store.unstagedEntries.count,
                actionIcon: "plus.rectangle.on.rectangle",
                actionHelp: "Stage all",
                actionEnabled: store.canStageAll
            ) {
                Task { await store.stageAll() }
            }
        }
    }

    @ViewBuilder
    private var stagedTreeSection: some View {
        if !store.stagedEntries.isEmpty {
            Section {
                treeRows(for: store.stagedEntries, staged: true)
            } header: {
                StagingSectionHeader(
                    title: "Staged",
                    count: store.stagedEntries.count,
                    actionIcon: "minus.rectangle",
                    actionHelp: "Unstage all",
                    actionEnabled: store.canUnstageAll
                ) {
                    Task { await store.unstageAll() }
                }
            }
        }
    }

    /// Stable key for List animations: counts plus boundary paths. Bulk refreshes
    /// from the watcher won't trip the animation unless the visible boundary moves.
    private var stagingAnimationKey: String {
        let staged = store.stagedEntries.count
        let unstaged = store.unstagedEntries.count
        let firstU = store.unstagedEntries.first?.path ?? ""
        let lastU = store.unstagedEntries.last?.path ?? ""
        let firstS = store.stagedEntries.first?.path ?? ""
        let lastS = store.stagedEntries.last?.path ?? ""
        return "\(unstaged)|\(staged)|\(firstU)|\(lastU)|\(firstS)|\(lastS)"
    }

    @ViewBuilder
    private func treeRows(for entries: [FileStatus], staged: Bool) -> some View {
        let tree = FileTreeBuilder.build(entries: entries)
        // Auto-expand root level by adding root folder ids when none are tracked yet for this repo.
        // (Folders not yet in `expandedFolders` collapse by default; we keep that behavior.)
        let flat = FileTreeBuilder.flatten(tree, expanded: store.expandedFolders)
        ForEach(flat) { node in
            switch node.payload {
            case .folder(let name, _):
                FolderTreeRow(
                    name: name,
                    path: node.id,
                    depth: node.depth,
                    changedCount: node.changedCount,
                    stagedCount: node.stagedCount,
                    isExpanded: store.expandedFolders.contains(node.id),
                    onToggle: { store.toggleFolderExpanded(node.id) }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            case .file(let file):
                ChangeRow(file: file, staged: staged, store: store)
                    .tag(file.path)
                    .padding(.leading, CGFloat(node.depth + 1) * 12)
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedPath },
            set: { newValue in
                let file = store.entries.first { $0.path == newValue }
                Task { await store.select(file) }
            }
        )
    }

    private var summary: String {
        let staged = store.stagedEntries.count
        let unstaged = store.unstagedEntries.count
        if staged == 0, unstaged == 0 { return "Clean" }
        if staged == 0 { return "\(unstaged) changed" }
        if unstaged == 0 { return "\(staged) staged" }
        return "\(staged) staged · \(unstaged) changed"
    }
}

private struct StagingSectionHeader: View {
    let title: String
    let count: Int
    let actionIcon: String
    let actionHelp: String
    let actionEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .frame(minHeight: 14)
                .background(
                    Capsule().fill(Color.primary.opacity(0.10))
                )
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: actionIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!actionEnabled)
            .opacity(actionEnabled ? 1 : 0.35)
            .help(actionHelp)
        }
        .padding(.vertical, 2)
    }
}

private struct CleanTreeCard: View {
    let store: RepositoryStore
    var switchToAllCommits: (() -> Void)?

    var body: some View {
        AviEmptyState(
            icon: "checkmark.seal",
            title: "Working tree clean",
            message: subhead,
            iconTint: DS.Palette.success
        ) {
            if let switchToAllCommits {
                AviButton("View History", icon: "clock.arrow.circlepath", variant: .secondary, size: .small, action: switchToAllCommits)
                    .frame(maxWidth: .infinity)
            }
            AviButton("Create Branch", icon: "arrow.triangle.branch", variant: .secondary, size: .small) {
                NotificationCenter.default.post(name: .aviCreateBranch, object: nil)
            }
            .frame(maxWidth: .infinity)
            if store.branch?.upstream != nil {
                AviButton("Pull", icon: "arrow.down.to.line", variant: .secondary, size: .small) {
                    Task { await store.pull() }
                }
                .frame(maxWidth: .infinity)
            }
            AviButton("Open Folder", icon: "folder", variant: .secondary, size: .small) {
                guard let root = store.root else { return }
                NSWorkspace.shared.open(root)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var subhead: String {
        guard let branch = store.branch?.name else {
            return "No staged or unstaged changes."
        }
        if let upstream = store.branch?.upstream {
            return "On \(branch). Tracking \(upstream)."
        }
        return "On \(branch)."
    }
}

private struct ChangeRow: View {
    let file: FileStatus
    let staged: Bool
    let store: RepositoryStore
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badge.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(badge.color)
                .frame(width: 12)
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if staged {
                inlineAction("minus.circle", help: "Unstage") {
                    Task { await store.unstage(file) }
                }
            } else {
                inlineAction("plus.circle", help: "Stage") {
                    Task { await store.stage(file) }
                }
                inlineAction("arrow.uturn.backward.circle", help: "Discard") {
                    confirmingDiscard = true
                }
            }
        }
        .font(.system(size: 12))
        .padding(.vertical, 1)
        .contextMenu {
            fileContextMenu
        }
        .confirmationDialog(
            "Discard changes to \(file.path)?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                Task { await store.discard(file) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private var fileContextMenu: some View {
        if staged {
            Button("Unstage") {
                Task { await store.unstage(file) }
            }
        } else {
            Button("Stage") {
                Task { await store.stage(file) }
            }
            Button("Discard…", role: .destructive) {
                confirmingDiscard = true
            }
        }

        Divider()

        Button("Open File") {
            store.openFile(file)
        }
        Button("Reveal in Finder") {
            store.revealInFinder(file)
        }

        Menu("Copy Path") {
            Button("Relative") {
                store.copyRelativePath(file)
            }
            Button("Absolute") {
                store.copyAbsolutePath(file)
            }
        }
    }

    private func inlineAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var displayName: String {
        if let originalPath = file.originalPath {
            return "\(originalPath) → \(file.path)"
        }
        return file.path
    }

    private var badge: (symbol: String, color: Color) {
        switch staged ? file.index : file.worktree {
        case .added, .untracked: ("plus", .green)
        case .modified, .typeChanged: ("pencil", .orange)
        case .deleted: ("minus", .red)
        case .renamed: ("arrow.right", .blue)
        case .copied: ("doc.on.doc", .blue)
        case .updatedButUnmerged: ("exclamationmark.triangle", .yellow)
        case .unmodified, .ignored: ("circle", .gray)
        }
    }
}

private struct FolderTreeRow: View {
    let name: String
    let path: String
    let depth: Int
    let changedCount: Int
    let stagedCount: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(changedCount)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                if stagedCount > 0 {
                    Text("(\(stagedCount) staged)")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12 + 8)
            .padding(.trailing, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(path)
        .accessibilityLabel("\(name) folder, \(changedCount) changed file\(changedCount == 1 ? "" : "s")")
    }
}
