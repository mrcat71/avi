import AppKit
import GitKit
import SwiftUI

struct RepositoryView: View {
    let store: RepositoryStore
    /// The window's open repositories, for the tabs.
    let session: WorkspaceSession
    let openRepositoryPicker: () -> Void

    private var selection: RepositorySelection? {
        get { store.workspaceSelection }
        nonmutating set { store.workspaceSelection = newValue }
    }

    @State private var hasAppliedInitialSelection = false
    @State private var showingCreateBranch = false
    @State private var createBranchStartPoint: String? = nil
    @State private var createTagTargetOID: String? = nil
    @State private var showingCommandPalette = false
    @Environment(\.openSettings) private var openSettings

    /// Split into functions so the type checker handles each modifier chain.
    var body: some View {
        divergedPullChoice(sheets(receivingCommands(layout)))
    }

    /// A pull whose branch and upstream both moved asks how to join them.
    private func divergedPullChoice(_ content: some View) -> some View {
        content
            .alert(
                store.divergedPull.map { "\($0.branch) and \($0.upstream) Have Diverged" } ?? "",
                isPresented: Binding(get: { store.divergedPull != nil }, set: {
                    if !$0 {
                        store.divergedPull = nil
                    }
                }),
                presenting: store.divergedPull
            ) { _ in
                Button("Rebase") {
                    Task { await store.reconcileDivergedPull(.rebase) }
                }
                .keyboardShortcut(.defaultAction)
                Button("Merge") {
                    Task { await store.reconcileDivergedPull(.merge) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { diverged in
                Text(DivergedPullText.message(diverged))
            }
    }

    private var layout: some View {
        HSplitView {
            RepositorySidebarView(
                selection: selectionBinding,
                store: store
            )
            .frame(
                minWidth: AppPreferences.minSidebarWidth,
                idealWidth: AppPreferences.sidebarWidth,
                maxWidth: AppPreferences.maxSidebarWidth
            )

            VStack(spacing: 0) {
                RepositoryTabsBar(session: session, openRepositoryPicker: openRepositoryPicker)
                RepositoryActionToolbarView(
                    store: store,
                    openRepositoryPicker: openRepositoryPicker
                )
                Divider()
                // In the layout, not a safe-area inset: the split view ignores
                // insets, so an inset banner covered the tabs and the sidebar.
                if let operation = store.operationState {
                    OperationBanner(store: store, operation: operation)
                } else if let head = store.detachedHead {
                    // A rebase detaches HEAD too; its own banner covers that.
                    DetachedHeadBanner(store: store, head: head)
                }
                if let notice = store.pullRequestNotice {
                    PullRequestBanner(store: store, notice: notice)
                }
                ForEach(store.tagProposals) { proposal in
                    TagProposalBanner(store: store, proposal: proposal)
                }
                if store.isAIWorking {
                    aiWorkBanner
                }
                workspace
            }
            .frame(minWidth: 760)
        }
        .background(AviWorkspaceBackground())
        .navigationTitle(store.root?.lastPathComponent ?? "Avi")
        .observeDensity()
        .task(id: store.id) {
            await store.refresh()
            applyInitialSelectionIfNeeded()
            await autoFetchWhileShown()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.autoFetchIfDue(interval: ConfigStore.shared.config.git.autoFetchInterval) }
        }
        .onChange(of: store.entries.isEmpty) { _, _ in
            applyInitialSelectionIfNeeded()
        }
        .onChange(of: store.stashes) { _, stashes in
            // If the open stash was popped or dropped, fall back to local changes
            // so the workspace doesn't point at a stash that no longer exists.
            if case let .stash(ref)? = selection, !stashes.contains(where: { $0.ref == ref }) {
                selection = .localChanges
            }
        }
    }

    /// Menu-bar and sidebar requests that reach this repository as notifications.
    private func receivingCommands(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .aviCreateBranch)) { notification in
                createBranchStartPoint = notification.object as? String
                showingCreateBranch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviCreateTag)) { notification in
                createTagTargetOID = notification.object as? String
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviNewBranch)) { _ in
                // Like Fork: start from whatever is selected, else from HEAD.
                createBranchStartPoint = selectedStartPoint
                showingCreateBranch = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviNewTag)) { _ in
                createTagTargetOID = selectedTagTarget
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviOpenCommandPalette)) { _ in
                showingCommandPalette = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviOpenAgentSettings)) { _ in
                SettingsNavigation.shared.requested = .agents
                openSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviGoToLocalChanges)) { _ in
                selection = .localChanges
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviGoToAllCommits)) { _ in
                selection = .allCommits
            }
            .onReceive(NotificationCenter.default.publisher(for: .aviToggleHistoryScope)) { _ in
                let next: HistoryFilter.Scope
                switch store.historyFilter.scope {
                case .currentBranch: next = .allBranches
                case .allBranches, .ref: next = .currentBranch
                }
                Task { await store.setHistoryFilter(HistoryFilter(scope: next, hideMerges: store.historyFilter.hideMerges)) }
            }
    }

    private func sheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showingCreateBranch, onDismiss: { createBranchStartPoint = nil }) {
                CreateBranchSheet(store: store, startPoint: createBranchStartPoint)
            }
            .sheet(item: Binding(
                get: { createTagTargetOID.map { CreateTagSheet.Target(oid: $0) } },
                set: { createTagTargetOID = $0?.oid }
            )) { target in
                CreateTagSheet(store: store, targetOID: target.oid)
            }
            .sheet(isPresented: $showingCommandPalette) {
                CommandPalette(
                    commands: CommandRegistry.commands(
                        store: store,
                        setSelection: { selection = $0 },
                        openCreateBranch: { showingCommandPalette = false; showingCreateBranch = true }
                    ),
                    isPresented: $showingCommandPalette
                )
                .padding(.top, 80)
                .background(Color.clear)
            }
            .alert(
                store.pendingCheckout.map { $0.leftBehind == 1 ? "Leave 1 Commit Behind?" : "Leave \($0.leftBehind) Commits Behind?" } ?? "",
                isPresented: Binding(
                    get: { store.pendingCheckout != nil },
                    set: {
                        if !$0 {
                            store.pendingCheckout = nil
                        }
                    }
                ),
                presenting: store.pendingCheckout
            ) { pending in
                Button("Create Branch First…") {
                    createBranchStartPoint = store.detachedHead?.oid
                    showingCreateBranch = true
                }
                Button("Switch Anyway", role: .destructive) {
                    Task { await store.checkoutLeavingCommits(pending) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("HEAD is detached, and \(pending.leftBehind == 1 ? "its last commit is" : "its last \(pending.leftBehind) commits are") on no branch. "
                    + "After switching to \(pending.ref.name), only the reflog keeps \(pending.leftBehind == 1 ? "it" : "them"), for about 30 days. "
                    + "Create a branch to keep \(pending.leftBehind == 1 ? "it" : "them").")
            }
            .alert("Git Error", isPresented: errorPresented) {
                Button("OK", role: .cancel) { store.dismissError() }
            } message: {
                Text(store.errorMessage ?? "")
            }
            .sheet(isPresented: aiRewordPresented) {
                if let preview = store.aiRewordPreview {
                    AIRewordSheet(store: store, preview: preview)
                }
            }
            .sheet(isPresented: aiSplitPresented) {
                if let preview = store.aiSplitPreview {
                    AISplitSheet(store: store, preview: preview)
                }
            }
    }

    private var aiRewordPresented: Binding<Bool> {
        Binding(
            get: { store.aiRewordPreview != nil },
            set: { presented in
                if !presented {
                    store.dismissAIRewordPreview()
                }
            }
        )
    }

    private var aiSplitPresented: Binding<Bool> {
        Binding(
            get: { store.aiSplitPreview != nil && !store.isAIWorking },
            set: { presented in
                if !presented {
                    store.dismissAISplitPreview()
                }
            }
        )
    }

    /// Shown while an AI job runs, instead of a sheet that blocked the window:
    /// you can switch views, tabs, and repositories until the result is ready.
    private var aiWorkBanner: some View {
        HStack(spacing: 10) {
            AviWorkingIndicator(title: store.aiWorkDescription.isEmpty ? "The AI is working…" : store.aiWorkDescription)
            Spacer()
            Button("Cancel") {
                store.cancelCommitMessageGeneration()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Glass.edgeStroke).frame(height: 0.6)
        }
    }

    /// The ref or commit selected in the sidebar or History, as a start point
    /// for a new branch. Nil starts from HEAD.
    private var selectedStartPoint: String? {
        switch selection ?? .allCommits {
        case .branch(let name), .remoteBranch(let name), .tag(let name):
            return name
        case .allCommits:
            return store.selectedCommitOID
        case .localChanges, .stash:
            return nil
        }
    }

    /// The commit a new tag goes on: the selected ref's or commit, else HEAD.
    private var selectedTagTarget: String? {
        switch selection ?? .allCommits {
        case .branch(let name):
            return store.refs.localBranches.first { $0.name == name }?.oid
        case .remoteBranch(let name):
            return store.refs.remoteBranches.first { $0.name == name }?.oid
        case .tag(let name):
            return store.refs.tags.first { $0.name == name }?.targetOID
        case .allCommits:
            return store.selectedCommitOID ?? store.branch?.oid
        case .localChanges, .stash:
            return store.branch?.oid
        }
    }

    private var selectionBinding: Binding<RepositorySelection> {
        Binding(
            get: { selection ?? .allCommits },
            set: { newValue in
                selection = newValue
                if let persisted = newValue.persisted {
                    AppPreferences.lastSelectedView = persisted
                }
            }
        )
    }

    @ViewBuilder
    private var workspace: some View {
        switch selection ?? .allCommits {
        case .localChanges:
            LocalChangesWorkspaceView(
                store: store,
                switchToAllCommits: { selection = .allCommits }
            )
        case let .stash(ref):
            StashContentsWorkspaceView(store: store, ref: ref)
        case .allCommits, .branch, .remoteBranch, .tag:
            HistoryWorkspaceView(store: store)
        }
    }

    /// Fetch when this repository comes into view, then check once a minute
    /// until it leaves; coming back to Avi checks too. Each check fetches only
    /// while Avi is in front and the last fetch is older than
    /// Settings > Git > Auto-fetch interval.
    private func autoFetchWhileShown() async {
        while !Task.isCancelled {
            if NSApp.isActive {
                await store.autoFetchIfDue(interval: ConfigStore.shared.config.git.autoFetchInterval)
            }
            try? await Task.safeSleep(for: .seconds(60))
        }
    }

    private func applyInitialSelectionIfNeeded() {
        guard !hasAppliedInitialSelection else { return }
        guard selection == nil else { hasAppliedInitialSelection = true; return }
        guard !store.isLoading, store.root != nil else { return }

        hasAppliedInitialSelection = true

        // An agent's proposal waits in Changes; show it rather than the last view.
        if store.hasUnseenProposal {
            selection = .localChanges
            return
        }

        if let saved = AppPreferences.lastSelectedView {
            switch saved {
            case .localChanges where !store.entries.isEmpty:
                selection = .localChanges
                return
            case .allCommits:
                selection = .allCommits
                return
            default:
                break
            }
        }

        selection = store.entries.isEmpty ? .allCommits : .localChanges
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: {
                presented in if !presented {
                    store.dismissError()
                }
            }
        )
    }
}

/// A tag an agent proposed for a commit that already exists. It goes on its
/// own to the remote only once the remote has the commit; until then, Push
/// sends the commit and the tag together.
struct TagProposalBanner: View {
    let store: RepositoryStore
    let proposal: TagProposal

    @State private var remoteHasCommit = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(proposal.source.displayName) proposes the tag \(proposal.tag.name)")
                    .font(.system(size: 12, weight: .semibold))
                    .textSelection(.enabled)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Create Tag") {
                Task { await store.acceptTagProposal(proposal.id) }
            }
            if remoteHasCommit, let remote {
                Button("Create and Push to \(remote)") {
                    Task { await store.acceptTagProposal(proposal.id, pushingTo: remote) }
                }
            }
            Button {
                store.dismissTagProposal(proposal.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Glass.edgeStroke).frame(height: 0.6)
        }
        .task(id: RemoteCheck(commit: proposal.commit, remote: remote, tips: store.refs.remoteBranches.map(\.targetOID))) {
            guard let remote else {
                remoteHasCommit = false
                return
            }
            remoteHasCommit = await store.remoteHasCommit(proposal.commit, remote: remote)
        }
    }

    private var remote: String? {
        store.defaultRemoteName
    }

    private var detail: String {
        var parts = ["On \(proposal.commit.prefix(7)) \(proposal.subject)"]
        if let message = proposal.tag.message {
            parts.append("annotated: \(message)")
        }
        if let remote, !remoteHasCommit {
            parts.append("\(remote) does not have this commit yet, so Push sends it and the tag together")
        }
        return parts.joined(separator: " · ")
    }

    /// Checks again whenever a fetch or push moves the remote's branches.
    private struct RemoteCheck: Hashable {
        let commit: String
        let remote: String?
        let tips: [String]
    }
}

/// What the last push or pull request did: the request it created with a
/// link, one already open, the form opened in the browser, a failure with
/// the browser as a way out, or the offer after a branch's first push.
private struct PullRequestBanner: View {
    let store: RepositoryStore
    let notice: PullRequestNotice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .textSelection(.enabled)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            actions
            Button {
                store.pullRequestNotice = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Glass.edgeStroke).frame(height: 0.6)
        }
    }

    private var noun: String {
        notice.forge.requestNoun.lowercased()
    }

    private var title: String {
        switch notice.kind {
        case .created(let info): return "Created \(noun) \(notice.forge.reference(info.number))"
        case .existing(let info): return "\(notice.forge.requestNoun) \(notice.forge.reference(info.number)) is already open"
        case .openedInBrowser: return "The \(noun) form is open in your browser"
        case .failed: return "Could not create the \(noun)"
        case .pushedNewBranch(let branch, let remote): return "Pushed \(branch) to \(remote)"
        }
    }

    private var detail: String? {
        switch notice.kind {
        case .created(let info), .existing(let info): return info.title
        case .openedInBrowser: return "Sign in to gh or glab, or add a token in Settings, and Avi creates it for you."
        case .failed(let message, _): return message
        case .pushedNewBranch: return nil
        }
    }

    private var symbol: String {
        switch notice.kind {
        case .created, .pushedNewBranch: return "checkmark.circle"
        case .existing, .openedInBrowser: return "arrow.triangle.pull"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .created, .pushedNewBranch: return .green
        case .existing, .openedInBrowser: return .secondary
        case .failed: return .orange
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch notice.kind {
        case .created(let info):
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info.url.absoluteString, forType: .string)
            }
            Button("Open") { NSWorkspace.shared.open(info.url) }
        case .existing(let info):
            Button("Open") { NSWorkspace.shared.open(info.url) }
        case .openedInBrowser:
            EmptyView()
        case .failed(_, let fallback):
            if let fallback {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(fallback)
                    store.pullRequestNotice = nil
                }
            }
        case .pushedNewBranch(let branch, _):
            Button("Create \(notice.forge.requestNoun)…") {
                store.pullRequestNotice = nil
                store.pushSheetRequest = PushSheetRequest(branch: branch, pullRequest: true)
            }
        }
    }
}

/// HEAD is detached, as agents often leave it: where it points, whether
/// commits here are on no branch, and the ways to give them one.
private struct DetachedHeadBanner: View {
    let store: RepositoryStore
    let head: DetachedHead

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(stranded ? .orange : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("HEAD is detached at \(head.shortOID)")
                        .font(.system(size: 12, weight: .semibold))
                        .textSelection(.enabled)
                    if !head.subject.isEmpty {
                        Text(head.subject)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(stranded ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let branch = switchTarget {
                Button("Switch to '\(branch.name)'") {
                    Task { await store.checkout(branch) }
                }
                .help("\(branch.name) is at this commit, so switching loses nothing")
            }
            Button("Create Branch Here…") {
                NotificationCenter.default.post(name: .aviCreateBranch, object: head.oid)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Glass.edgeStroke).frame(height: 0.6)
        }
    }

    private var stranded: Bool {
        (head.unreferencedCount ?? 0) > 0
    }

    /// A branch at this commit that no other worktree holds.
    private var switchTarget: GitReference? {
        head.branchesHere.lazy
            .filter { store.branchHolders[$0] == nil }
            .compactMap { name in store.refs.localBranches.first { $0.name == name } }
            .first
    }

    private var detail: String {
        if let count = head.unreferencedCount, count > 0 {
            return "\(count == 1 ? "1 commit here is" : "\(count) commits here are") on no branch. "
                + "Create a branch to keep \(count == 1 ? "it" : "them") before switching away."
        }
        if !head.branchesHere.isEmpty {
            let names = head.branchesHere.map { "'\($0)'" }.joined(separator: ", ")
            return "Same commit as \(names). New commits made here would be on no branch."
        }
        return "New commits made here would be on no branch."
    }
}

/// What the diverged-pull dialog says.
enum DivergedPullText {
    static func message(_ diverged: DivergedPull) -> String {
        let mine = diverged.ahead == 1 ? "1 commit" : "\(diverged.ahead) commits"
        let theirs = diverged.behind == 1 ? "1 commit" : "\(diverged.behind) commits"
        return "\(diverged.branch) has \(mine) that \(diverged.upstream) does not, and \(diverged.upstream) has \(theirs) that \(diverged.branch) does not.\n\n"
            + "Rebase replays your \(mine) on top of \(diverged.upstream), keeping the history in one line. "
            + "Merge joins the two with a merge commit. A conflict stops either one for you to resolve.\n\n"
            + "To skip this question, set pull.rebase in your Git config."
    }
}

/// A merge or rebase that stopped: what Git needs from you, and the ways out.
private struct OperationBanner: View {
    let store: RepositoryStore
    let operation: GitOperationState

    @State private var showingDetails = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(guidance)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let notice = store.operationNotice {
                Button {
                    showingDetails.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("What Git said")
                .accessibilityLabel("What Git said")
                .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                    ScrollView {
                        Text(notice)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(width: 460, height: 220)
                }
            }
            switch operation {
            case .rebase:
                Button("Continue") {
                    Task { await store.continueRebase() }
                }
                .disabled(conflictCount > 0)
                .help(conflictCount > 0 ? "Resolve every conflicted file and mark it resolved first" : "git rebase --continue")
                Button("Skip Commit") {
                    Task { await store.skipRebaseCommit() }
                }
                .help("Drop the commit the rebase stopped at and go on")
                Button("Abort Rebase", role: .destructive) {
                    Task { await store.abortOperation() }
                }
            case .merge:
                Button("Abort Merge", role: .destructive) {
                    Task { await store.abortOperation() }
                }
            case .cherryPick, .revert:
                Button("Continue") {
                    Task { await store.continueOperation() }
                }
                .disabled(conflictCount > 0)
                .help(conflictCount > 0 ? "Resolve every conflicted file and mark it resolved first" : "git \(verb) --continue")
                Button("Skip Commit") {
                    Task { await store.skipOperation() }
                }
                .help("Leave this commit out and finish")
                Button(operation == .cherryPick ? "Abort Cherry-pick" : "Abort Revert", role: .destructive) {
                    Task { await store.abortOperation() }
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Glass.edgeStroke).frame(height: 0.6)
        }
    }

    private var conflictCount: Int {
        store.entries.filter(\.isConflicted).count
    }

    private var symbol: String {
        switch operation {
        case .merge: return "arrow.triangle.merge"
        case .rebase: return "arrow.triangle.2.circlepath"
        case .cherryPick: return "arrow.right.doc.on.clipboard"
        case .revert: return "arrow.uturn.backward"
        }
    }

    private var verb: String {
        operation == .cherryPick ? "cherry-pick" : "revert"
    }

    private var title: String {
        switch operation {
        case .merge: return "Merge in progress"
        case .rebase: return conflictCount > 0 ? "Rebase stopped on a conflict" : "Rebase paused"
        case .cherryPick: return conflictCount > 0 ? "Cherry-pick stopped on a conflict" : "Cherry-pick paused"
        case .revert: return conflictCount > 0 ? "Revert stopped on a conflict" : "Revert paused"
        }
    }

    private var guidance: String {
        let files = conflictCount == 1 ? "the conflicted file" : "the \(conflictCount) conflicted files"
        switch operation {
        case .merge:
            return conflictCount > 0
                ? "Resolve \(files) in Changes and mark them resolved, then commit to finish the merge."
                : "Conflicts are resolved. Commit to finish the merge, or abort it."
        case .rebase:
            return conflictCount > 0
                ? "Resolve \(files) in Changes and mark them resolved, then Continue."
                : "Amend the commit or stage your resolution if you need to, then Continue."
        case .cherryPick, .revert:
            return conflictCount > 0
                ? "Resolve \(files) in Changes and mark them resolved, then Continue to commit."
                : "Stage your resolution, then Continue to commit, or Skip if nothing is left to apply."
        }
    }
}

enum RepositorySelection: Hashable {
    case localChanges
    case allCommits
    case branch(name: String)
    case remoteBranch(name: String)
    case tag(name: String)
    case stash(ref: String)

    var persisted: PersistedView? {
        switch self {
        case .localChanges: return .localChanges
        case .allCommits, .branch, .remoteBranch, .tag: return .allCommits
        case .stash: return nil
        }
    }
}

private struct RepositoryActionToolbarView: View {
    let store: RepositoryStore
    let openRepositoryPicker: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ToolbarPillButton(title: "Open", systemImage: "folder", action: openRepositoryPicker)

            toolbarDivider

            ToolbarPillButton(
                title: "Fetch",
                systemImage: "arrow.down",
                helpText: fetchHelp
            ) {
                Task { await store.fetch(remote: nil) }
            }
            .disabled(store.remotes.isEmpty || store.isRemoteOperationRunning)

            ToolbarPillButton(
                title: "Pull",
                systemImage: "arrow.down.to.line",
                badge: behindBadge,
                badgeTint: .blue,
                helpText: pullHelp
            ) {
                Task { await store.pull() }
            }
            .disabled(!canPullPush)

            ToolbarPillButton(
                title: "Push",
                systemImage: "arrow.up.to.line",
                badge: aheadBadge,
                badgeTint: .green,
                helpText: pushHelp
            ) {
                store.pushSheetRequest = PushSheetRequest(branch: nil, pullRequest: false)
            }
            .disabled(!canPullPush)

            if let providerURL = providerWebURL {
                toolbarDivider
                ToolbarPillButton(
                    title: providerName,
                    systemImage: "safari",
                    helpText: "Open repository on \(providerName) in browser"
                ) {
                    NSWorkspace.shared.open(providerURL)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Glass.edgeStroke)
                .frame(height: 0.6)
        }
        .sheet(item: Binding(get: { store.pushSheetRequest }, set: { store.pushSheetRequest = $0 })) { request in
            PushSheet(
                store: store,
                branchName: request.branch,
                includesPullRequest: request.pullRequest,
                dismiss: { store.pushSheetRequest = nil }
            )
        }
        // A remote on an unrecognized host may be a self-hosted GitLab that
        // `glab` knows; its button and merge requests appear once it loads.
        .task(id: store.remotes.compactMap(\.fetchURL)) {
            if providerHint == .unknown, !store.remotes.isEmpty {
                await KnownProviderHosts.shared.loadIfNeeded()
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.isLoading || store.isRemoteOperationRunning || store.isAutoFetching {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .padding(.top, 4)
                    .padding(.trailing, 4)
                    .opacity(0.75)
            }
        }
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var canPullPush: Bool {
        !store.isRemoteOperationRunning && store.branch?.isUnborn == false
    }

    private var aheadBadge: String? {
        guard let ahead = store.branch?.ahead, ahead > 0 else { return nil }
        return "\(ahead)"
    }

    private var behindBadge: String? {
        guard let behind = store.branch?.behind, behind > 0 else { return nil }
        return "\(behind)"
    }

    private var fetchHelp: String {
        store.remotes.isEmpty ? "No remotes configured" : "Fetch from all remotes"
    }

    private var pullHelp: String {
        guard let branch = store.branch else { return "Pull" }
        let name = branch.name ?? "current branch"
        if branch.isUnborn {
            return "No commits yet"
        }
        guard let upstream = branch.upstream else { return "Set upstream for \(name) first" }
        if branch.behind > 0, branch.ahead > 0 {
            return "Pull \(branch.behind) commit\(branch.behind == 1 ? "" : "s") from \(upstream). \(name) has \(branch.ahead) of its own, "
                + "so Avi asks whether to rebase or merge them, unless Git's pull.rebase says"
        }
        if branch.behind > 0 {
            return "Pull \(branch.behind) commit\(branch.behind == 1 ? "" : "s") from \(upstream) into \(name)"
        }
        return "\(name) is up to date with \(upstream)"
    }

    private var pushHelp: String {
        guard let branch = store.branch else { return "Push" }
        let name = branch.name ?? "current branch"
        if branch.isUnborn {
            return "No commits yet"
        }
        guard let upstream = branch.upstream else { return "Push \(name) and set upstream to origin/\(name)" }
        // The Push sheet writes the branch under its own name, to the remote it
        // preselects, so an upstream with another name, such as the origin/main
        // the branch started from, is replaced rather than pushed to.
        let upstreamRemote = upstream.split(separator: "/", maxSplits: 1).first.map(String.init)
        let remote = store.remotes.contains { $0.name == upstreamRemote } ? upstreamRemote : store.remotes.first?.name
        let target = "\(remote ?? "origin")/\(name)"
        if upstream != target {
            return "Push \(name) to \(target) and track it instead of \(upstream)"
        }
        if branch.ahead > 0 {
            return "Push \(branch.ahead) commit\(branch.ahead == 1 ? "" : "s") from \(name) to \(upstream)"
        }
        return "\(name) is in sync with \(upstream)"
    }

    private var providerHint: ProviderHint {
        guard let remote = store.remotes.first(where: { $0.name == "origin" }) ?? store.remotes.first else {
            return .unknown
        }
        return RemoteURLParser.hint(from: remote, knownHosts: KnownProviderHosts.shared.hosts)
    }

    private var providerName: String {
        switch providerHint {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .unknown: return ""
        }
    }

    private var providerWebURL: URL? {
        switch providerHint {
        case .github(let owner, let repo):
            return GitHubAPI.repoWebURL(owner: owner, repo: repo)
        case .gitlab(let host, let projectPath):
            return GitLabAPI.projectWebURL(host: host, projectPath: projectPath)
        case .unknown:
            return nil
        }
    }
}

struct ToolbarPillButton: View {
    let title: String
    let systemImage: String
    var badge: String?
    var badgeTint: Color = .accentColor
    var helpText: String?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: DS.IconScale.lg, weight: .medium))
                Text(title)
                    .font(.system(size: DS.IconScale.lg, weight: .medium))
                if let badge {
                    Text(badge)
                        .font(.system(size: DS.IconScale.sm, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, DS.Spacing.sm + 1)
                        .frame(minWidth: 18, minHeight: 14)
                        .background(
                            Capsule().fill(badgeTint.opacity(0.20))
                        )
                        .foregroundStyle(badgeTint)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .frame(height: 28)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(isHovering && isEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.clear))
                    if isHovering, isEnabled {
                        Capsule(style: .continuous)
                            .fill(Glass.hoverTint())
                    }
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isHovering && isEnabled ? Glass.edgeStroke : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isHovering && isEnabled ? 1.0 : 1.0)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .animation(Glass.Motion.snappy, value: isHovering)
        .help(helpText ?? title)
        .accessibilityLabel(helpText ?? title)
    }
}

struct HistoryWorkspaceView: View {
    let store: RepositoryStore

    var body: some View {
        VSplitView {
            HistoryListView(store: store, refBadgesByOID: refBadgesByOID)
                .frame(maxWidth: .infinity, minHeight: 180, idealHeight: 320)
                .aviPane()

            CommitDetailView(store: store)
                .frame(maxWidth: .infinity, minHeight: 320, idealHeight: 380)
                .aviPane()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refBadgesByOID: [String: [HistoryRefBadge]] {
        var badges: [String: [HistoryRefBadge]] = [:]

        for ref in store.refs.localBranches {
            badges[ref.oid, default: []].append(HistoryRefBadge(label: ref.name, ref: ref))
        }
        for ref in store.refs.remoteBranches {
            badges[ref.oid, default: []].append(HistoryRefBadge(label: ref.name, ref: ref))
        }
        for ref in store.refs.tags {
            badges[ref.targetOID, default: []].append(HistoryRefBadge(label: ref.name, ref: ref))
        }

        return badges
    }
}

struct LocalChangesWorkspaceView: View {
    let store: RepositoryStore
    let switchToAllCommits: () -> Void

    @AppStorage("avi.commitPanelHeight") private var commitPanelHeight: Double = 220

    var body: some View {
        conflictDialogs(workspace)
    }

    /// Confirmations for resolving conflicts, from the list or the resolver.
    private func conflictDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(
                store.pendingSideChoice.map(SideChoiceText.init)?.title ?? "",
                isPresented: Binding(get: { store.pendingSideChoice != nil }, set: {
                    if !$0 {
                        store.pendingSideChoice = nil
                    }
                }),
                titleVisibility: .visible,
                presenting: store.pendingSideChoice
            ) { choice in
                Button(SideChoiceText(choice).button, role: .destructive) {
                    Task { await store.resolveConflicts(choice.files, taking: choice.side) }
                }
            } message: { choice in
                Text(SideChoiceText(choice).message)
            }
            .alert(
                store.pendingResolve.map { $0.withMarkers.count == 1 ? "\($0.withMarkers[0]) Still Has Conflict Markers" : "\($0.withMarkers.count) Files Still Have Conflict Markers" } ?? "",
                isPresented: Binding(get: { store.pendingResolve != nil }, set: {
                    if !$0 {
                        store.pendingResolve = nil
                    }
                }),
                presenting: store.pendingResolve
            ) { pending in
                Button("Mark as Resolved Anyway", role: .destructive) {
                    Task { await store.markResolved(pending.files, force: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text((pending.withMarkers.count > 1 ? pending.withMarkers.joined(separator: "\n") + "\n\n" : "")
                    + "The <<<<<<< and >>>>>>> lines would be committed as they are. Resolve each conflict first, unless the file really contains them.")
            }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            LocalChangesStatusBar(store: store)
            Divider()
            HSplitView {
                ChangeListView(store: store, switchToAllCommits: switchToAllCommits)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 520)
                    .aviPane()

                // The commit panel keeps the height you gave it whatever it
                // shows: AI results and planned commits scroll inside it.
                StableVSplit(bottomHeight: $commitPanelHeight, minTopHeight: 240, minBottomHeight: 190) {
                    DiffDetailView(store: store)
                        .aviPane()
                } bottom: {
                    Group {
                        // The composer edits whichever commit of the stack is selected.
                        if store.composerDraft != nil {
                            CommitPlanComposerView(store: store)
                        } else {
                            CommitPanelView(store: store)
                        }
                    }
                    .aviPane()
                }
                .frame(minWidth: 460)
            }
        }
        .onAppear(perform: markSeenIfFrontmost)
        .onChange(of: store.hasUnseenProposal) { _, _ in
            markSeenIfFrontmost()
        }
        .sheet(item: Binding(get: { store.revisionRequest }, set: { store.revisionRequest = $0 })) { request in
            PlanRevisionSheet(store: store, request: request)
        }
        .sheet(item: Binding(get: { store.tagEditRequest }, set: { store.tagEditRequest = $0 })) { request in
            CommitTagSheet(store: store, request: request)
        }
        .sheet(item: Binding(get: { store.fileStashRequest }, set: { store.fileStashRequest = $0 })) { request in
            StashFilesSheet(store: store, request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            markSeenIfFrontmost()
        }
    }

    /// You are looking at this repository's changes, so whatever an agent sent
    /// here is no longer news.
    private func markSeenIfFrontmost() {
        guard store.hasUnseenProposal, NSApp.isActive else { return }
        store.hasUnseenProposal = false
    }
}

private struct LocalChangesStatusBar: View {
    let store: RepositoryStore

    @Environment(\.aviDensity) private var density

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .background(Circle().fill(statusColor.opacity(0.25)).frame(width: 12, height: 12))
                Text(statusLabel)
                    .aviLabel(density, color: DS.Palette.textPrimary)
            }

            // Ref names keep their case: monospaced, not uppercased.
            if let branchName = store.branch?.name {
                Text("·")
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branchName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }

            if let upstream = store.branch?.upstream {
                Text("→")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("tracking")
                Text(upstream)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 5) {
                if store.autoFetchFailure != nil, !store.isAutoFetching {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10))
                }
                Text(fetchedLabel)
                    .aviLabel(density, color: DS.Palette.textTertiary)
            }
            .foregroundStyle(.tertiary)
            .help(fetchedTooltip)

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Glass.edgeStroke)
                .frame(height: 0.6)
        }
    }

    private var statusLabel: String {
        if store.branch?.isDetached == true {
            return "detached"
        }
        let n = store.entries.count
        if n == 0 {
            return "clean"
        }
        return n == 1 ? "1 change" : "\(n) changes"
    }

    private var statusColor: Color {
        if store.branch?.isDetached == true {
            return .red
        }
        if store.entries.isEmpty {
            return .green
        }
        return .orange
    }

    private var fetchedLabel: String {
        if store.isAutoFetching {
            return "fetching…"
        }
        if store.autoFetchFailure != nil {
            return "fetch failed"
        }
        guard let last = store.lastFetched else { return "never fetched" }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed < 30 {
            return "fetched just now"
        }
        if elapsed < 60 * 60 {
            return "fetched \(Int(elapsed / 60)) min ago"
        }
        if elapsed < 60 * 60 * 24 {
            return "fetched \(Int(elapsed / 3600)) h ago"
        }
        if elapsed < 60 * 60 * 24 * 7 {
            return "fetched \(Int(elapsed / 86400)) d ago"
        }
        let formatter = DateFormatter()
        formatter.locale = AviLocale.display
        formatter.dateStyle = .medium
        return "fetched \(formatter.string(from: last))"
    }

    private var fetchedTooltip: String {
        let last = store.lastFetched?.formatted(.dateTime.year().month().day().hour().minute().second().locale(AviLocale.display))
        guard let failure = store.autoFetchFailure else {
            return last ?? "No fetch has been recorded for this repository."
        }
        let when = failure.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AviLocale.display))
        return "The automatic fetch at \(when) failed:\n\(failure.message)\n\nLast fetch: \(last ?? "none recorded")"
    }
}

private struct AviWorkspaceBackground: View {
    var body: some View {
        DS.Palette.surface.ignoresSafeArea()
    }
}

extension View {
    func aviPane() -> some View {
        background(DS.Palette.surfaceRaised)
    }
}

struct BranchSwitcherPopover: View {
    let store: RepositoryStore
    @Binding var isPresented: Bool

    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Switch to branch", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color.primary.opacity(0.04))
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if !filteredLocal.isEmpty {
                        sectionHeader("Local")
                        ForEach(filteredLocal) { ref in
                            BranchSwitcherRow(
                                ref: ref,
                                isCurrent: ref.isCurrent,
                                select: { selectRef(ref) }
                            )
                        }
                    }
                    if !filteredRemote.isEmpty {
                        sectionHeader("Remote")
                        ForEach(filteredRemote) { ref in
                            BranchSwitcherRow(
                                ref: ref,
                                isCurrent: false,
                                select: { selectRef(ref) }
                            )
                        }
                    }
                    if filteredLocal.isEmpty, filteredRemote.isEmpty {
                        Text("No matching branches")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)

            Divider()

            HStack(spacing: 6) {
                Button {
                    isPresented = false
                    NotificationCenter.default.post(name: .aviCreateBranch, object: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Branch")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private var filteredLocal: [GitReference] {
        let sorted = store.refs.localBranches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return filtered(sorted)
    }

    private var filteredRemote: [GitReference] {
        filtered(store.refs.remoteBranches)
    }

    private func filtered(_ refs: [GitReference]) -> [GitReference] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return refs }
        return refs.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private func selectRef(_ ref: GitReference) {
        if !ref.isCurrent {
            Task { await store.checkout(ref) }
        }
        isPresented = false
    }
}

private struct BranchSwitcherRow: View {
    let ref: GitReference
    let isCurrent: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                Image(systemName: ref.kind == .tag ? "tag.fill" : (ref.kind == .remoteBranch ? "network" : "arrow.triangle.branch"))
                    .font(.system(size: 10, weight: isCurrent ? .bold : .regular))
                    .frame(width: 14)
                    .foregroundStyle(isCurrent ? Color.accentColor : ref.kind == .remoteBranch ? .purple : .blue)

                Text(displayName)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var displayName: String {
        if ref.kind == .remoteBranch {
            return ref.name
        }
        return ref.name
    }
}

/// Commit IDs read better short; ref names stay as they are.
enum RefNameDisplay {
    static func short(_ name: String) -> String {
        let isOID = (name.count == 40 || name.count == 64) && name.allSatisfy(\.isHexDigit)
        return isOID ? String(name.prefix(8)) : name
    }
}

struct CreateBranchSheet: View {
    let store: RepositoryStore
    var startPoint: String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var checkout = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Branch")
                .font(.system(size: 14, weight: .semibold))

            if let startPoint {
                Text("From \(RefNameDisplay.short(startPoint))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let current = store.branch?.name {
                Text("From \(current)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: sanitizedName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            Toggle("Check out after creating", isOn: $checkout)
                .controlSize(.small)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func create() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        Task {
            await store.createBranch(named: cleaned, startPoint: startPoint, checkout: checkout)
            dismiss()
        }
    }

    private var sanitizedName: Binding<String> {
        Binding(
            get: { name },
            set: { newValue in
                name = newValue.replacingOccurrences(of: " ", with: "-")
            }
        )
    }
}

struct CreateTagSheet: View {
    struct Target: Identifiable, Equatable {
        let oid: String
        var id: String {
            oid
        }
    }

    let store: RepositoryStore
    let targetOID: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message = ""
    @State private var pushTag = true
    /// Whether the remote has the commit; nil until checked. The tag goes
    /// along with a push only after its commit is there.
    @State private var remoteHasCommit: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Tag")
                .font(.system(size: 14, weight: .semibold))

            Text("At \(String(targetOID.prefix(7)))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            TextField("Name (e.g. v1.2.3)", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            VStack(alignment: .leading, spacing: 4) {
                Text("Message (optional)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .frame(minHeight: 60, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                Text(message.isEmpty ? "Lightweight tag" : "Annotated tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if let remote = store.defaultRemoteName {
                if remoteHasCommit == false {
                    Text("\(remote) does not have this commit yet, so the tag stays here for now. Push sends the commit and the tag together.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Toggle("Push tag to \(remote) after creating", isOn: $pushTag)
                        .controlSize(.small)
                        .disabled(remoteHasCommit == nil)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
        .task {
            guard let remote = store.defaultRemoteName else { return }
            remoteHasCommit = await store.remoteHasCommit(targetOID, remote: remote)
        }
    }

    private func create() {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }
        let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let pushRemote = pushTag && remoteHasCommit == true ? store.defaultRemoteName : nil
        Task {
            await store.createTag(
                name: cleanedName,
                targetOID: targetOID,
                message: cleanedMessage.isEmpty ? nil : cleanedMessage
            )
            if let pushRemote, store.refs.tags.contains(where: { $0.name == cleanedName }) {
                await store.pushTag(name: cleanedName, remote: pushRemote)
            }
            dismiss()
        }
    }
}
