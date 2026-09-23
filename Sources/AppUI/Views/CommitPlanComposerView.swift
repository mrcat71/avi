import SwiftUI

/// Bottom-right pane in Plan mode: edit the selected draft's message, step
/// through drafts, and commit the whole plan.
struct CommitPlanComposerView: View {
    let store: RepositoryStore

    @State private var confirmingDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                header
                if let draft = store.selectedDraft {
                    CommitMessageEditor(summary: summaryBinding(draft.id), messageBody: bodyBinding(draft.id))
                    issueLine(for: draft)
                    actionBar(for: draft)
                } else {
                    Text("Add a commit with the + button, then drag files onto it.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .disabled(store.isApplyingPlan || store.selectedDraft.map { store.revisingDraftIDs.contains($0.id) } == true)
        .confirmationDialog("Discard the whole plan?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Plan", role: .destructive) {
                store.discardPlan()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Messages and groupings are lost. The files stay changed.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(position)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            if let draft = store.selectedDraft {
                Text("from \(draft.source.displayName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let draft = store.selectedDraft {
                Menu {
                    DraftActionsMenu(store: store, draftID: draft.id)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Actions for this commit")
                .accessibilityLabel("Actions for this commit")
            }
            stepButton("chevron.left", label: "Previous commit", offset: -1)
            stepButton("chevron.right", label: "Next commit", offset: 1)
        }
    }

    private var position: String {
        guard let draft = store.selectedDraft,
              let index = store.commitPlan.drafts.firstIndex(where: { $0.id == draft.id })
        else { return "Plan" }
        return "Commit \(index + 1) of \(store.commitPlan.drafts.count)"
    }

    private func stepButton(_ symbol: String, label: String, offset: Int) -> some View {
        let target = neighbour(offset)
        return Button {
            if let target {
                store.selectDraft(target)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .help(label)
        .accessibilityLabel(label)
    }

    private func neighbour(_ offset: Int) -> UUID? {
        let drafts = store.commitPlan.drafts
        guard let current = store.selectedDraft, let index = drafts.firstIndex(where: { $0.id == current.id }) else { return nil }
        let target = index + offset
        return drafts.indices.contains(target) ? drafts[target].id : nil
    }

    // MARK: Actions

    /// The draft menu's main actions as visible buttons, so they need no hunting.
    /// Falls back to icons when the pane is narrow.
    private func actionBar(for draft: CommitDraft) -> some View {
        ViewThatFits(in: .horizontal) {
            actionRow(for: draft, compact: false)
            actionRow(for: draft, compact: true)
        }
    }

    private func actionRow(for draft: CommitDraft, compact: Bool) -> some View {
        let drafts = store.commitPlan.drafts
        let index = drafts.firstIndex { $0.id == draft.id } ?? 0
        let isLast = index == drafts.count - 1
        let aiReady = store.canUseAIForPlan && !store.isRevisingPlan && !store.isApplyingPlan
        let aiHelp = store.canUseAIForPlan ? nil : "Turn on AI in Settings > AI Commit Messages"
        return HStack(spacing: 6) {
            actionButton("Write Message", symbol: "character.bubble", compact: compact, help: aiHelp ?? "Let the AI write this commit's message from its changes") {
                store.improveMessage(forDraft: draft.id)
            }
            .disabled(!aiReady || draft.files.isEmpty)
            actionButton("Revise…", symbol: "square.and.pencil", compact: compact, help: aiHelp ?? "Tell the AI how to change this commit") {
                store.requestRevision(of: [draft.id])
            }
            .disabled(!aiReady)
            actionButton("Split…", symbol: "square.split.2x1", compact: compact, help: aiHelp ?? "Have the AI split this commit into smaller ones") {
                store.requestRevision(of: [draft.id], suggestion: "Split this commit into smaller commits, one per logical change.")
            }
            .disabled(!aiReady || draft.files.count < 2)
            Menu {
                Button("Move Up") {
                    store.moveDraft(draft.id, by: -1)
                }
                .disabled(index == 0)
                Button("Move Down") {
                    store.moveDraft(draft.id, by: 1)
                }
                .disabled(isLast)
                Divider()
                Button("Merge with Previous") {
                    store.mergeDraft(draft.id, withNext: false)
                }
                .disabled(index == 0)
                Button("Merge with Next") {
                    store.mergeDraft(draft.id, withNext: true)
                }
                .disabled(isLast)
                Divider()
                Button("Delete Commit", role: .destructive) {
                    store.deleteDraft(draft.id)
                }
            } label: {
                if compact {
                    Image(systemName: "arrow.up.arrow.down")
                } else {
                    Label("Arrange", systemImage: "arrow.up.arrow.down")
                }
            }
            .controlSize(.small)
            .fixedSize()
            .help("Move, merge, or delete this commit")
            .accessibilityLabel("Arrange")
            Spacer(minLength: 8)
            actionButton("Rethink Plan…", symbol: "rectangle.3.group", compact: compact, help: aiHelp ?? "Tell the AI how to regroup every commit") {
                store.requestRevision(of: drafts.map(\.id))
            }
            .disabled(!aiReady || drafts.count < 2)
        }
        .disabled(store.isApplyingPlan)
    }

    private func actionButton(_ title: String, symbol: String, compact: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if compact {
                Image(systemName: symbol)
            } else {
                Label(title, systemImage: symbol)
            }
        }
        .controlSize(.small)
        .fixedSize()
        .help(help)
        .accessibilityLabel(title)
    }

    // MARK: Draft problems

    @ViewBuilder
    private func issueLine(for draft: CommitDraft) -> some View {
        let issues = store.issues(of: draft)
        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(describe(issue))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Spacer()
                switch issue {
                case .unchanged(let paths):
                    Button("Remove Them") {
                        store.moveFiles(paths, to: .unassigned)
                    }
                    .controlSize(.small)
                case .noFiles:
                    Button("Delete Commit") {
                        store.deleteDraft(draft.id)
                    }
                    .controlSize(.small)
                case .emptyMessage:
                    EmptyView()
                }
            }
        }
    }

    private func describe(_ issue: DraftIssue) -> String {
        switch issue {
        case .emptyMessage:
            return "Needs a message."
        case .noFiles:
            return "No files. Drag files onto it, or delete it."
        case .unchanged(let paths):
            let names = paths.prefix(3).joined(separator: ", ")
            return paths.count > 3 ? "No longer changed: \(names) and \(paths.count - 3) more" : "No longer changed: \(names)"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Discard Plan", role: .destructive) {
                if store.commitPlan.isEdited {
                    confirmingDiscard = true
                } else {
                    store.discardPlan()
                }
            }
            .controlSize(.small)
            .disabled(store.commitPlan.isEmpty)

            Spacer()

            if let progress = store.planProgress {
                ProgressView()
                    .controlSize(.small)
                Text("Committing \(min(progress.completed + 1, progress.total)) of \(progress.total)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let blocker {
                Text(blocker)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            if store.commitPlan.drafts.count > 1, let draft = store.selectedDraft {
                Button("Commit This") {
                    Task { await store.commitDraft(draft.id) }
                }
                .controlSize(.small)
                .disabled(!store.issues(of: draft).isEmpty || store.isApplyingPlan || store.isLoading)
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .help("Commit only this one and move to the next (Option+Cmd+Return)")
            }

            Button {
                Task { await store.commitAllDrafts() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(commitAllTitle)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!store.canCommitAllDrafts || store.isLoading)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Create every commit in order (Cmd+Return)")
        }
    }

    private var commitAllTitle: String {
        let count = store.commitPlan.drafts.count
        return count == 1 ? "Commit" : "Commit All (\(count))"
    }

    /// The first thing stopping Commit All, named by commit number.
    private var blocker: String? {
        for (index, draft) in store.commitPlan.drafts.enumerated() {
            if let issue = store.issues(of: draft).first {
                switch issue {
                case .emptyMessage: return "Commit \(index + 1) needs a message"
                case .noFiles: return "Commit \(index + 1) has no files"
                case .unchanged: return "Commit \(index + 1) has unchanged files"
                }
            }
        }
        return nil
    }

    // MARK: Bindings

    private func summaryBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { CommitMessageParts.split(store.commitPlan.draft(id: id)?.message ?? "").summary },
            set: { summary in
                let body = CommitMessageParts.split(store.commitPlan.draft(id: id)?.message ?? "").body
                store.setMessage(CommitMessageParts.join(summary: summary, body: body), forDraft: id)
            }
        )
    }

    private func bodyBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { CommitMessageParts.split(store.commitPlan.draft(id: id)?.message ?? "").body },
            set: { body in
                let summary = CommitMessageParts.split(store.commitPlan.draft(id: id)?.message ?? "").summary
                store.setMessage(CommitMessageParts.join(summary: summary, body: body), forDraft: id)
            }
        )
    }
}
