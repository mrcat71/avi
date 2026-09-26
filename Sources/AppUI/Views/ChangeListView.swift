import AppKit
import GitKit
import SwiftUI

/// The Changes column: unstaged files on top and, below them, the commits you
/// are about to make. Commit 1 is the staged files; planned commits follow it.
struct ChangeListView: View {
    let store: RepositoryStore
    var switchToAllCommits: (() -> Void)?

    @Bindable private var config = ConfigStore.shared
    @State private var multiSelection: Set<String> = []
    @State private var stackSelection: Set<String> = []
    /// Cmd+A acts on the list you touched last.
    @State private var stackIsActive = false
    @State private var pendingDiscard: [FileStatus] = []
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            sectionToolbar
            Divider()
            content
        }
        .background(selectAllShortcut)
        .confirmationDialog(
            discardPrompt,
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(pendingDiscard.count > 1 ? "Discard \(pendingDiscard.count) Files" : "Discard", role: .destructive) {
                discardFiles(pendingDiscard)
            }
            Button("Cancel", role: .cancel) {
                pendingDiscard = []
            }
        } message: {
            Text(discardMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aviDiscardSelection)) { _ in
            requestDiscard(selectedUnstagedFiles)
        }
        // Keep the highlight where the store's selection is: here, or in the stack.
        .onChange(of: store.selectedPath) { _, _ in
            syncHighlight()
        }
        .onChange(of: store.selectedDiffSource) { _, _ in
            syncHighlight()
        }
    }

    /// Hidden button that registers Cmd+A as "select all files" in the list you
    /// used last. Lives behind the view so the shortcut is in the responder chain
    /// while a list has focus, without taking visible space.
    private var selectAllShortcut: some View {
        Button("Select All Files") {
            if stackIsActive {
                stackSelection = Set(stackFilePaths.map(PlanRowTag.file))
            } else {
                multiSelection = Set(unstagedEntries.map(\.path))
            }
        }
        .keyboardShortcut("a", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var isTreeMode: Bool {
        config.config.appearance.fileListMode == "tree"
    }

    private var unstagedEntries: [FileStatus] {
        store.unplannedUnstagedEntries
    }

    private var stackFilePaths: [String] {
        store.stagedCommitEntries.map(\.path) + store.commitPlan.drafts.flatMap(\.files)
    }

    private var sectionToolbar: some View {
        HStack(spacing: 6) {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            splitButton
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

    /// Splits every change no planned commit holds, staged or not, into commits.
    private var splitButton: some View {
        let paths = store.splittablePaths
        let help = store.canUseAIForPlan
            ? "Let the AI group every change that is not in a planned commit into commits"
            : "Turn on AI in Settings > AI Commit Messages"
        return ViewThatFits(in: .horizontal) {
            splitButton(paths: paths, help: help, compact: false)
            splitButton(paths: paths, help: help, compact: true)
        }
    }

    private func splitButton(paths: [String], help: String, compact: Bool) -> some View {
        Button {
            store.requestSplit(of: paths, title: paths.count == 1 ? "1 changed file" : "\(paths.count) changed files")
        } label: {
            if compact {
                Image(systemName: "rectangle.split.3x1")
            } else {
                Label("Split into Commits…", systemImage: "rectangle.split.3x1")
            }
        }
        .controlSize(.small)
        .fixedSize()
        .disabled(!store.canUseAIForPlan || paths.count < 2 || store.isRevisingPlan || store.isApplyingPlan)
        .help(help)
        .accessibilityLabel("Split into Commits")
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty, store.commitPlan.isEmpty {
            CleanTreeCard(store: store, switchToAllCommits: switchToAllCommits)
        } else {
            VSplitView {
                unstagedPane
                    .frame(minHeight: unstagedMinHeight, idealHeight: unstagedIdealHeight)
                CommitStackView(store: store, selection: $stackSelection) {
                    stackIsActive = true
                }
                .frame(minHeight: 120, idealHeight: 240)
            }
        }
    }

    private var unstagedMinHeight: CGFloat {
        unstagedEntries.isEmpty ? 34 : 120
    }

    private var unstagedIdealHeight: CGFloat {
        unstagedEntries.isEmpty ? 34 : 240
    }

    private var unstagedPane: some View {
        VStack(spacing: 0) {
            PaneHeader(
                title: "Unstaged",
                count: unstagedEntries.count,
                actionLabel: "Stage",
                actionTint: .accentColor,
                actionEnabled: !selectedUnstagedFiles.isEmpty
            ) {
                stageFiles(selectedUnstagedFiles)
            }
            .dropDestination(for: String.self) { items, _ in
                dropOnUnstaged(items)
            }
            Divider()
            unstagedList
        }
    }

    /// Files currently selected in the unstaged list. Folder ids in `multiSelection`
    /// (from tree mode) are filtered out by intersecting with the entries array.
    private var selectedUnstagedFiles: [FileStatus] {
        unstagedEntries.filter { multiSelection.contains($0.path) }
    }

    /// The list's file paths in the order you see them. Passed to the store so
    /// selection advances to the visually-next file after a stage.
    private func visibleOrder(_ entries: [FileStatus]) -> [String] {
        FileTreeBuilder.visiblePaths(entries, expanded: store.expandedFolders, tree: isTreeMode)
    }

    /// Stage `files` as a single batch and advance selection to the next unstaged
    /// file. Every stage entry point (pane button, row "+", context menu) funnels
    /// through here.
    private func stageFiles(_ files: [FileStatus]) {
        guard !files.isEmpty else { return }
        let order = visibleOrder(unstagedEntries)
        Task { await store.stage(files, advancingFrom: order) }
    }

    /// Files a row action applies to: the whole selection when the row is part
    /// of it, otherwise that row alone.
    private func discardTargets(for file: FileStatus) -> [FileStatus] {
        DiscardTargets.resolve(row: file, selection: multiSelection, entries: unstagedEntries)
    }

    /// Open the confirmation for `files`. Empty input is ignored so the
    /// Cmd+Shift+D path cannot raise an empty dialog.
    private func requestDiscard(_ files: [FileStatus]) {
        guard !files.isEmpty else { return }
        pendingDiscard = files
        confirmingDiscard = true
    }

    /// Discard `files` as a single batch and advance selection to the next
    /// unstaged file.
    private func discardFiles(_ files: [FileStatus]) {
        guard !files.isEmpty else { return }
        let order = visibleOrder(unstagedEntries)
        pendingDiscard = []
        Task { await store.discard(files, advancingFrom: order) }
    }

    private var discardPrompt: String {
        guard let only = pendingDiscard.first, pendingDiscard.count == 1 else {
            return "Discard changes to \(pendingDiscard.count) files?"
        }
        return "Discard changes to \(only.path)?"
    }

    private var discardMessage: String {
        guard pendingDiscard.count > 1 else { return "This cannot be undone." }
        let shown = pendingDiscard.prefix(5).map(\.path).joined(separator: "\n")
        let hidden = pendingDiscard.count - min(pendingDiscard.count, 5)
        let list = hidden > 0 ? "\(shown)\nand \(hidden) more" : shown
        return "\(list)\n\nThis cannot be undone."
    }

    private var unstagedList: some View {
        ScrollViewReader { proxy in
            List(selection: unstagedSelection) {
                if unstagedEntries.isEmpty {
                    Text(store.entries.isEmpty ? "Nothing changed" : "Nothing to stage")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 2)
                        .listRowSeparator(.hidden)
                        .dropDestination(for: String.self) { items, _ in
                            dropOnUnstaged(items)
                        }
                } else if isTreeMode {
                    FileTreeRows(store: store, entries: unstagedEntries, fileTag: { $0 }, folderTag: { $0 }) { file in
                        unstagedRow(file, isTreeRow: true)
                    }
                } else {
                    ForEach(unstagedEntries) { file in
                        unstagedRow(file, isTreeRow: false)
                            .tag(file.path)
                            .id(file.path)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(Glass.Motion.snappy, value: stagingAnimationKey)
            .onChange(of: store.selectedPath) { _, newValue in
                guard let newValue, unstagedEntries.contains(where: { $0.path == newValue }) else { return }
                withAnimation(Glass.Motion.snappy) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func unstagedRow(_ file: FileStatus, isTreeRow: Bool) -> some View {
        // A row action or drag takes the whole selection when the row is part of it.
        let targets = discardTargets(for: file)
        let paths = targets.map(\.path)
        return ChangeRow(
            file: file,
            staged: false,
            isTreeRow: isTreeRow,
            store: store,
            onStage: { stageFiles([$0]) },
            onUnstage: { _ in },
            onDiscard: { requestDiscard(discardTargets(for: $0)) },
            discardCount: targets.count,
            moveMenu: AnyView(MoveToMenu(store: store, paths: paths, current: .unstaged))
        )
        .draggable(paths.joined(separator: PlanRowTag.dragSeparator))
        .dropDestination(for: String.self) { items, _ in
            dropOnUnstaged(items)
        }
    }

    /// Files dragged here from a commit leave it: staged ones are unstaged.
    private func dropOnUnstaged(_ items: [String]) -> Bool {
        let paths = items.flatMap { $0.components(separatedBy: PlanRowTag.dragSeparator) }.filter { !$0.isEmpty }
        let known = store.changedPathSet.union(store.commitPlan.claimedPaths)
        let accepted = paths.filter { known.contains($0) }
        guard !accepted.isEmpty else { return false }
        Task { await store.move(accepted, to: .unstaged) }
        return true
    }

    /// Drive the diff viewer from the selection. When a single FILE row is
    /// selected, load its diff. When 2+ rows or a folder is selected, leave the
    /// diff view on whatever was last shown (mirrors HistoryView's pattern).
    /// When selection is empty, clear the diff.
    private var unstagedSelection: Binding<Set<String>> {
        Binding(
            get: { multiSelection },
            set: { selection in
                // Clearing this list while you work in the stack must not clear the diff.
                guard !selection.isEmpty || !stackIsActive else { return }
                stackIsActive = false
                multiSelection = selection
                if selection.count == 1, let id = selection.first,
                   let file = unstagedEntries.first(where: { $0.path == id }) {
                    Task { await store.select(file, source: file.isUntracked ? .untracked : .unstaged) }
                } else if selection.isEmpty {
                    Task { await store.select(nil) }
                }
                // Otherwise (multi-select, or selection landed on a folder header),
                // leave store.selectedPath alone.
            }
        )
    }

    /// Highlights the selected file in the list that shows it and clears the
    /// other. A partly staged file is listed twice; the diff source decides.
    private func syncHighlight() {
        guard let path = store.selectedPath else {
            if !multiSelection.isEmpty {
                multiSelection.removeAll()
            }
            return
        }
        let inUnstaged = store.selectedDiffSource != .staged && unstagedEntries.contains { $0.path == path }
        if inUnstaged {
            if multiSelection != [path] {
                multiSelection = [path]
            }
            stackSelection = stackSelection.filter { PlanRowTag.path(of: $0) == nil }
        } else if !multiSelection.isEmpty {
            multiSelection.removeAll()
        }
    }

    /// Stable key for List animations: counts plus boundary paths. Bulk refreshes
    /// from the watcher won't trip the animation unless the visible boundary moves.
    private var stagingAnimationKey: String {
        let unstaged = unstagedEntries
        return "\(unstaged.count)|\(store.stagedEntries.count)|\(unstaged.first?.path ?? "")|\(unstaged.last?.path ?? "")"
    }

    private var summary: String {
        let changed = store.entries.count
        guard changed > 0 else { return store.commitPlan.isEmpty ? "Clean" : "No changes" }
        return changed == 1 ? "1 changed file" : "\(changed) changed files"
    }
}

/// Folder and file rows for `entries` in tree order, honoring folder expansion.
struct FileTreeRows<FileRow: View>: View {
    let store: RepositoryStore
    let entries: [FileStatus]
    let fileTag: (String) -> String
    let folderTag: (String) -> String
    @ViewBuilder let fileRow: (FileStatus) -> FileRow

    var body: some View {
        let flat = FileTreeBuilder.flatten(FileTreeBuilder.build(entries: entries), expanded: store.expandedFolders)
        ForEach(flat) { node in
            switch node.payload {
            case .folder(let name, _):
                FolderTreeRow(
                    name: name,
                    path: node.id,
                    depth: node.depth,
                    changedCount: node.changedCount,
                    isExpanded: store.expandedFolders.contains(node.id),
                    onToggle: { store.toggleFolderExpanded(node.id) }
                )
                // Tag folder rows so arrow-key navigation traverses them and
                // selection can cross folder boundaries naturally. Selection
                // handlers filter folder tags back out so the diff view is
                // never asked to render a folder path.
                .tag(folderTag(node.id))
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            case .file(let file):
                fileRow(file)
                    .tag(fileTag(file.path))
                    .id(file.path)
                    .padding(.leading, CGFloat(node.depth + 1) * 12)
            }
        }
    }
}

struct PaneHeader: View {
    let title: String
    let count: Int
    let actionLabel: String
    let actionTint: Color
    let actionEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
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
                Text(actionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .foregroundStyle(actionEnabled ? actionTint : .secondary)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.thinMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!actionEnabled)
            .opacity(actionEnabled ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
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

struct ChangeRow: View {
    let file: FileStatus
    let staged: Bool
    var isTreeRow = false
    let store: RepositoryStore
    let onStage: (FileStatus) -> Void
    let onUnstage: (FileStatus) -> Void
    let onDiscard: (FileStatus) -> Void
    /// How many files a discard from this row would touch, so the menu can say so.
    var discardCount: Int = 1
    /// "Move To" submenu for the stack: Commit 1, a planned commit, or Unstaged.
    var moveMenu: AnyView?

    var body: some View {
        HStack(spacing: 6) {
            Text(badge.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(badge.color)
                .frame(width: 12)
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(fullPathDescription)
                .accessibilityLabel(fullPathDescription)
            Spacer(minLength: 6)
            if staged {
                inlineAction("minus.circle", help: "Unstage") {
                    onUnstage(file)
                }
            } else {
                inlineAction("plus.circle", help: "Stage") {
                    onStage(file)
                }
                inlineAction("arrow.uturn.backward.circle", help: discardHelp) {
                    onDiscard(file)
                }
            }
        }
        .font(.system(size: 12))
        .padding(.vertical, 1)
        .contextMenu {
            fileContextMenu
        }
    }

    private var discardHelp: String {
        discardCount > 1 ? "Discard \(discardCount) files" : "Discard"
    }

    @ViewBuilder
    private var fileContextMenu: some View {
        if staged {
            Button("Unstage") {
                onUnstage(file)
            }
        } else {
            Button("Stage") {
                onStage(file)
            }
            Button(discardCount > 1 ? "Discard \(discardCount) Files…" : "Discard…", role: .destructive) {
                onDiscard(file)
            }
        }
        if let moveMenu {
            moveMenu
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
        guard isTreeRow else { return fullPathDescription }
        let name = URL(fileURLWithPath: file.path).lastPathComponent
        if let original = file.originalPath {
            let oldName = URL(fileURLWithPath: original).lastPathComponent
            if oldName != name {
                return "\(oldName) → \(name)"
            }
        }
        return name
    }

    private var fullPathDescription: String {
        if let originalPath = file.originalPath {
            return "\(originalPath) → \(file.path)"
        }
        return file.path
    }

    /// Git-style status letter for the file's change kind (M/A/D/R/C/T/U),
    /// rendered as text in the row instead of an SF Symbol glyph.
    private var badge: (letter: String, color: Color) {
        switch staged ? file.index : file.worktree {
        case .added, .untracked: ("A", .green)
        case .modified: ("M", .orange)
        case .typeChanged: ("T", .orange)
        case .deleted: ("D", .red)
        case .renamed: ("R", .blue)
        case .copied: ("C", .blue)
        case .updatedButUnmerged: ("U", .yellow)
        case .unmodified, .ignored: (".", .gray)
        }
    }
}

struct FolderTreeRow: View {
    let name: String
    let path: String
    let depth: Int
    let changedCount: Int
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
