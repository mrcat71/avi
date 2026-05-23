import GitKit
import SwiftUI

struct DiffDetailView: View {
    let store: RepositoryStore

    var body: some View {
        if let file = store.selectedFile {
            FileDiffView(title: file.path, diff: store.diff)
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
        if let diff {
            if diff.isBinary {
                ContentUnavailableView("Binary File", systemImage: "doc.zipper")
            } else if diff.isEmpty {
                ContentUnavailableView("No Changes", systemImage: "equal")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                            Text(hunk.header)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary)
                            ForEach(hunk.lines) { line in
                                DiffLineRow(line: line)
                            }
                        }
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)
            Text(marker + line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .font(.system(size: 12, design: .monospaced))
        .background(background)
    }

    private func lineNumber(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 38, alignment: .trailing)
            .padding(.horizontal, 2)
    }

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "-"
        case .noNewline: "\\"
        case .context: " "
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        default: .clear
        }
    }
}
