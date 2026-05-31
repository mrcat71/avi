import GitKit
import SwiftUI

/// Shows the contents of a stash - its changed files and the per-file diff -
/// when a stash is selected in the sidebar. A stash is commit-like, so this
/// mirrors `CommitDetailView` and reuses `CommitFileRow` and `FileDiffView`.
struct StashContentsWorkspaceView: View {
    let store: RepositoryStore
    let ref: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                StashFileListView(store: store)
                    .frame(minWidth: 220, idealWidth: 280)

                if let file = store.selectedStashFile {
                    FileDiffView(title: file.displayPath, diff: store.stashFileDiff)
                        .frame(minWidth: 420)
                } else {
                    ContentUnavailableView(
                        "No File Selected",
                        systemImage: "doc.text",
                        description: Text("Select a changed file to see its diff.")
                    )
                    .frame(minWidth: 420)
                }
            }
        }
        .task(id: ref) {
            await store.selectStash(ref: ref)
        }
    }

    private var entry: StashEntry? {
        store.stashes.first { $0.ref == ref }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(entry.map { "{\($0.index)}" } ?? ref)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if let branch = entry?.branch {
                Text("on \(branch)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Strip the "WIP on <branch>: " / "On <branch>: " reflog prefix so the
    /// header shows the meaningful message, matching the sidebar StashRow.
    private var title: String {
        guard let subject = entry?.subject else { return ref }
        if let colon = subject.firstIndex(of: ":") {
            let after = subject[subject.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !after.isEmpty { return after }
        }
        return subject
    }
}

private struct StashFileListView: View {
    let store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Files", trailing: filesSummary)
            Divider()
            List(selection: selection) {
                ForEach(store.stashFiles) { file in
                    CommitFileRow(file: file)
                        .tag(file.path)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if store.stashFiles.isEmpty {
                    if store.isStashLoading {
                        ProgressView()
                    } else {
                        ContentUnavailableView(
                            "No Changes",
                            systemImage: "tray",
                            description: Text("This stash has no tracked changes to show.")
                        )
                    }
                }
            }
        }
    }

    private var filesSummary: String? {
        let n = store.stashFiles.count
        if n == 0 { return nil }
        return n == 1 ? "1 file" : "\(n) files"
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedStashPath },
            set: { newValue in
                let file = store.stashFiles.first { $0.path == newValue }
                Task { await store.selectStashFile(file) }
            }
        )
    }
}
