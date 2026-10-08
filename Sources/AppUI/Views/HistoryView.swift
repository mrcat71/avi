import AppKit
import GitKit
import SwiftUI

struct HistoryListView: View {
    let store: RepositoryStore
    var refBadgesByOID: [String: [HistoryRefBadge]] = [:]

    @State private var multiSelection: Set<String> = []
    @State private var confirmation: CommitConfirmation?
    @State private var resetTarget: CommitSummary?
    @State private var compareTarget: CommitSummary?
    @State private var rebaseTarget: CommitSummary?
    @State private var searchQuery = ""
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.aviDensity) private var density

    var body: some View {
        let search = searchState
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HistoryHeader(store: store) {
                    HistorySearchField(
                        query: $searchQuery,
                        isExpanded: $isSearchExpanded,
                        isFocused: $isSearchFocused,
                        position: search.position(of: store.selectedCommitOID),
                        matchCount: search.matchIndices.count,
                        step: { jump($0, in: search) }
                    )
                }
                Divider()
                HStack(spacing: 12) {
                    Text("Commit").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Author").frame(width: HistoryRowView.authorWidth(avatarSize: avatarSize), alignment: .leading)
                    Text("SHA").frame(width: 65, alignment: .leading)
                    Text("Date").frame(width: 120, alignment: .trailing)
                }
                .aviLabel(density, color: DS.Palette.textTertiary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(DS.Palette.surface)
                Divider()
                if search.isActive, search.matchIndices.isEmpty {
                    NoMatchesBanner(store: store)
                    Divider()
                }
                content(search)
            }
            .onChange(of: store.selectedCommitOID, initial: true) { _, newValue in
                // Reveal sidebar/palette navigation, without recentering ordinary row clicks.
                if let newValue {
                    if multiSelection != [newValue] {
                        multiSelection = [newValue]
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                } else if !multiSelection.isEmpty {
                    multiSelection.removeAll()
                }
            }
        }
        // Typing goes to the first match after the selection, as Find does,
        // unless the selected commit already matches.
        .task(id: searchQuery) {
            guard !HistorySearch.terms(in: searchQuery).isEmpty else { return }
            try? await Task.safeSleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let search = searchState
            if let selected = store.selectedCommitOID, search.matchOIDs.contains(selected) {
                return
            }
            jump(1, in: search)
        }
        .task(id: store.wantsHistorySearchFocus) {
            guard store.wantsHistorySearchFocus else { return }
            store.wantsHistorySearchFocus = false
            isSearchExpanded = true
            // The field has to exist before it can take focus.
            try? await Task.safeSleep(for: .milliseconds(50))
            isSearchFocused = true
        }
    }

    private var headName: String {
        store.branch.flatMap { $0.isDetached ? nil : "'\($0.name)'" } ?? "HEAD"
    }

    private var searchState: HistorySearchState {
        let terms = HistorySearch.terms(in: searchQuery)
        guard !terms.isEmpty else { return HistorySearchState(terms: [], rows: []) }
        return HistorySearchState(terms: terms, rows: store.historyRows)
    }

    /// Selects the next (+1) or previous (-1) match; selecting reveals the row.
    private func jump(_ step: Int, in search: HistorySearchState) {
        let rows = store.historyRows
        let selected = store.selectedCommitOID.flatMap { oid in rows.firstIndex { $0.commit.oid == oid } }
        guard let target = HistorySearch.nextMatch(after: selected, in: search.matchIndices, step: step),
              rows.indices.contains(target) else { return }
        Task { await store.selectCommit(rows[target].commit) }
    }

    /// Runs a choice from a commit's context menu; the list owns the sheets and alerts.
    private func handle(_ action: CommitMenuAction, _ commit: CommitSummary) {
        switch action {
        case .newBranch:
            NotificationCenter.default.post(name: .aviCreateBranch, object: commit.oid)
        case .newTag:
            NotificationCenter.default.post(name: .aviCreateTag, object: commit.oid)
        case .interactiveRebase:
            rebaseTarget = commit
        case .editCommit:
            Task { await store.editCommit(commit) }
        case .reset:
            resetTarget = commit
        case .checkout, .cherryPick, .revert:
            confirmation = CommitConfirmation(action: action, commit: commit)
        case .savePatch:
            Task { await store.savePatch(for: commit) }
        case .compare:
            compareTarget = commit
        case .copySHA:
            Self.copy(commit.oid)
        case .copyShortSHA:
            Self.copy(commit.shortOID)
        case .copySubject:
            Self.copy(commit.subject)
        }
    }

    private static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func confirm(_ item: CommitConfirmation) {
        switch item.action {
        case .checkout:
            Task { await store.checkoutCommit(item.commit) }
        case .cherryPick:
            Task { await store.cherryPick(item.commit) }
        case .revert:
            Task { await store.revert(item.commit) }
        default:
            break
        }
    }

    @ViewBuilder
    private func content(_ search: HistorySearchState) -> some View {
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
            let ancestry = store.headAncestry()
            let headOID = store.detachedHead?.oid ?? store.branch?.oid
            let gitLabHost = store.gitLabHost
            List(selection: $multiSelection) {
                ForEach(store.historyRows) { row in
                    HistoryRowView(
                        row: row,
                        isSelected: multiSelection.contains(row.commit.oid),
                        refBadges: refBadgesByOID[row.commit.oid] ?? [],
                        laneColors: laneColors,
                        graphWidth: graphWidth,
                        store: store,
                        multiSelectionOIDs: multiSelection,
                        searchTerms: search.terms,
                        isDimmed: search.isActive && !search.matchOIDs.contains(row.commit.oid),
                        isOnHead: ancestry.contains(row.commit.oid),
                        isHead: row.commit.oid == headOID,
                        laneWidth: laneWidth,
                        avatarSize: avatarSize,
                        gitLabHost: gitLabHost,
                        menu: handle
                    ) { ref in
                        Task { await store.checkout(ref) }
                    }
                    .tag(row.commit.oid)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                if store.hasOlderHistory {
                    OlderHistoryRow(store: store, isSearching: search.isActive)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            // Edit > Copy copies the selected commits' SHAs, newest first.
            .onCopyCommand {
                let oids = store.historyRows.map(\.commit.oid).filter(multiSelection.contains)
                guard !oids.isEmpty else { return [] }
                return [NSItemProvider(object: oids.joined(separator: "\n") as NSString)]
            }
            .alert(
                confirmation?.title(head: headName) ?? "",
                isPresented: Binding(get: { confirmation != nil }, set: {
                    if !$0 {
                        confirmation = nil
                    }
                }),
                presenting: confirmation
            ) { item in
                Button(item.confirmTitle) { confirm(item) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text(item.message(head: headName, store: store))
            }
            .sheet(item: $resetTarget) { commit in
                ResetToCommitSheet(store: store, commit: commit)
            }
            .sheet(item: $compareTarget) { commit in
                CompareWithWorkingTreeSheet(store: store, commit: commit)
            }
            .sheet(item: $rebaseTarget) { commit in
                InteractiveRebaseSheet(store: store, base: .commit(commit))
            }
            .onChange(of: multiSelection) { _, newValue in
                // Load the diff for the most recently single-selected commit;
                // when 2+ are selected, leave the detail view as-is (we don't
                // have a meaningful "combined diff" view yet).
                if newValue.count == 1, let oid = newValue.first, store.selectedCommitOID != oid {
                    let commit = store.historyRows.first { $0.commit.oid == oid }?.commit
                    Task { await store.selectCommit(commit) }
                } else if newValue.isEmpty, store.selectedCommitOID != nil {
                    Task { await store.selectCommit(nil) }
                }
            }
        }
    }

    private var graphWidth: CGFloat {
        CGFloat(max(store.historyRows.map(\.laneCount).max() ?? 1, 1)) * laneWidth + HistoryGraphView.horizontalInset * 2
    }

    /// Settings > Appearance > Graph lane width.
    private var laneWidth: CGFloat {
        CGFloat(ConfigStore.shared.config.appearance.graphLaneWidth)
    }

    private var avatarSize: CGFloat? {
        guard ConfigStore.shared.config.appearance.authorPictures else { return nil }
        return density == .compact ? 14 : 16
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

private struct HistoryHeader<Search: View>: View {
    let store: RepositoryStore
    @ViewBuilder let search: Search

    var body: some View {
        AviPanelHeader("History", breadcrumb: breadcrumb) {
            HStack(spacing: 2) {
                search
                filterMenu
            }
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
        if n == 0 {
            return "no commits"
        }
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
    static let lanePalette: [Color] = DS.Palette.lanes

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

/// A commit action that asks first: what it is about to do, and to what.
struct CommitConfirmation: Identifiable {
    let action: CommitMenuAction
    let commit: CommitSummary

    var id: String {
        "\(action):\(commit.oid)"
    }

    func title(head: String) -> String {
        switch action {
        case .checkout: return "Check out \(commit.shortOID)?"
        case .cherryPick: return "Cherry-pick \(commit.shortOID) onto \(head)?"
        case .revert: return "Revert \(commit.shortOID)?"
        default: return ""
        }
    }

    var confirmTitle: String {
        switch action {
        case .checkout: return "Check Out"
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        default: return "OK"
        }
    }

    @MainActor
    func message(head: String, store: RepositoryStore) -> String {
        let subject = commit.subject.isEmpty ? "(no subject)" : commit.subject
        let merge = commit.parentOIDs.count > 1 ? " It is a merge, so Avi uses its first parent as the mainline." : ""
        switch action {
        case .checkout:
            var text = "HEAD will be detached at “\(subject)”. Commits you make there belong to no branch until you create one."
            if let head = store.detachedHead, let stranded = head.unreferencedCount, stranded > 0 {
                text += " HEAD has \(stranded) commit\(stranded == 1 ? "" : "s") on no branch now; leaving keeps them only in the reflog."
            }
            if !store.entries.isEmpty {
                text += " Local changes come along; Git refuses if the commit would overwrite them."
            }
            return text
        case .cherryPick:
            return "Applies “\(subject)” as a new commit on top of \(head).\(merge) Conflicts stop it so you can resolve them."
        case .revert:
            return "Adds a commit on \(head) that undoes “\(subject)”.\(merge) Conflicts stop it so you can resolve them."
        default:
            return ""
        }
    }
}

/// Search results over the loaded history rows, computed once per render.
struct HistorySearchState {
    let terms: [String]
    /// Row indexes of the matches, in display order.
    let matchIndices: [Int]
    let matchOIDs: Set<String>
    private let rowIndexByOID: [String: Int]

    init(terms: [String], rows: [CommitGraphRow]) {
        self.terms = terms
        var indices: [Int] = []
        var oids: Set<String> = []
        var byOID: [String: Int] = [:]
        if !terms.isEmpty {
            for (index, row) in rows.enumerated() where HistorySearch.matches(row.commit, terms: terms) {
                indices.append(index)
                oids.insert(row.commit.oid)
                byOID[row.commit.oid] = indices.count
            }
        }
        matchIndices = indices
        matchOIDs = oids
        rowIndexByOID = byOID
    }

    var isActive: Bool {
        !terms.isEmpty
    }

    /// 1-based position of `oid` among the matches.
    func position(of oid: String?) -> Int? {
        oid.flatMap { rowIndexByOID[$0] }
    }
}

/// Last row of History when Git may have older commits than the ones loaded.
private struct OlderHistoryRow: View {
    let store: RepositoryStore
    let isSearching: Bool

    @Environment(\.aviDensity) private var density

    var body: some View {
        HStack(spacing: 8) {
            Text(isSearching ? "Searched the latest \(store.historyRows.count) commits" : "Latest \(store.historyRows.count) commits")
                .aviLabel(density, color: DS.Palette.textTertiary)
            Spacer()
            OlderHistoryButton(store: store, isSearching: isSearching)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}

/// Shown under the column headers when nothing loaded matches the search.
private struct NoMatchesBanner: View {
    let store: RepositoryStore

    @Environment(\.aviDensity) private var density

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DS.IconScale.sm, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(store.hasOlderHistory
                ? "No match in the latest \(store.historyRows.count) commits"
                : "No commit matches")
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            if store.hasOlderHistory {
                OlderHistoryButton(store: store, isSearching: true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.primary.opacity(0.04))
    }
}

private struct OlderHistoryButton: View {
    let store: RepositoryStore
    let isSearching: Bool

    var body: some View {
        HStack(spacing: 6) {
            if store.isLoadingOlderHistory {
                ProgressView().controlSize(.mini)
            }
            Button(isSearching ? "Search Older Commits" : "Load Older Commits") {
                Task { await store.loadOlderHistory() }
            }
            .controlSize(.small)
            .disabled(store.isLoadingOlderHistory)
            .help("Load \(RepositoryStore.historyOlderStep) more commits into History")
        }
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

    @Environment(\.aviDensity) private var density

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .aviLabel(density)
            Spacer()
            if let trailing {
                Text(trailing)
                    .aviLabel(density, color: DS.Palette.textTertiary)
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
    let graphWidth: CGFloat
    let store: RepositoryStore
    let multiSelectionOIDs: Set<String>
    var searchTerms: [String] = []
    /// Searching, and this commit does not match.
    var isDimmed = false
    /// HEAD reaches this commit: it can be reset to, rebased from, or reverted.
    var isOnHead = false
    var isHead = false
    var laneWidth: CGFloat = 16
    /// Set when author pictures are on.
    var avatarSize: CGFloat?
    var gitLabHost: String?
    var menu: (CommitMenuAction, CommitSummary) -> Void = { _, _ in }
    let checkoutRef: (GitReference) -> Void

    @Environment(\.aviDensity) private var density

    private let maxVisibleBadges = 4

    private static let avatarSpacing: CGFloat = 6

    /// The Author column keeps 130 points for the name and adds the author's
    /// picture beside it, so the header lines up with the rows.
    static func authorWidth(avatarSize: CGFloat?) -> CGFloat {
        130 + (avatarSize.map { $0 + avatarSpacing } ?? 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                HistoryGraphView(
                    row: row,
                    isSelected: isSelected,
                    laneColors: laneColors,
                    laneWidth: laneWidth
                )
                .frame(width: graphWidth, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(visibleBadges) { badge in
                        BadgePill(
                            badge: badge,
                            hasLocalChanges: !store.entries.isEmpty,
                            select: { Task { await store.selectCommit(row.commit) } },
                            checkout: checkoutRef,
                            store: store
                        )
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

                    Text(highlighted(row.commit.subject.isEmpty ? "(no subject)" : row.commit.subject))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .opacity(textOpacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            Group {
                HStack(spacing: Self.avatarSpacing) {
                    if let avatarSize {
                        AuthorAvatar(name: row.commit.authorName, email: row.commit.authorEmail, size: avatarSize, gitLabHost: gitLabHost)
                    }
                    Text(highlighted(row.commit.authorName))
                        .foregroundStyle(.secondary)
                }
                .frame(width: Self.authorWidth(avatarSize: avatarSize), alignment: .leading)
                Text(shortOIDText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .leading)
                Text(CommitDateText.string(for: row.commit.authorDate, style: .short))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)
            }
            .opacity(textOpacity)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: density == .compact ? 24 : 28)
        .background(isSelected ? DS.Palette.rowSelectedSoftFill : Color.clear)
        .contentShape(Rectangle())
        .help(fullMessage)
        .contextMenu {
            commitMenu
            Divider()
            aiContextMenuSection
        }
    }

    /// The commit menu: branch and tag here, rewrite history up to here,
    /// bring this commit elsewhere, and copy it.
    @ViewBuilder
    private var commitMenu: some View {
        let commit = row.commit
        let busy = store.operationState != nil || store.isAIWorking || store.rebaseInProgress
        let head = store.branch.flatMap { $0.isDetached ? nil : "'\($0.name)'" } ?? "HEAD"
        Button("New Branch…") { menu(.newBranch, commit) }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        Button("New Tag…") { menu(.newTag, commit) }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        Divider()
        Menu("Interactive Rebase") {
            Button("Rebase \(head) from Here…") { menu(.interactiveRebase, commit) }
                .disabled(!isOnHead || isHead || busy)
            Button("Edit Commit") { menu(.editCommit, commit) }
                .disabled(!isOnHead || commit.parentOIDs.count > 1 || busy)
        }
        Button("Reset \(head) to Here…") { menu(.reset, commit) }
            .disabled(isHead || busy)
        Divider()
        Button("Checkout Commit…") { menu(.checkout, commit) }
            .disabled(isHead || busy)
        Button("Cherry-pick Commit…") { menu(.cherryPick, commit) }
            .disabled(isOnHead || busy)
        Button("Revert Commit…") { menu(.revert, commit) }
            .disabled(!isOnHead || busy)
        Button("Save as Patch…") { menu(.savePatch, commit) }
        Divider()
        Button("Compare to Local Changes") { menu(.compare, commit) }
        Divider()
        Button("Copy Commit SHA") { menu(.copySHA, commit) }
            .keyboardShortcut("c", modifiers: .command)
        Button("Copy Short SHA") { menu(.copyShortSHA, commit) }
        Button("Copy Subject") { menu(.copySubject, commit) }
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

    /// Searching dims the text of commits that do not match; the graph stays
    /// whole so the lanes still read as lanes.
    private var textOpacity: Double {
        isDimmed && !isSelected ? 0.32 : 1
    }

    private func highlighted(_ text: String) -> AttributedString {
        searchTerms.isEmpty ? AttributedString(text) : HistorySearch.highlighted(text, terms: searchTerms)
    }

    /// The short SHA, with the part a search word matched highlighted.
    private var shortOIDText: AttributedString {
        var text = AttributedString(row.commit.shortOID)
        if let term = searchTerms.first(where: { HistorySearch.isSHAPrefix($0, of: row.commit.oid) }) {
            let end = text.index(text.startIndex, offsetByCharacters: min(term.count, row.commit.shortOID.count))
            text[text.startIndex ..< end].backgroundColor = DS.Palette.searchHighlight
        }
        return text
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
    let hasLocalChanges: Bool
    let select: () -> Void
    let checkout: (GitReference) -> Void
    let store: RepositoryStore

    var body: some View {
        ReferenceActionButton(
            ref: badge.ref,
            hasLocalChanges: hasLocalChanges,
            select: select,
            checkout: checkout,
            pushRemote: store.defaultRemoteName,
            pushTag: { tag in Task { await store.pushTag(name: tag.name) } },
            deleteTag: { tag, remote in Task { await store.deleteTag(named: tag.name, remote: remote) } }
        ) {
            AviBadge(badgeKind, text: label, tint: laneTint)
        }
        .aviTooltip {
            BadgePopover(badge: badge)
        }
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

    /// The color HistoryListView gives the lane this branch starts.
    private var laneTint: Color? {
        badge.ref.kind == .localBranch ? HistoryGraphPalette.color(for: "local:\(badge.ref.name)") : nil
    }

    private var label: String {
        switch badge.ref.kind {
        case .remoteBranch:
            return badge.ref.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? badge.ref.name
        default:
            return badge.ref.name
        }
    }
}

private struct BadgePopover: View {
    let badge: HistoryRefBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Type", typeLabel)
            row("Name", badge.ref.name)
            row("Commit", String(badge.ref.targetOID.prefix(12)))
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
                CommitHeaderView(commit: commit, gitLabHost: store.gitLabHost)
                Divider()
                HSplitView {
                    CommitFileListView(store: store)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)

                    if let file = store.selectedCommitFile {
                        FileDiffView(title: file.displayPath, diff: store.commitDiff, errorMessage: store.commitDiffError) {
                            await store.selectCommitFile(store.selectedCommitFile)
                        }
                        .frame(minWidth: 420)
                    } else if let error = store.commitDiffError {
                        ContentUnavailableView("Unable to Load Commit", systemImage: "exclamationmark.triangle", description: Text(error))
                            .frame(minWidth: 420)
                    } else if store.isCommitLoading {
                        ProgressView().frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
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
    var gitLabHost: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if ConfigStore.shared.config.appearance.authorPictures {
                AuthorAvatar(name: commit.authorName, email: commit.authorEmail, size: 30, gitLabHost: gitLabHost)
                    .padding(.top, 1)
            }
            details
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
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
                    Text(CommitDateText.string(for: commit.authorDate, style: .long))
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
                if store.commitFiles.isEmpty, store.isCommitLoading {
                    ProgressView()
                }
            }
        }
    }

    private var filesSummary: String? {
        let n = store.commitFiles.count
        if n == 0 {
            return nil
        }
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

struct CommitFileRow: View {
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
