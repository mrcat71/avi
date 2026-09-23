import AppKit
import GitKit
import SwiftUI

/// Switches the Changes workspace between the staged/unstaged file lists and
/// the commit plan. Shared by both toolbars so it never moves.
struct ChangesModeSwitch: View {
    let store: RepositoryStore

    var body: some View {
        HStack(spacing: 2) {
            segment("Files", isSelected: store.changesMode == .files, showsDot: false) {
                store.showFiles()
            }
            segment(planLabel, isSelected: store.changesMode == .plan, showsDot: store.hasUnseenProposal && store.changesMode != .plan) {
                store.showPlan()
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
        .fixedSize()
    }

    private var planLabel: String {
        store.commitPlan.isEmpty ? "Plan" : "Plan \(store.commitPlan.drafts.count)"
    }

    private func segment(_ title: String, isSelected: Bool, showsDot: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                if showsDot {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 20)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsDot ? "\(title), new proposal" : title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The commit plan: drafts grouped by who proposed them, then the changed
/// files no draft holds. Files move by drag and drop or the Move To menu.
/// Every row is an ordinary list row: pinned section headers on macOS float
/// over the first row and swallow clicks meant for it.
struct CommitPlanListView: View {
    let store: RepositoryStore

    @State private var selection: Set<String> = []
    @State private var pendingGroupDiscard: DraftSource?
    @State private var confirmingPlanDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
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
            Text("The files stay changed and move to Not in Plan.")
        }
        .confirmationDialog("Discard the whole plan?", isPresented: $confirmingPlanDiscard, titleVisibility: .visible) {
            Button("Discard Plan", role: .destructive) {
                store.discardPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Messages and groupings are lost. The files stay changed.")
        }
        .onChange(of: store.selectedPath) { _, path in
            // Keep the list highlight in step when the store picks a file.
            if let path, !selection.contains(PlanRowTag.file(path)) {
                selection = [PlanRowTag.file(path)]
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            ChangesModeSwitch(store: store)
            Spacer()
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Button {
                store.addDraft()
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
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
            .help("Plan actions")
            .accessibilityLabel("Plan actions")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var summary: String {
        let drafts = store.commitPlan.drafts.count
        let free = store.unassignedPaths.count
        let commits = drafts == 1 ? "1 commit" : "\(drafts) commits"
        return free == 0 ? commits : "\(commits) · \(free) not in plan"
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
        let numbers = Dictionary(uniqueKeysWithValues: store.commitPlan.drafts.enumerated().map { ($1.id, $0 + 1) })
        return List(selection: selectionBinding) {
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
                    draftRows(draft, number: numbers[draft.id] ?? 0)
                }
            }
            newDraftDropRow
                .selectionDisabled()
            Text("Not in plan (\(store.unassignedPaths.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .selectionDisabled()
                .listRowSeparator(.hidden)
                .dropDestination(for: String.self) { items, _ in
                    drop(items, on: .unassigned)
                }
            if store.unassignedPaths.isEmpty {
                Text("Every changed file is in a commit.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
            } else {
                ForEach(store.unassignedPaths, id: \.self) { path in
                    fileRow(path, owner: nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .disabled(store.isApplyingPlan)
        .onDeleteCommand {
            let paths = selectedPaths
            guard !paths.isEmpty else { return }
            store.moveFiles(paths, to: .unassigned)
        }
    }

    @ViewBuilder
    private func draftRows(_ draft: CommitDraft, number: Int) -> some View {
        DraftHeaderRow(
            store: store,
            draft: draft,
            number: number,
            issues: store.issues(of: draft),
            isSelected: store.selectedDraftID == draft.id,
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
            fileRow(path, owner: draft)
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

    private func fileRow(_ path: String, owner: CommitDraft?) -> some View {
        let entry = store.entry(forPlanPath: path)
        return PlanFileRow(
            path: path,
            entry: entry,
            isChanged: store.changedPathSet.contains(path)
        )
        .tag(PlanRowTag.file(path))
        .padding(.leading, owner == nil ? 0 : 24)
        .draggable(dragPayload(for: path))
        .dropDestination(for: String.self) { items, _ in
            drop(items, on: owner.map { .draft($0.id) } ?? .unassigned)
        }
        .contextMenu {
            fileMenu(path, entry: entry, owner: owner)
        }
    }

    @ViewBuilder
    private func fileMenu(_ path: String, entry: FileStatus?, owner: CommitDraft?) -> some View {
        let targets = moveTargets(for: path)
        Menu(targets.count > 1 ? "Move \(targets.count) Files To" : "Move To") {
            ForEach(Array(store.commitPlan.drafts.enumerated()), id: \.element.id) { index, draft in
                Button("\(index + 1). \(draft.subject.isEmpty ? "Untitled" : draft.subject)") {
                    store.moveFiles(targets, to: .draft(draft.id))
                }
                .disabled(draft.id == owner?.id && targets == [path])
            }
            Divider()
            Button("New Commit") {
                store.moveFiles(targets, to: .newDraft)
            }
            Button("Not in Plan") {
                store.moveFiles(targets, to: .unassigned)
            }
            .disabled(owner == nil && targets == [path])
        }
        if let owner {
            Divider()
            Menu("Commit \(store.commitPlan.drafts.firstIndex { $0.id == owner.id }.map { "\($0 + 1)" } ?? "")") {
                DraftActionsMenu(store: store, draftID: owner.id)
            }
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

    // MARK: Selection and drag

    /// Files a move from `path`'s row applies to: the whole selection when the
    /// row is part of it, otherwise that row alone.
    private func moveTargets(for path: String) -> [String] {
        let chosen = selectedPaths
        return chosen.contains(path) ? chosen : [path]
    }

    private var selectedPaths: [String] {
        let chosen = Set(selection.compactMap(PlanRowTag.path(of:)))
        let ordered = store.commitPlan.drafts.flatMap(\.files) + store.unassignedPaths
        return ordered.filter { chosen.contains($0) }
    }

    /// Dragging a selected row carries the whole selection.
    private func dragPayload(for path: String) -> String {
        moveTargets(for: path).joined(separator: PlanRowTag.dragSeparator)
    }

    private func drop(_ items: [String], on target: DraftMoveTarget) -> Bool {
        let paths = items.flatMap { $0.components(separatedBy: PlanRowTag.dragSeparator) }.filter { !$0.isEmpty }
        let known = store.changedPathSet.union(store.commitPlan.claimedPaths)
        let accepted = paths.filter { known.contains($0) }
        guard !accepted.isEmpty else { return false }
        store.moveFiles(accepted, to: target)
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
                guard newValue.count == 1, let tag = newValue.first else { return }
                if let path = PlanRowTag.path(of: tag) {
                    if let owner = store.commitPlan.owner(of: path) {
                        store.selectDraft(owner.id)
                    }
                    Task { await store.selectPlanFile(path) }
                } else if let id = PlanRowTag.draftID(of: tag) {
                    store.selectDraft(id)
                    if let first = store.commitPlan.draft(id: id)?.files.first {
                        Task { await store.selectPlanFile(first) }
                    }
                }
            }
        )
    }

    private var discardPrompt: String {
        guard let source = pendingGroupDiscard else { return "" }
        let count = store.commitPlan.drafts(from: source).count
        return "Discard \(count == 1 ? "the commit" : "\(count) commits") from \(source.displayName)?"
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

/// Actions on the plan as a whole.
struct PlanActionsMenu: View {
    let store: RepositoryStore
    let confirmDiscard: () -> Void

    var body: some View {
        let drafts = store.commitPlan.drafts
        let aiReady = store.canUseAIForPlan && !store.isRevisingPlan && !store.isApplyingPlan
        Button(drafts.count == 1 ? "Commit" : "Commit All (\(drafts.count))") {
            Task { await store.commitAllDrafts() }
        }
        .disabled(!store.canCommitAllDrafts)
        Button("New Commit") {
            store.addDraft()
        }
        .disabled(store.isApplyingPlan)
        Divider()
        Button("Rethink Plan with AI…") {
            store.requestRevision(of: drafts.map(\.id))
        }
        .disabled(!aiReady || drafts.isEmpty)
        if !store.canUseAIForPlan {
            Text("Turn on AI in Settings > AI Commit Messages")
        }
        Divider()
        Button("Discard Plan…", role: .destructive) {
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
private struct PlanGroupHeaderRow: View {
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

/// List tags for plan rows. Files and drafts share one selection set.
enum PlanRowTag {
    static let dragSeparator = "\u{1F}"

    static func file(_ path: String) -> String {
        "f:" + path
    }

    static func draft(_ id: UUID) -> String {
        "d:" + id.uuidString
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

private struct DraftHeaderRow: View {
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

private struct PlanFileRow: View {
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
