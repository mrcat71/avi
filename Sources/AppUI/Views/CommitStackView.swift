import AppKit
import GitKit
import SwiftUI

/// The commits you are about to make, in order. Commit 1 is the staged files,
/// the index; planned commits follow, grouped by who proposed them. Files move
/// by drag and drop or Move To: into Commit 1 stages them, out of it unstages
/// them, and planned commits leave the index alone.
/// Every row is an ordinary list row: pinned section headers on macOS float
/// over the first row and swallow clicks meant for it.
struct CommitStackView: View {
    let store: RepositoryStore
    @Binding var selection: Set<String>
    /// Called when you use this list, so Cmd+A knows where to act.
    let onActivate: () -> Void

    @Bindable private var config = ConfigStore.shared
    @State private var pendingGroupDiscard: DraftSource?
    @State private var confirmingPlanDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isRevisingPlan {
                revisingBanner
                Divider()
            }
            if let notice = store.planNotice {
                noticeBanner(notice)
                Divider()
            }
            list
        }
        .confirmationDialog(
            discardPrompt,
            isPresented: Binding(get: { pendingGroupDiscard != nil }, set: {
                if !$0 {
                    pendingGroupDiscard = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                if let source = pendingGroupDiscard {
                    store.discardDrafts(from: source)
                }
                pendingGroupDiscard = nil
            }
            Button("Cancel", role: .cancel) {
                pendingGroupDiscard = nil
            }
        } message: {
            Text("The files stay changed and go back to Commit 1 or Unstaged.")
        }
        .confirmationDialog("Discard every planned commit?", isPresented: $confirmingPlanDiscard, titleVisibility: .visible) {
            Button("Discard Plan", role: .destructive) {
                store.discardPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Messages and groupings are lost. The files stay changed.")
        }
        .onChange(of: store.selectedPath) { _, _ in
            syncHighlight()
        }
        .onChange(of: store.selectedDiffSource) { _, _ in
            syncHighlight()
        }
    }

    private var isTreeMode: Bool {
        config.config.appearance.fileListMode == "tree"
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Commits")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text("\(store.stackCount)")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .frame(minHeight: 14)
                .background(Capsule().fill(Color.primary.opacity(0.10)))
                .foregroundStyle(.secondary)
                .accessibilityLabel(store.stackCount == 1 ? "1 commit" : "\(store.stackCount) commits")
            Spacer()
            if store.showsStagedCommit {
                unstageButton
            }
            Button {
                store.addDraft()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isApplyingPlan)
            .help("New commit")
            .accessibilityLabel("New commit")
            Menu {
                PlanActionsMenu(store: store, confirmDiscard: { confirmingPlanDiscard = true })
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Commit actions")
            .accessibilityLabel("Commit actions")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var unstageButton: some View {
        Button {
            unstage(selectedStagedFiles)
        } label: {
            Text("Unstage")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .foregroundStyle(selectedStagedFiles.isEmpty ? Color.secondary : Color.primary)
                .background(Capsule(style: .continuous).fill(.thinMaterial))
                .overlay(Capsule(style: .continuous).strokeBorder(Glass.edgeStroke, lineWidth: 0.6))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedStagedFiles.isEmpty)
        .opacity(selectedStagedFiles.isEmpty ? 0.5 : 1)
        .help("Unstage the selected files of Commit 1")
    }

    private var revisingBanner: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(store.revisingDraftIDs.count == 1 ? "The AI is working on 1 commit…" : "The AI is working on \(store.revisingDraftIDs.count) commits…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Cancel") {
                store.cancelPlanAI()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.06))
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(notice)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                store.planNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: List

    private var list: some View {
        let groups = store.commitPlan.groups
        return List(selection: selectionBinding) {
            if store.showsStagedCommit {
                StagedCommitHeaderRow(store: store, isSelected: store.composerDraft == nil, onSplit: requestStagedSplit)
                    .tag(PlanRowTag.stagedCommit)
                    .contextMenu {
                        StagedCommitMenu(store: store, onSplit: requestStagedSplit)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        drop(items, on: .staged)
                    }
                stagedRows
            }
            ForEach(groups) { group in
                PlanGroupHeaderRow(
                    store: store,
                    source: group.source,
                    drafts: group.drafts,
                    isOnlyGroup: groups.count == 1,
                    onDiscard: { pendingGroupDiscard = group.source }
                )
                .selectionDisabled()
                .listRowSeparator(.hidden)
                ForEach(group.drafts) { draft in
                    draftRows(draft)
                }
            }
            newDraftDropRow
                .selectionDisabled()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .disabled(store.isApplyingPlan)
        .onDeleteCommand {
            let paths = selectedPaths
            guard !paths.isEmpty else { return }
            Task { await store.move(paths, to: .unstaged) }
        }
    }

    @ViewBuilder
    private var stagedRows: some View {
        let entries = store.stagedCommitEntries
        if entries.isEmpty {
            Text(store.commitPlan.isEmpty ? "Nothing staged. Stage files, or drag them here." : "Drag files here to stage them")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, 24)
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .dropDestination(for: String.self) { items, _ in
                    drop(items, on: .staged)
                }
        } else if isTreeMode {
            FileTreeRows(store: store, entries: entries, fileTag: PlanRowTag.file, folderTag: PlanRowTag.folder) { file in
                stagedRow(file, isTreeRow: true)
            }
        } else {
            ForEach(entries) { file in
                stagedRow(file, isTreeRow: false)
                    .padding(.leading, 24)
                    .tag(PlanRowTag.file(file.path))
                    .id(file.path)
            }
        }
    }

    private func stagedRow(_ file: FileStatus, isTreeRow: Bool) -> some View {
        let targets = moveTargets(for: file.path)
        return ChangeRow(
            file: file,
            staged: true,
            isTreeRow: isTreeRow,
            store: store,
            onStage: { _ in },
            onUnstage: { unstage([$0]) },
            onDiscard: { _ in },
            moveMenu: AnyView(MoveToMenu(store: store, paths: targets, current: .staged))
        )
        .draggable(targets.joined(separator: PlanRowTag.dragSeparator))
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: .staged)
        }
    }

    @ViewBuilder
    private func draftRows(_ draft: CommitDraft) -> some View {
        let number = store.stackNumber(ofDraft: draft.id) ?? 0
        DraftHeaderRow(
            store: store,
            draft: draft,
            number: number,
            issues: store.issues(of: draft),
            isSelected: store.composerDraft?.id == draft.id,
            isRevising: store.revisingDraftIDs.contains(draft.id)
        )
        .tag(PlanRowTag.draft(draft.id))
        .contextMenu {
            DraftActionsMenu(store: store, draftID: draft.id)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: .draft(draft.id))
        }
        if draft.files.isEmpty {
            Text("Drag files here")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, 24)
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .dropDestination(for: String.self) { items, _ in
                    drop(items, on: .draft(draft.id))
                }
        }
        ForEach(displayedFiles(of: draft), id: \.self) { path in
            draftFileRow(path, owner: draft, number: number)
        }
    }

    private var newDraftDropRow: some View {
        Button {
            store.addDraft()
        } label: {
            Label("New commit", systemImage: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add an empty commit, or drop files here to start one")
        .listRowSeparator(.hidden)
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: .newDraft)
        }
    }

    private func draftFileRow(_ path: String, owner: CommitDraft, number: Int) -> some View {
        let entry = store.entry(forPlanPath: path)
        let targets = moveTargets(for: path)
        return PlanFileRow(
            path: path,
            entry: entry,
            isChanged: store.changedPathSet.contains(path)
        )
        .tag(PlanRowTag.file(path))
        .padding(.leading, 24)
        .draggable(targets.joined(separator: PlanRowTag.dragSeparator))
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: .draft(owner.id))
        }
        .contextMenu {
            MoveToMenu(store: store, paths: targets, current: .draft(owner.id))
            Divider()
            Menu("Commit \(number)") {
                DraftActionsMenu(store: store, draftID: owner.id)
            }
            if let entry {
                Divider()
                Button("Open File") {
                    store.openFile(entry)
                }
                Button("Reveal in Finder") {
                    store.revealInFinder(entry)
                }
                Menu("Copy Path") {
                    Button("Relative") {
                        store.copyRelativePath(entry)
                    }
                    Button("Absolute") {
                        store.copyAbsolutePath(entry)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func requestStagedSplit() {
        let paths = store.stagedCommitEntries.map(\.path)
        store.requestSplit(of: paths, title: "Commit 1: \(paths.count) staged files")
    }

    /// Unstages `files` and moves the selection to the next file of Commit 1.
    private func unstage(_ files: [FileStatus]) {
        guard !files.isEmpty else { return }
        let order = FileTreeBuilder.visiblePaths(store.stagedCommitEntries, expanded: store.expandedFolders, tree: isTreeMode)
        Task { await store.unstage(files, advancingFrom: order) }
    }

    private var selectedStagedFiles: [FileStatus] {
        let chosen = Set(selection.compactMap(PlanRowTag.path(of:)))
        return store.stagedCommitEntries.filter { chosen.contains($0.path) }
    }

    // MARK: Selection and drag

    /// Files a move from `path`'s row applies to: the whole selection when the
    /// row is part of it, otherwise that row alone.
    private func moveTargets(for path: String) -> [String] {
        let chosen = selectedPaths
        return chosen.contains(path) ? chosen : [path]
    }

    private var selectedPaths: [String] {
        let chosen = Set(selection.compactMap(PlanRowTag.path(of:)))
        let ordered = store.stagedCommitEntries.map(\.path) + store.commitPlan.drafts.flatMap(\.files)
        return ordered.filter { chosen.contains($0) }
    }

    private func drop(_ items: [String], on destination: ChangeDestination) -> Bool {
        let paths = items.flatMap { $0.components(separatedBy: PlanRowTag.dragSeparator) }.filter { !$0.isEmpty }
        let known = store.changedPathSet.union(store.commitPlan.claimedPaths)
        let accepted = paths.filter { known.contains($0) }
        guard !accepted.isEmpty else { return false }
        Task { await store.move(accepted, to: destination) }
        return true
    }

    /// A staged rename is committed as a pair; show it once, under its new name.
    private func displayedFiles(of draft: CommitDraft) -> [String] {
        let files = Set(draft.files)
        return draft.files.filter { path in
            guard let rename = store.entries.first(where: { $0.index == .renamed && $0.originalPath == path }) else { return true }
            return !files.contains(rename.path)
        }
    }

    private var selectionBinding: Binding<Set<String>> {
        Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                onActivate()
                guard newValue.count == 1, let tag = newValue.first else { return }
                if tag == PlanRowTag.stagedCommit {
                    store.selectStagedCommit()
                    if let first = store.stagedCommitEntries.first {
                        Task { await store.select(first, source: .staged) }
                    }
                } else if let path = PlanRowTag.path(of: tag) {
                    if let owner = store.commitPlan.owner(of: path) {
                        store.selectDraft(owner.id)
                        Task { await store.selectPlanFile(path) }
                    } else if let file = store.stagedCommitEntries.first(where: { $0.path == path }) {
                        store.selectStagedCommit()
                        Task { await store.select(file, source: .staged) }
                    }
                } else if let id = PlanRowTag.draftID(of: tag) {
                    store.selectDraft(id)
                    if let first = store.commitPlan.draft(id: id)?.files.first {
                        Task { await store.selectPlanFile(first) }
                    }
                }
            }
        )
    }

    /// Keeps the list highlight in step when the store picks a file, and drops
    /// file highlights once the selection moves to Unstaged.
    private func syncHighlight() {
        guard let path = store.selectedPath else { return }
        let inStack = store.commitPlan.owner(of: path) != nil
            || (store.selectedDiffSource == .staged && store.stagedCommitEntries.contains { $0.path == path })
        if inStack {
            let tag = PlanRowTag.file(path)
            if !selection.contains(tag) {
                selection = [tag]
            }
        } else if selection.contains(where: { PlanRowTag.path(of: $0) != nil }) {
            selection = selection.filter { PlanRowTag.path(of: $0) == nil }
        }
    }

    private var discardPrompt: String {
        guard let source = pendingGroupDiscard else { return "" }
        let count = store.commitPlan.drafts(from: source).count
        return "Discard \(count == 1 ? "the commit" : "\(count) commits") from \(source.displayName)?"
    }
}

/// "Move To" for files anywhere in Changes: Commit 1, a planned commit, a new
/// one, or Unstaged. Moving into Commit 1 stages; moving to Unstaged unstages.
struct MoveToMenu: View {
    let store: RepositoryStore
    let paths: [String]
    /// Where the files are now; that entry is disabled.
    let current: ChangeDestination

    var body: some View {
        Menu(paths.count > 1 ? "Move \(paths.count) Files To" : "Move To") {
            Button("Staged (Commit 1)") {
                move(.staged)
            }
            .disabled(current == .staged)
            ForEach(store.commitPlan.drafts) { draft in
                Button("\(store.stackNumber(ofDraft: draft.id) ?? 0). \(draft.subject.isEmpty ? "Untitled" : draft.subject)") {
                    move(.draft(draft.id))
                }
                .disabled(current == .draft(draft.id) && paths.allSatisfy(draft.files.contains))
            }
            Divider()
            Button("New Commit") {
                move(.newDraft)
            }
            Button("Unstaged") {
                move(.unstaged)
            }
            .disabled(current == .unstaged)
        }
    }

    private func move(_ destination: ChangeDestination) {
        Task { await store.move(paths, to: destination) }
    }
}

/// Commit 1's heading: the staged files, and what you can do with them.
private struct StagedCommitHeaderRow: View {
    let store: RepositoryStore
    let isSelected: Bool
    let onSplit: () -> Void

    var body: some View {
        let count = store.stagedCommitEntries.count
        HStack(spacing: 6) {
            Text("1")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 16)
                .background(Capsule().fill(Color.accentColor.opacity(isSelected ? 0.30 : 0.16)))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Commit 1")
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.commitSummary.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(store.amend ? "Staged · amends the last commit" : "Staged")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .frame(minHeight: 14)
                .background(Capsule().fill(Color.primary.opacity(0.10)))
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("\(count) staged file\(count == 1 ? "" : "s")")
            Button(action: onSplit) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canUseAIForPlan || count < 2 || store.isRevisingPlan || store.isApplyingPlan)
            .help(store.canUseAIForPlan ? "Split Commit 1 into several commits with AI" : "Turn on AI in Settings > AI Commit Messages")
            .accessibilityLabel("Split Commit 1 with AI")
            Menu {
                StagedCommitMenu(store: store, onSplit: onSplit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Commit 1 actions")
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        let summary = store.commitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? "Staged changes" : summary
    }
}

/// Everything you can do with Commit 1, on right-click and behind its "..." button.
private struct StagedCommitMenu: View {
    let store: RepositoryStore
    let onSplit: () -> Void

    var body: some View {
        let count = store.stagedCommitEntries.count
        let aiReady = store.canUseAIForPlan && !store.isRevisingPlan && !store.isApplyingPlan
        if store.stackCount > 1 {
            Button("Commit Only This") {
                Task { await store.commit() }
            }
            .disabled(!store.canCommit || store.isLoading)
            Divider()
        }
        Button("Write Message with AI") {
            store.generateCommitMessage(config: ConfigStore.shared.config.ai)
        }
        .disabled(!aiReady || count == 0 || store.isGeneratingCommitMessage)
        Button("Split with AI…", action: onSplit)
            .disabled(!aiReady || count < 2)
        if !store.canUseAIForPlan {
            Text("Turn on AI in Settings > AI Commit Messages")
        }
        Divider()
        Button("Unstage All") {
            Task { await store.move(store.stagedCommitEntries.map(\.path), to: .unstaged) }
        }
        .disabled(count == 0)
    }
}

/// Everything you can do with one draft. The same items appear on right-click,
/// behind the row's "..." button, and in the composer, so each is always one
/// menu away.
struct DraftActionsMenu: View {
    let store: RepositoryStore
    let draftID: UUID

    var body: some View {
        let drafts = store.commitPlan.drafts
        let index = drafts.firstIndex { $0.id == draftID } ?? 0
        let draft = drafts.first { $0.id == draftID }
        let isLast = index == drafts.count - 1
        let ready = draft.map { store.issues(of: $0).isEmpty } ?? false
        let aiReady = store.canUseAIForPlan && !store.isRevisingPlan && !store.isApplyingPlan

        Button("Commit This Now") {
            Task { await store.commitDraft(draftID) }
        }
        .disabled(!ready || store.isApplyingPlan)
        Divider()
        Button("Write Message with AI") {
            store.improveMessage(forDraft: draftID)
        }
        .disabled(!aiReady || (draft?.files.isEmpty ?? true))
        Button("Revise with AI…") {
            store.requestRevision(of: [draftID])
        }
        .disabled(!aiReady)
        Button("Split with AI…") {
            store.requestRevision(of: [draftID], suggestion: "Split this commit into smaller commits, one per logical change.")
        }
        .disabled(!aiReady || (draft?.files.count ?? 0) < 2)
        if !store.canUseAIForPlan {
            Text("Turn on AI in Settings > AI Commit Messages")
        }
        Divider()
        Button("Move Up") {
            store.moveDraft(draftID, by: -1)
        }
        .disabled(index == 0)
        Button("Move Down") {
            store.moveDraft(draftID, by: 1)
        }
        .disabled(isLast)
        Button("Merge with Previous") {
            store.mergeDraft(draftID, withNext: false)
        }
        .disabled(index == 0)
        Button("Merge with Next") {
            store.mergeDraft(draftID, withNext: true)
        }
        .disabled(isLast)
        Divider()
        Button("Delete Commit", role: .destructive) {
            store.deleteDraft(draftID)
        }
    }
}

/// Actions on the whole stack of commits.
struct PlanActionsMenu: View {
    let store: RepositoryStore
    let confirmDiscard: () -> Void

    var body: some View {
        let drafts = store.commitPlan.drafts
        let aiReady = store.canUseAIForPlan && !store.isRevisingPlan && !store.isApplyingPlan
        let splittable = store.splittablePaths
        Button(store.stackCount > 1 ? "Commit All (\(store.stackCount))" : "Commit") {
            Task { await store.commitStack() }
        }
        .disabled(!store.canCommitStack)
        Button("New Commit") {
            store.addDraft()
        }
        .disabled(store.isApplyingPlan)
        Divider()
        Button("Split into Commits with AI…") {
            store.requestSplit(of: splittable, title: splittable.count == 1 ? "1 changed file" : "\(splittable.count) changed files")
        }
        .disabled(!aiReady || splittable.count < 2)
        Button("Rethink Planned Commits with AI…") {
            store.requestRevision(of: drafts.map(\.id))
        }
        .disabled(!aiReady || drafts.isEmpty)
        if !store.canUseAIForPlan {
            Text("Turn on AI in Settings > AI Commit Messages")
        }
        Divider()
        Button("Discard Planned Commits…", role: .destructive) {
            if store.commitPlan.isEdited {
                confirmDiscard()
            } else {
                store.discardPlan()
            }
        }
        .disabled(drafts.isEmpty || store.isApplyingPlan)
    }
}

/// One source's run of drafts: who proposed them and what to do with them together.
struct PlanGroupHeaderRow: View {
    let store: RepositoryStore
    let source: DraftSource
    let drafts: [CommitDraft]
    let isOnlyGroup: Bool
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: source.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(source.groupTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if !isOnlyGroup {
                Button("Commit These") {
                    Task { await store.commitDrafts(from: source) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .disabled(!isReady)
                .help("Commit only the \(drafts.count) commit\(drafts.count == 1 ? "" : "s") from \(source.displayName)")
            }
            Menu {
                groupMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Actions for the commits from \(source.displayName)")
        }
        .padding(.top, 6)
        .contextMenu {
            groupMenu
        }
    }

    @ViewBuilder
    private var groupMenu: some View {
        Button("Commit These") {
            Task { await store.commitDrafts(from: source) }
        }
        .disabled(!isReady)
        Button("Revise These with AI…") {
            store.requestRevision(of: drafts.map(\.id))
        }
        .disabled(!store.canUseAIForPlan || store.isRevisingPlan || store.isApplyingPlan)
        Divider()
        Button("Discard These…", role: .destructive, action: onDiscard)
            .disabled(store.isApplyingPlan)
    }

    private var isReady: Bool {
        !store.isApplyingPlan && drafts.allSatisfy { store.issues(of: $0).isEmpty }
    }
}

/// List tags for commit stack rows. Files, commits, and folders share one selection set.
enum PlanRowTag {
    static let dragSeparator = "\u{1F}"

    static func file(_ path: String) -> String {
        "f:" + path
    }

    static func draft(_ id: UUID) -> String {
        "d:" + id.uuidString
    }

    /// Commit 1, the staged files.
    static let stagedCommit = "s:staged"

    static func folder(_ id: String) -> String {
        "dir:" + id
    }

    static func path(of tag: String) -> String? {
        tag.hasPrefix("f:") ? String(tag.dropFirst(2)) : nil
    }

    static func draftID(of tag: String) -> UUID? {
        tag.hasPrefix("d:") ? UUID(uuidString: String(tag.dropFirst(2))) : nil
    }
}

extension DraftSource {
    var symbolName: String {
        switch self {
        case .agent: return "terminal"
        case .ai: return "character.bubble"
        case .manual: return "person"
        }
    }
}

struct DraftHeaderRow: View {
    let store: RepositoryStore
    let draft: CommitDraft
    let number: Int
    let issues: [DraftIssue]
    let isSelected: Bool
    let isRevising: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 16)
                .background(Capsule().fill(Color.accentColor.opacity(isSelected ? 0.30 : 0.16)))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Commit \(number)")
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.subject.isEmpty ? "Needs message" : draft.subject)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(draft.subject.isEmpty ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let problem {
                    Text(problem)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if isRevising {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("The AI is working on this commit")
            } else {
                Text("\(draft.files.count)")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .frame(minHeight: 14)
                    .background(Capsule().fill(Color.primary.opacity(0.10)))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .help("\(draft.files.count) file\(draft.files.count == 1 ? "" : "s")")
                    .accessibilityLabel("\(draft.files.count) file\(draft.files.count == 1 ? "" : "s")")
            }
            Menu {
                DraftActionsMenu(store: store, draftID: draft.id)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Commit \(number) actions")
        }
        .padding(.vertical, 2)
    }

    private var problem: String? {
        for issue in issues {
            switch issue {
            case .emptyMessage:
                continue
            case .noFiles:
                return "No files"
            case .unchanged(let paths):
                return paths.count == 1 ? "1 file no longer changed" : "\(paths.count) files no longer changed"
            }
        }
        return nil
    }
}

struct PlanFileRow: View {
    let path: String
    let entry: FileStatus?
    let isChanged: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(badge.letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(badge.color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 12))
                .strikethrough(!isChanged)
                .foregroundStyle(isChanged ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(help)
            Spacer(minLength: 4)
            if let entry, entry.isStaged, entry.hasUnstagedChanges {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Partly staged. The commit takes the whole working-tree version.")
                    .accessibilityLabel("Partly staged")
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(help)
    }

    private var label: String {
        if let entry, entry.index == .renamed, let original = entry.originalPath, entry.path == path {
            return "\(original) → \(path)"
        }
        return path
    }

    private var help: String {
        isChanged ? label : "\(label): no longer changed"
    }

    private var badge: (letter: String, color: Color) {
        guard let entry, isChanged else { return ("·", .gray) }
        if entry.isUntracked || entry.index == .added {
            return ("A", .green)
        }
        if entry.index == .renamed {
            return ("R", .blue)
        }
        if entry.index == .deleted || entry.worktree == .deleted {
            return ("D", .red)
        }
        if entry.index == .typeChanged || entry.worktree == .typeChanged {
            return ("T", .orange)
        }
        return ("M", .orange)
    }
}
