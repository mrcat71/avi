import GitKit
import SwiftUI

struct HistoryListView: View {
    let store: RepositoryStore
    var refBadgesByOID: [String: [HistoryRefBadge]] = [:]

    var body: some View {
        Group {
            if store.historyRows.isEmpty && store.isHistoryLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.historyRows.isEmpty {
                ContentUnavailableView(
                    "No Commits",
                    systemImage: "clock",
                    description: Text("This repository has no commits yet.")
                )
            } else {
                List(selection: selection) {
                    ForEach(store.historyRows) { row in
                        HistoryRowView(
                            row: row,
                            refBadges: refBadgesByOID[row.commit.oid] ?? []
                        ) { ref in
                            Task { await store.checkout(ref) }
                        }
                        .tag(row.commit.oid)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedCommitOID },
            set: { newValue in
                let commit = store.historyRows.first { $0.commit.oid == newValue }?.commit
                Task { await store.selectCommit(commit) }
            }
        )
    }
}

struct HistoryRefBadge: Identifiable {
    let label: String
    let ref: GitReference

    var id: String {
        "\(ref.kind.rawValue):\(ref.name):\(ref.oid)"
    }
}

private struct HistoryRowView: View {
    let row: CommitGraphRow
    let refBadges: [HistoryRefBadge]
    let checkoutRef: (GitReference) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HistoryGraphGutter(row: row)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ForEach(Array(refBadges.prefix(4))) { badge in
                        Button {
                            checkoutRef(badge.ref)
                        } label: {
                            Text(badge.label)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .frame(maxWidth: 180)
                                .background(.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Checkout \(badge.ref.name)")
                    }

                    Text(row.commit.subject.isEmpty ? "(no subject)" : row.commit.subject)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    Text(row.commit.authorName)
                    Text(row.commit.shortOID)
                        .font(.caption.monospaced())
                    Text(row.commit.authorDate, format: .dateTime.month().day().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct HistoryGraphGutter: View {
    let row: CommitGraphRow

    private let laneWidth: CGFloat = 12
    private let horizontalInset: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2

            for lane in 0..<max(row.laneCount, 1) {
                var path = Path()
                let x = xPosition(for: lane)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.24)), lineWidth: 1)
            }

            for parentLane in row.parentLanes {
                var path = Path()
                path.move(to: CGPoint(x: xPosition(for: row.lane), y: midY))
                path.addLine(to: CGPoint(x: xPosition(for: parentLane), y: size.height))
                context.stroke(path, with: .color(color(for: row.lane)), lineWidth: 1.5)
            }

            let dotRect = CGRect(
                x: xPosition(for: row.lane) - 4,
                y: midY - 4,
                width: 8,
                height: 8
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(color(for: row.lane)))
        }
        .frame(width: width, height: 34)
    }

    private var width: CGFloat {
        CGFloat(max(row.laneCount, 1)) * laneWidth + horizontalInset * 2
    }

    private func xPosition(for lane: Int) -> CGFloat {
        horizontalInset + CGFloat(lane) * laneWidth + laneWidth / 2
    }

    private func color(for lane: Int) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .teal, .pink, .indigo]
        return palette[lane % palette.count]
    }
}

struct CommitDetailView: View {
    let store: RepositoryStore

    var body: some View {
        if let commit = store.selectedCommit {
            VStack(alignment: .leading, spacing: 0) {
                CommitHeaderView(commit: commit)
                Divider()
                HSplitView {
                    CommitFileListView(store: store)
                        .frame(minWidth: 220, idealWidth: 280)

                    if let file = store.selectedCommitFile {
                        FileDiffView(title: file.displayPath, diff: store.commitDiff)
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
        } else {
            ContentUnavailableView(
                "No Commit Selected",
                systemImage: "clock",
                description: Text("Select a commit to inspect its files and patch.")
            )
        }
    }
}

private struct CommitHeaderView: View {
    let commit: CommitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.subject.isEmpty ? "(no subject)" : commit.subject)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(2)

            HStack(spacing: 10) {
                Label(commit.authorName, systemImage: "person")
                Label(commit.shortOID, systemImage: "number")
                Label {
                    Text(commit.authorDate, format: .dateTime.year().month().day().hour().minute())
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if !commit.body.isEmpty {
                Text(commit.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommitFileListView: View {
    let store: RepositoryStore

    var body: some View {
        List(selection: selection) {
            ForEach(store.commitFiles) { file in
                CommitFileRow(file: file)
                    .tag(file.path)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if store.commitFiles.isEmpty && store.isHistoryLoading {
                ProgressView()
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedCommitPath },
            set: { newValue in
                let file = store.commitFiles.first { $0.path == newValue }
                Task { await store.selectCommitFile(file) }
            }
        )
    }
}

private struct CommitFileRow: View {
    let file: CommitFileChange

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: badge.symbol)
                .foregroundStyle(badge.color)
                .frame(width: 14)
            Text(file.displayPath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(file.kind.rawValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var badge: (symbol: String, color: Color) {
        switch file.kind {
        case .added: ("plus", .green)
        case .modified, .typeChanged: ("pencil", .orange)
        case .deleted: ("minus", .red)
        case .renamed: ("arrow.right", .blue)
        case .copied: ("doc.on.doc", .blue)
        case .unmerged: ("exclamationmark.triangle", .yellow)
        case .unknown: ("circle", .gray)
        }
    }
}
