import GitKit
import SwiftUI

struct ChangeListView: View {
    let store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(changeSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await store.stageAll() }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.borderless)
                .disabled(!store.canStageAll)
                .help("Stage All")

                Button {
                    Task { await store.unstageAll() }
                } label: {
                    Image(systemName: "minus.square")
                }
                .buttonStyle(.borderless)
                .disabled(!store.canUnstageAll)
                .help("Unstage All")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)

            Divider()

            List(selection: selection) {
                if !store.stagedEntries.isEmpty {
                    Section("Staged") {
                        ForEach(store.stagedEntries) { file in
                            ChangeRow(file: file, staged: true, store: store)
                        }
                    }
                }
                Section("Changes") {
                    if store.unstagedEntries.isEmpty {
                        Text("No changes")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.unstagedEntries) { file in
                            ChangeRow(file: file, staged: false, store: store)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
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

    private var changeSummary: String {
        let staged = store.stagedEntries.count
        let unstaged = store.unstagedEntries.count
        if staged == 0 && unstaged == 0 { return "Clean" }
        return "\(staged) staged, \(unstaged) changed"
    }
}

private struct ChangeRow: View {
    let file: FileStatus
    let staged: Bool
    let store: RepositoryStore
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: badge.symbol)
                .foregroundStyle(badge.color)
                .frame(width: 14)
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if staged {
                actionButton("minus.circle", help: "Unstage") {
                    Task { await store.unstage(file) }
                }
            } else {
                actionButton("plus.circle", help: "Stage") {
                    Task { await store.stage(file) }
                }
                actionButton("arrow.uturn.backward.circle", help: "Discard") {
                    confirmingDiscard = true
                }
            }
        }
        .font(.system(size: 13))
        .padding(.vertical, 2)
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

    private func actionButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
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
