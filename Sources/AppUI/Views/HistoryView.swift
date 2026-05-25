import AppKit
import GitKit
import SwiftUI

struct HistoryListView: View {
    let store: RepositoryStore
    var refBadgesByOID: [String: [HistoryRefBadge]] = [:]

    @State private var multiSelection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HistoryHeader(store: store)
            Divider()
            content
        }
        .onChange(of: store.selectedCommitOID) { _, newValue in
            // Keep List in sync when the detail-view selection moves by code
            // (initial load, command palette navigation, etc.).
            if let newValue {
                if multiSelection != [newValue] { multiSelection = [newValue] }
            } else if !multiSelection.isEmpty {
                multiSelection.removeAll()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.historyRows.isEmpty, store.isHistoryLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.historyRows.isEmpty {
            ContentUnavailableView(
                "No Commits",
                systemImage: "clock",
                description: Text("This repository has no commits yet.")
            )
        } else {
            List(selection: $multiSelection) {
                ForEach(store.historyRows) { row in
                    HistoryRowView(
                        row: row,
                        isSelected: multiSelection.contains(row.commit.oid),
                        refBadges: refBadgesByOID[row.commit.oid] ?? [],
                        laneColors: laneColors,
                        store: store,
                        multiSelectionOIDs: multiSelection
                    ) { ref in
                        Task { await store.checkout(ref) }
                    }
                    .tag(row.commit.oid)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .onChange(of: multiSelection) { _, newValue in
                // Load the diff for the most recently single-selected commit;
                // when 2+ are selected, leave the detail view as-is (we don't
                // have a meaningful "combined diff" view yet).
                if newValue.count == 1, let oid = newValue.first {
                    let commit = store.historyRows.first { $0.commit.oid == oid }?.commit
                    Task { await store.selectCommit(commit) }
                } else if newValue.isEmpty {
                    Task { await store.selectCommit(nil) }
                }
            }
        }
    }

    /// Maps lane index to a stable color derived from the branch that originates that lane.
    /// Lanes whose origin commit has no branch tip fall back to lane-index palette in the view.
    private var laneColors: [Int: Color] {
        var laneOriginOID: [Int: String] = [:]
        for row in store.historyRows {
            if laneOriginOID[row.lane] == nil {
                laneOriginOID[row.lane] = row.commit.oid
            }
        }

        var oidToBranchKey: [String: String] = [:]
        for ref in store.refs.localBranches {
            oidToBranchKey[ref.oid] = "local:\(ref.name)"
        }
        for ref in store.refs.remoteBranches {
            if oidToBranchKey[ref.oid] == nil {
                oidToBranchKey[ref.oid] = "remote:\(ref.name)"
            }
        }

        var result: [Int: Color] = [:]
        for (lane, oid) in laneOriginOID {
            if let key = oidToBranchKey[oid] {
                result[lane] = HistoryGraphPalette.color(for: key)
            }
        }
        return result
    }
}

private struct HistoryHeader: View {
    let store: RepositoryStore

    var body: some View {
        AviPanelHeader("History", breadcrumb: breadcrumb) {
            filterMenu
        }
    }

    private var breadcrumb: [String] {
        var segments = [scopeLabel]
        if store.historyFilter.hideMerges {
            segments.append("no merges")
        }
        segments.append(commitsLabel)
        return segments
    }

    private var filterMenu: some View {
        Menu {
            Section("Scope") {
                Button {
                    Task { await store.setHistoryFilter(HistoryFilter(scope: .currentBranch, hideMerges: store.historyFilter.hideMerges)) }
                } label: {
                    Label("Current branch", systemImage: isCurrentScope(.currentBranch) ? "checkmark" : "")
                }
                Button {
                    Task { await store.setHistoryFilter(HistoryFilter(scope: .allBranches, hideMerges: store.historyFilter.hideMerges)) }
                } label: {
                    Label("All branches", systemImage: isCurrentScope(.allBranches) ? "checkmark" : "")
                }
                if case .ref(let name) = store.historyFilter.scope {
                    Button {
                        Task { await store.setHistoryFilter(HistoryFilter(scope: .ref(name), hideMerges: store.historyFilter.hideMerges)) }
                    } label: {
                        Label(name, systemImage: "checkmark")
                    }
                }
            }

            Section {
                Button {
                    Task {
                        await store.setHistoryFilter(HistoryFilter(scope: store.historyFilter.scope, hideMerges: !store.historyFilter.hideMerges))
                    }
                } label: {
                    Label("Hide merge commits", systemImage: store.historyFilter.hideMerges ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: DS.IconScale.md, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .accessibilityLabel("Filter history")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter history")
    }

    private var scopeLabel: String {
        switch store.historyFilter.scope {
        case .currentBranch:
            return store.branch?.name ?? "current branch"
        case .allBranches:
            return "all branches"
        case .ref(let name):
            return name
        }
    }

    private var commitsLabel: String {
        let n = store.historyRows.count
        if n == 0 { return "no commits" }
        return n == 1 ? "1 commit" : "\(n) commits"
    }

    private func isCurrentScope(_ scope: HistoryFilter.Scope) -> Bool {
        switch (store.historyFilter.scope, scope) {
        case (.currentBranch, .currentBranch), (.allBranches, .allBranches): return true
        case (.ref(let a), .ref(let b)): return a == b
        default: return false
        }
    }
}

enum HistoryGraphPalette {
    static let lanePalette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink, .indigo, .brown]

    static func color(for key: String) -> Color {
        var hash: UInt32 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return lanePalette[Int(hash % UInt32(lanePalette.count))]
    }

    static func color(forLane index: Int) -> Color {
        lanePalette[index % lanePalette.count]
    }
}

struct HistoryRefBadge: Identifiable {
    let label: String
    let ref: GitReference

    var id: String {
        "\(ref.kind.rawValue):\(ref.name):\(ref.oid)"
    }
}

struct PanelHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}

private struct HistoryRowView: View {
    let row: CommitGraphRow
    let isSelected: Bool
    let refBadges: [HistoryRefBadge]
    let laneColors: [Int: Color]
    let store: RepositoryStore
    let multiSelectionOIDs: Set<String>
    let checkoutRef: (GitReference) -> Void

    @Environment(\.aviDensity) private var density

    private let maxVisibleBadges = 4

    var body: some View {
        HStack(spacing: 0) {
            // Leading accent stripe (visible only on selected row).
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 3)

            HStack(spacing: 6) {
                HistoryGraphView(row: row, isSelected: isSelected, laneColors: laneColors)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        ForEach(visibleBadges) { badge in
                            BadgePill(badge: badge) {
                                checkoutRef(badge.ref)
                            }
                        }

                        if hiddenCount > 0 {
                            Text("+\(hiddenCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.10))
                                )
                                .foregroundStyle(.secondary)
                        }

                        Text(row.commit.subject.isEmpty ? "(no subject)" : row.commit.subject)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    HStack(spacing: 5) {
                        Text(row.commit.authorName)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(row.commit.shortOID)
                            .font(.system(size: 10, design: .monospaced))
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(row.commit.authorDate, format: .dateTime.month().day().hour().minute())
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.leading, 4)
        }
        .frame(height: density == .compact ? 28 : 36)
        .contentShape(Rectangle())
        .help(fullMessage)
        .contextMenu {
            Button("Copy SHA") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(row.commit.shortOID, forType: .string)
            }
            Button("Copy Full SHA") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(row.commit.oid, forType: .string)
            }
            Button("Copy Subject") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(row.commit.subject, forType: .string)
            }
            Divider()
            aiContextMenuSection
        }
    }

    @ViewBuilder
    private var aiContextMenuSection: some View {
        let aiEnabled = ConfigStore.shared.config.ai.enabled
        let busy = store.isAIWorking || store.rebaseInProgress
        let isInMultiSelection = multiSelectionOIDs.contains(row.commit.oid)
        let multiCount = multiSelectionOIDs.count
        if isInMultiSelection, multiCount >= 2 {
            Button("Recompose \(multiCount) Selected Commits with AI") {
                store.recomposeCommitsWithAI(oids: multiSelectionOIDs)
            }
            .disabled(!aiEnabled || busy)
        } else {
            Menu("AI") {
                Button("Reword Commit") {
                    store.rewordCommitWithAI(oid: row.commit.oid)
                }
                .disabled(!aiEnabled || busy)
                Button("Split Commit Into Multiple…") {
                    store.splitOldCommitWithAI(oid: row.commit.oid)
                }
                .disabled(!aiEnabled || busy)
            }
        }
    }

    private var visibleBadges: [HistoryRefBadge] {
        Array(refBadges.prefix(maxVisibleBadges))
    }

    private var hiddenCount: Int {
        max(0, refBadges.count - maxVisibleBadges)
    }

    private var fullMessage: String {
        var text = row.commit.subject.isEmpty ? "(no subject)" : row.commit.subject
        if !row.commit.body.isEmpty {
            text += "\n\n" + row.commit.body
        }
        return text
    }
}

private struct BadgePill: View {
    let badge: HistoryRefBadge
    let checkout: () -> Void

    var body: some View {
        Button(action: checkout) {
            AviBadge(badgeKind, text: label)
        }
        .buttonStyle(.plain)
        .aviTooltip {
            BadgePopover(badge: badge)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var badgeKind: AviBadge.Kind {
        switch badge.ref.kind {
        case .localBranch:
            return badge.ref.isCurrent ? .currentBranch : .localBranch
        case .remoteBranch:
            return .remoteBranch
        case .tag:
            return .tag
        }
    }

    private var label: String {
        switch badge.ref.kind {
        case .remoteBranch:
            return badge.ref.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? badge.ref.name
        default:
            return badge.ref.name
        }
    }

    private var accessibilityLabel: String {
        let kindWord: String
        switch badge.ref.kind {
        case .localBranch: kindWord = badge.ref.isCurrent ? "current branch" : "local branch"
        case .remoteBranch: kindWord = "remote branch"
        case .tag: kindWord = "tag"
        }
        return "\(kindWord) \(badge.ref.name)"
    }
}

private struct BadgePopover: View {
    let badge: HistoryRefBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Type", typeLabel)
            row("Name", badge.ref.name)
            row("Commit", String(badge.ref.oid.prefix(12)))
            if let upstream = badge.ref.upstream, badge.ref.kind != .tag {
                row("Tracking", upstream)
            }
            if let ahead = badge.ref.ahead, ahead > 0 {
                row("Ahead", "\(ahead)")
            }
            if let behind = badge.ref.behind, behind > 0 {
                row("Behind", "\(behind)")
            }
            if badge.ref.kind == .tag, let date = badge.ref.taggerDate {
                row("Date", date.formatted(.dateTime.year().month().day().hour().minute()))
            }
            if let message = badge.ref.annotatedMessage {
                Divider()
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            if let subject = badge.ref.subject {
                Divider()
                Text(subject)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: key == "Commit" ? .monospaced : .default))
                .textSelection(.enabled)
        }
    }

    private var typeLabel: String {
        switch badge.ref.kind {
        case .localBranch: return badge.ref.isCurrent ? "Local branch (current)" : "Local branch"
        case .remoteBranch: return "Remote branch"
        case .tag: return badge.ref.annotatedMessage != nil ? "Annotated tag" : "Lightweight tag"
        }
    }
}

// Old HistoryGraphGutter replaced by HistoryGraphView.swift (Phase 2 rewrite).

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
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.subject.isEmpty ? "(no subject)" : commit.subject)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                meta(systemImage: "person", text: commit.authorName)
                meta(systemImage: "number", text: commit.shortOID, monospaced: true)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9))
                    Text(commit.authorDate, format: .dateTime.year().month().day().hour().minute())
                        .font(.system(size: 11))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if !commit.body.isEmpty {
                ScrollView {
                    Text(commit.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(systemImage: String, text: String, monospaced: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
        }
    }
}

private struct CommitFileListView: View {
    let store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Files", trailing: filesSummary)
            Divider()
            List(selection: selection) {
                ForEach(store.commitFiles) { file in
                    CommitFileRow(file: file)
                        .tag(file.path)
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if store.commitFiles.isEmpty, store.isHistoryLoading {
                    ProgressView()
                }
            }
        }
    }

    private var filesSummary: String? {
        let n = store.commitFiles.count
        if n == 0 { return nil }
        return n == 1 ? "1 file" : "\(n) files"
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
        HStack(spacing: 6) {
            Image(systemName: badge.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(badge.color)
                .frame(width: 12)
            Text(file.displayPath)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(file.kind.rawValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 1)
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
