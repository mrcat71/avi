import GitKit
import SwiftUI

/// "Interactively Rebase on <branch>": the commits the rebase replays, oldest
/// first. Reorder them by dragging or with Move Up / Move Down, and pick what
/// happens to each before Git runs the plan.
/// What an interactive rebase replays the current branch's commits onto: a
/// branch tip from the branch menu, or a commit from History's commit menu.
struct RebaseBase: Equatable {
    /// For people: a branch name, or a commit's short SHA.
    let title: String
    /// For Git: `refs/heads/<branch>`, or a full commit ID.
    let revision: String
    let isCommit: Bool

    static func branch(_ ref: GitReference) -> RebaseBase {
        RebaseBase(title: ref.name, revision: "refs/heads/\(ref.name)", isCommit: false)
    }

    static func commit(_ commit: CommitSummary) -> RebaseBase {
        RebaseBase(title: commit.shortOID, revision: commit.oid, isCommit: true)
    }
}

struct InteractiveRebaseSheet: View {
    let store: RepositoryStore
    let base: RebaseBase

    init(store: RepositoryStore, base: RebaseBase) {
        self.store = store
        self.base = base
    }

    init(store: RepositoryStore, onto ref: GitReference) {
        self.init(store: store, base: .branch(ref))
    }

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var original: [String] = []
    @State private var selection: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var autostash = true

    struct Row: Identifiable, Equatable {
        let commit: CommitSummary
        var step: Step = .pick
        var message: String

        var id: String {
            commit.oid
        }
    }

    enum Step: String, CaseIterable, Identifiable {
        case pick, reword, edit, squash, fixup, drop

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .pick: return "Pick"
            case .reword: return "Reword"
            case .edit: return "Edit"
            case .squash: return "Squash"
            case .fixup: return "Fixup"
            case .drop: return "Drop"
            }
        }

        var help: String {
            switch self {
            case .pick: return "Keep the commit as it is"
            case .reword: return "Keep the changes, write a new message"
            case .edit: return "Stop after this commit so you can amend it"
            case .squash: return "Fold into the commit above, keeping both messages"
            case .fixup: return "Fold into the commit above, keeping only its message"
            case .drop: return "Remove the commit and its changes"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Interactive Rebase")
                    .font(.system(size: 14, weight: .semibold))
                Text(base.isCommit
                    ? "Replays \(current)'s commits after \(base.title), oldest at the top. Git applies them from top to bottom."
                    : "Replays \(current)'s commits onto \(base.title), oldest at the top. Git applies them from top to bottom.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Move Up") { move(by: -1) }
                    .disabled(!canMove(by: -1))
                Button("Move Down") { move(by: 1) }
                    .disabled(!canMove(by: 1))
                Toggle("Stash uncommitted changes during the rebase", isOn: $autostash)
                    .controlSize(.small)
                    .padding(.leading, 8)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start Rebase", action: start)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(plan == nil)
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(width: 680, height: 520)
        .task(load)
    }

    private var current: String {
        store.branch?.name ?? "HEAD"
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView("Cannot List the Commits", systemImage: "exclamationmark.triangle", description: Text(loadError))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView(
                "Nothing to Rebase",
                systemImage: "checkmark.circle",
                description: Text(base.isCommit ? "\(current) has no commits after \(base.title)." : "\(current) has no commits that \(base.title) lacks.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach($rows) { $row in
                    RebaseRow(row: $row, isFirstKept: isFirstKept(row))
                        .tag(row.id)
                }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    /// The plan as Git will run it, or nil while something in it is invalid.
    private var plan: InteractiveRebasePlan? {
        try? makePlan()
    }

    private var problem: String? {
        guard !rows.isEmpty else { return nil }
        do {
            _ = try makePlan()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func makePlan() throws -> InteractiveRebasePlan {
        try InteractiveRebasePlan(original: original, items: rows.map { row in
            switch row.step {
            case .pick: return RebaseTodoItem(oid: row.id, action: .pick)
            case .reword: return RebaseTodoItem(oid: row.id, action: .reword(row.message))
            case .edit: return RebaseTodoItem(oid: row.id, action: .edit)
            case .squash: return RebaseTodoItem(oid: row.id, action: .squash)
            case .fixup: return RebaseTodoItem(oid: row.id, action: .fixup)
            case .drop: return RebaseTodoItem(oid: row.id, action: .drop)
            }
        })
    }

    /// Squash and fixup need a kept commit above them.
    private func isFirstKept(_ row: Row) -> Bool {
        rows.first { $0.step != .drop }?.id == row.id
    }

    @Sendable
    private func load() async {
        do {
            let commits = try await store.rebaseCandidates(ontoRevision: base.revision)
            original = commits.map(\.oid)
            rows = commits.map { commit in
                Row(commit: commit, message: commit.body.isEmpty ? commit.subject : commit.subject + "\n\n" + commit.body)
            }
            selection = rows.first?.id
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func canMove(by offset: Int) -> Bool {
        guard let selection, let index = rows.firstIndex(where: { $0.id == selection }) else { return false }
        return rows.indices.contains(index + offset)
    }

    private func move(by offset: Int) {
        guard canMove(by: offset), let selection, let index = rows.firstIndex(where: { $0.id == selection }) else { return }
        rows.swapAt(index, index + offset)
    }

    private func start() {
        guard let plan else { return }
        let autostash = autostash
        dismiss()
        let revision = base.revision
        Task { await store.interactiveRebase(ontoRevision: revision, plan: plan, autostash: autostash) }
    }
}

private struct RebaseRow: View {
    @Binding var row: InteractiveRebaseSheet.Row
    let isFirstKept: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker("Action", selection: $row.step) {
                    ForEach(InteractiveRebaseSheet.Step.allCases) { step in
                        Text(step.title)
                            .tag(step)
                            .help(step.help)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 96)
                .help(row.step.help)
                .accessibilityLabel("Action for \(row.commit.subject)")
                Text(String(row.commit.oid.prefix(8)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(row.commit.subject.isEmpty ? "(no subject)" : row.commit.subject)
                    .font(.system(size: 12))
                    .strikethrough(row.step == .drop)
                    .foregroundStyle(row.step == .drop ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if isFirstKept, row.step == .squash || row.step == .fixup {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Nothing above to fold into")
                        .accessibilityLabel("Nothing above to fold into")
                }
                Text(row.commit.authorName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if row.step == .reword {
                TextEditor(text: $row.message)
                    .font(.system(size: 12))
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                    .accessibilityLabel("New message for \(row.commit.subject)")
            }
        }
        .padding(.vertical, 2)
    }
}
