import GitKit
import SwiftUI

struct DiffDetailView: View {
    let store: RepositoryStore

    var body: some View {
        if let file = store.selectedFile {
            FileDiffView(title: file.path, diff: store.diff, errorMessage: store.diffError)
        } else {
            EmptyDiffState(store: store)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            content
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
                ContentUnavailableView("No Changes", systemImage: "equal")
            } else {
                NativeDiffTextView(diff: diff)
                    .id(title)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
