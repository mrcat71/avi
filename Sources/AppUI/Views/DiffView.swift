import GitKit
import SwiftUI

struct DiffDetailView: View {
    let store: RepositoryStore

    @State private var pendingDiscard: PendingLineDiscard?

    var body: some View {
        if let file = store.selectedFile {
            FileDiffView(title: file.path, diff: store.diff, errorMessage: store.diffError, lineActions: lineActions(for: file)) {
                if let file = store.selectedFile {
                    await store.loadDiff(for: file)
                }
            }
            .confirmationDialog(
                pendingDiscard?.title ?? "",
                isPresented: Binding(get: { pendingDiscard != nil }, set: {
                    if !$0 {
                        pendingDiscard = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: pendingDiscard
            ) { pending in
                Button("Discard", role: .destructive) {
                    Task { await store.applyLines(.discard, keys: pending.keys, file: pending.file) }
                }
            } message: { _ in
                Text("The working tree loses these changes. This cannot be undone.")
            }
        } else {
            EmptyDiffState(store: store)
        }
    }

    /// Staging picked lines works on a file changed in place, in the unified diff.
    private func lineActions(for file: FileStatus) -> DiffLineActions? {
        guard !DiffPreferences.shared.sideBySide else { return nil }
        let perform: (DiffLineCommand, Set<DiffLineKey>) -> Void = { command, keys in
            if command == .discard {
                pendingDiscard = PendingLineDiscard(file: file, keys: keys)
            } else {
                Task { await store.applyLines(command, keys: keys, file: file) }
            }
        }
        switch store.selectedDiffSource {
        case .unstaged where file.worktree == .modified:
            return DiffLineActions(mode: .unstaged, perform: perform)
        case .staged where file.index == .modified:
            return DiffLineActions(mode: .staged, perform: perform)
        default:
            return nil
        }
    }
}

/// Lines waiting for you to confirm discarding them.
private struct PendingLineDiscard {
    let file: FileStatus
    let keys: Set<DiffLineKey>

    var title: String {
        keys.count == 1 ? "Discard 1 changed line?" : "Discard \(keys.count) changed lines?"
    }
}

private struct EmptyDiffState: View {
    let store: RepositoryStore

    var body: some View {
        AviEmptyState(
            icon: store.entries.isEmpty ? "checkmark.seal" : "doc.text",
            title: headline,
            message: subhead,
            iconTint: store.entries.isEmpty ? DS.Palette.success : DS.Palette.textTertiary
        ) {
            if store.canStageAll {
                AviButton("Stage all changes", icon: "plus.rectangle.on.rectangle", variant: .secondary, size: .small) {
                    Task { await store.stageAll() }
                }
                .frame(maxWidth: .infinity)
            }
            AviButton("Refresh", icon: "arrow.clockwise", variant: .secondary, size: .small) {
                Task { await store.refresh() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var headline: String {
        store.entries.isEmpty ? "Working tree clean" : "No file selected"
    }

    private var subhead: String {
        store.entries.isEmpty
            ? "Nothing to stage or commit right now."
            : "Pick a changed file on the left to see its diff."
    }
}

struct FileDiffView: View {
    let title: String
    let diff: FileDiff?
    var errorMessage: String?
    /// Staging picked lines, in the Changes view only.
    var lineActions: DiffLineActions?
    /// Loads the diff again after the toolbar changes what Git is asked for.
    var reload: (@MainActor () async -> Void)?

    private let preferences = DiffPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DiffToolbar(preferences: preferences, reloads: reload != nil)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 28)
            Divider()
            content
        }
        .onChange(of: preferences.gitOptions) { _, _ in
            guard let reload else { return }
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView("Unable to Load Diff", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if let diff {
            if diff.isBinary {
                ContentUnavailableView("Binary File", systemImage: "doc.zipper")
            } else if diff.isEmpty {
                ContentUnavailableView(
                    "No Changes",
                    systemImage: "equal",
                    description: preferences.ignoreWhitespace ? Text("Whitespace changes are hidden.") : nil
                )
            } else if preferences.sideBySide {
                SideBySideDiffView(diff: diff, showsInvisibles: preferences.showInvisibles)
                    .id(title)
            } else {
                NativeDiffTextView(
                    diff: diff,
                    display: DiffDisplay(wrapsLines: preferences.wrapLines, showsInvisibles: preferences.showInvisibles),
                    lineActions: lineActions
                )
                .id(title)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The diff's options as a row of small toggles, as in Fork: whitespace,
/// invisible characters, wrapping, lines of context, the whole file, and
/// side by side. They apply to every diff in Avi.
struct DiffToolbar: View {
    @Bindable var preferences: DiffPreferences
    /// False where the diff cannot load again, so Git's options would not apply.
    let reloads: Bool

    var body: some View {
        HStack(spacing: 1) {
            toggle("space", "Ignore Whitespace", isOn: $preferences.ignoreWhitespace)
                .disabled(!reloads)
            toggle("paragraphsign", "Show Invisible Characters", isOn: $preferences.showInvisibles)
            toggle("arrow.turn.down.left", preferences.sideBySide ? "Wrap Lines (not side by side)" : "Wrap Lines", isOn: $preferences.wrapLines)
                .disabled(preferences.sideBySide)
            button("text.badge.minus", "Fewer Lines of Context (\(preferences.contextLines))") {
                preferences.showFewerLines()
            }
            .disabled(!reloads || !preferences.canShowFewerLines)
            button("text.badge.plus", "More Lines of Context (\(preferences.contextLines))") {
                preferences.showMoreLines()
            }
            .disabled(!reloads || !preferences.canShowMoreLines)
            toggle("arrow.up.and.down.text.horizontal", "Show Entire File", isOn: $preferences.wholeFile)
                .disabled(!reloads)
            toggle("rectangle.split.2x1", "Side by Side", isOn: $preferences.sideBySide)
        }
    }

    private func toggle(_ symbol: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 20)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn.wrappedValue ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func button(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 20)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}
