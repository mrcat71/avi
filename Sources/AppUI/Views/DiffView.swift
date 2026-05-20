import GitKit
import SwiftUI

struct DiffDetailView: View {
    let store: RepositoryStore

    var body: some View {
        if let file = store.selectedFile {
            FileDiffView(title: file.path, diff: store.diff)
        } else {
            ContentUnavailableView(
                "No File Selected",
                systemImage: "doc.text",
                description: Text("Select a changed file to see its diff.")
            )
        }
    }
}

struct FileDiffView: View {
    let title: String
    let diff: FileDiff?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
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
                .padding(.leading, 8)
        }
        .font(.system(.body, design: .monospaced))
        .background(background)
    }

    private func lineNumber(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
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
        case .addition: .green.opacity(0.15)
        case .deletion: .red.opacity(0.15)
        default: .clear
        }
    }
}
