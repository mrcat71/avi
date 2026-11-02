import AppKit
import GitKit
import SwiftUI

/// What the local branch menu asks the sidebar to do.
enum BranchMenuAction: Equatable {
    case checkout
    case openHolder
    case checkoutAsWorktree
    case fastForward
    case push
    case createPullRequest
    case merge
    case rebase
    case interactiveRebase
    case newBranch
    case newTag
    case track(String)
    case trackOther
    case stopTracking
    case rename
    case delete
    case copyName
}

/// The right-click menu of a local branch, laid out like Fork's: switching,
/// syncing with the remote, combining with the current branch, creating refs,
/// managing the branch, copying its name.
struct LocalBranchMenu: View {
    let ref: GitReference
    let store: RepositoryStore
    /// Worktree that has this branch checked out, if not this one.
    let heldBy: Worktree?
    let perform: (BranchMenuAction) -> Void

    var body: some View {
        let current = store.branch?.name
        let remote = store.pushRemoteName(for: ref.name)

        if let heldBy {
            Button("Checked Out in \(heldBy.path.lastPathComponent)") { perform(.openHolder) }
        } else {
            Button("Checkout…") { perform(.checkout) }
                .disabled(ref.isCurrent)
        }
        Button("Checkout as Worktree…") { perform(.checkoutAsWorktree) }
            .disabled(ref.isCurrent || heldBy != nil)

        Divider()

        if let upstream = ref.upstream, !ref.isUpstreamGone {
            Button("Fast-Forward to '\(upstream)'") { perform(.fastForward) }
                .disabled(!store.canFastForward(ref))
        }
        Button(remote.map { "Push to '\($0)'…" } ?? "Push…") { perform(.push) }
            .disabled(remote == nil)
        Button(pullRequestTitle(remote: remote)) { perform(.createPullRequest) }
            .disabled(remote == nil || pullRequestKind == nil)

        Divider()

        if let current, !ref.isCurrent {
            Button("Merge into '\(current)'…") { perform(.merge) }
            Button("Rebase on '\(ref.name)'…") { perform(.rebase) }
            Button("Interactively Rebase on '\(ref.name)'…") { perform(.interactiveRebase) }
            Divider()
        }

        Button("New Branch…") { perform(.newBranch) }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        Button("New Tag…") { perform(.newTag) }
            .keyboardShortcut("g", modifiers: [.command, .shift])

        Divider()

        trackingMenu
        Button("Rename…") { perform(.rename) }
        Button("Delete…", role: .destructive) { perform(.delete) }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(ref.isCurrent)

        Divider()

        Button("Copy Branch Name") { perform(.copyName) }
            .keyboardShortcut("c", modifiers: .command)
    }

    private var trackingMenu: some View {
        let candidates = store.trackingCandidates(for: ref)
        return Menu("Tracking") {
            ForEach(candidates, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { ref.upstream == name },
                    set: { perform($0 ? .track(name) : .stopTracking) }
                ))
            }
            if !candidates.isEmpty {
                Divider()
            }
            Button("Other Remote Branch…") { perform(.trackOther) }
            Button("Stop Tracking") { perform(.stopTracking) }
                .disabled(ref.upstream == nil)
        }
    }

    private enum PullRequestKind {
        case pullRequest
        case mergeRequest
    }

    private var pullRequestKind: PullRequestKind? {
        switch store.pullRequestProvider(for: ref.name) {
        case .github: return .pullRequest
        case .gitlab: return .mergeRequest
        case .unknown: return nil
        }
    }

    private func pullRequestTitle(remote: String?) -> String {
        let noun = pullRequestKind == .mergeRequest ? "Merge Request" : "Pull Request"
        guard let remote else { return "Create \(noun)" }
        return "Create \(noun) on '\(remote)'"
    }
}

/// Sheets the branch menu opens.
enum BranchSheet: Identifiable {
    case worktree(GitReference)
    case push(GitReference)
    /// The Push sheet with "Create pull request" ticked.
    case pullRequest(GitReference)
    case merge(GitReference)
    case rebase(GitReference)
    case interactiveRebase(GitReference)
    case delete(GitReference)

    var id: String {
        switch self {
        case .worktree(let ref): return "worktree:" + ref.fullName
        case .push(let ref): return "push:" + ref.fullName
        case .pullRequest(let ref): return "pull-request:" + ref.fullName
        case .merge(let ref): return "merge:" + ref.fullName
        case .rebase(let ref): return "rebase:" + ref.fullName
        case .interactiveRebase(let ref): return "interactive:" + ref.fullName
        case .delete(let ref): return "delete:" + ref.fullName
        }
    }
}

/// Shared frame for the branch sheets: the popup header with the branch, an
/// explanation, the options, then Cancel and the action.
private struct BranchSheetLayout<Content: View>: View {
    let symbol: String
    var tint: Color = DS.Palette.accent
    let title: String
    let subtitle: String
    let summary: String
    let actionTitle: String
    var actionRole: ButtonRole?
    var actionEnabled = true
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AviPopup(symbol: symbol, tint: tint, title: title, subtitle: subtitle, width: 460) {
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .keyboardShortcut(.cancelAction)
            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        let button = Button(actionTitle, role: actionRole) {
            dismiss()
            action()
        }
        .buttonStyle(.aviProminent)
        .disabled(!actionEnabled)
        // A destructive action is clicked, never confirmed with Return.
        if actionRole == .destructive {
            button
        } else {
            button
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// "Checkout as Worktree": the branch in a new folder next to this repository.
struct WorktreeCheckoutSheet: View {
    let store: RepositoryStore
    let branch: GitReference

    @State private var path = ""
    @State private var openAfterwards = true

    var body: some View {
        BranchSheetLayout(
            symbol: "square.on.square",
            title: "Checkout as Worktree",
            subtitle: branch.name,
            summary: "Checks out \(branch.name) in a new folder linked to this repository, so you can work on it while this worktree stays on its own branch.",
            actionTitle: "Create Worktree",
            actionEnabled: problem == nil,
            action: create
        ) {
            AviPopupField("Folder", note: problem ?? "Git creates this folder.", noteTone: problem == nil ? .secondary : .danger) {
                HStack(spacing: 6) {
                    TextField("Folder", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .accessibilityLabel("Worktree folder")
                    Button("Choose…", action: choose)
                }
            }
            AviPopupGroup {
                AviPopupOption(
                    "Switch to it",
                    detail: "The repository's tab shows the new worktree. Its other worktrees are a hover over the tab away.",
                    isOn: $openAfterwards
                )
            }
        }
        .onAppear {
            if path.isEmpty {
                path = store.suggestedWorktreePath(for: branch.name)?.path ?? ""
            }
        }
    }

    private var resolvedURL: URL? {
        let expanded = (path.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private var problem: String? {
        guard let url = resolvedURL else { return "Enter a full path, such as ~/src/\(branch.name)." }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let empty = isDirectory.boolValue && ((try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty ?? false)
        return empty ? nil : "That folder already exists and is not empty."
    }

    private func choose() {
        let panel = NSSavePanel()
        panel.title = "Choose Where to Create the Worktree"
        panel.prompt = "Choose"
        panel.canCreateDirectories = true
        if let url = resolvedURL {
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func create() {
        guard let url = resolvedURL else { return }
        let open = openAfterwards
        Task { await store.addWorktree(branch: branch.name, at: url, openAfterwards: open) }
    }
}

/// "Merge into <current>": how to bring the branch in.
struct MergeBranchSheet: View {
    let store: RepositoryStore
    let branch: GitReference

    @State private var mode: MergeMode = .fastForwardIfPossible

    var body: some View {
        let current = store.branch?.name ?? "HEAD"
        BranchSheetLayout(
            symbol: "arrow.triangle.merge",
            tint: DS.Palette.infoPurple,
            title: "Merge Branch",
            subtitle: "\(branch.name) into \(current)",
            summary: "Merges \(branch.name) into \(current), the branch checked out here.",
            actionTitle: mode == .squash ? "Squash" : "Merge",
            action: { Task { await store.merge(branch: branch.name, mode: mode) } }
        ) {
            AviPopupChoices(
                choices: MergeMode.allCases.map { mode in
                    .init(value: mode, title: Self.title(of: mode), detail: Self.explanation(of: mode, branch: branch.name, current: current))
                },
                selection: $mode
            )
            if !store.entries.isEmpty {
                AviPopupCallout("You have uncommitted changes. Git stops before the merge if it would overwrite them.", tone: .warning)
            }
        }
    }

    static func title(of mode: MergeMode) -> String {
        switch mode {
        case .fastForwardIfPossible: return "Fast-forward if possible"
        case .noFastForward: return "Always create a merge commit"
        case .fastForwardOnly: return "Fast-forward only"
        case .squash: return "Squash into one change"
        }
    }

    static func explanation(of mode: MergeMode, branch: String, current: String) -> String {
        switch mode {
        case .fastForwardIfPossible:
            return "Moves \(current) forward when it has no commits of its own; otherwise records a merge commit."
        case .noFastForward:
            return "Records a merge commit even when \(current) could just move forward, so the merge stays visible in history."
        case .fastForwardOnly:
            return "Moves \(current) forward, or stops without changing anything when the branches have diverged."
        case .squash:
            return "Stages every change from \(branch) as one change on \(current) without committing. Review it in Changes, then commit."
        }
    }
}

/// "Rebase on <branch>": replays the current branch on top of it.
struct RebaseBranchSheet: View {
    let store: RepositoryStore
    let onto: GitReference

    @State private var autostash = true
    @State private var commitCount: Int?

    var body: some View {
        let current = store.branch?.name ?? "HEAD"
        BranchSheetLayout(
            symbol: "arrow.triangle.pull",
            tint: DS.Palette.infoTeal,
            title: "Rebase Branch",
            subtitle: "\(current) onto \(onto.name)",
            summary: "Replays the commits of \(current) that \(onto.name) does not have on top of \(onto.name).",
            actionTitle: "Rebase",
            action: { Task { await store.rebase(onto: onto.name, autostash: autostash) } }
        ) {
            if let commitCount {
                AviPopupNote(commitCount == 0
                    ? "\(current) has no commits of its own, so it simply moves to \(onto.name)."
                    : "\(commitCount == 1 ? "1 commit is" : "\(commitCount) commits are") replayed and get new IDs.")
            }
            if store.branch?.upstream != nil {
                AviPopupCallout("\(current) is already pushed. After rebasing, pushing it again needs Force push.", tone: .warning)
            }
            AviPopupGroup {
                AviPopupOption(
                    "Stash uncommitted changes during the rebase",
                    detail: "Puts them aside while the commits are replayed, then brings them back.",
                    isOn: $autostash
                )
            }
        }
        .task {
            commitCount = try? await store.rebaseCandidates(onto: onto.name).count
        }
    }
}

/// "Delete…": the local branch, and its remote branch when you ask.
struct DeleteBranchSheet: View {
    let store: RepositoryStore
    let branch: GitReference
    /// Called when Git refuses because the branch is not merged.
    let needsForce: (GitReference) -> Void

    @State private var alsoOnRemote = false

    var body: some View {
        let upstream = branch.isUpstreamGone ? nil : store.upstreamParts(of: branch)
        BranchSheetLayout(
            symbol: "trash",
            tint: DS.Palette.danger,
            title: "Delete Branch",
            subtitle: branch.name,
            summary: "Deletes \(branch.name) from this Mac.",
            actionTitle: "Delete",
            actionRole: .destructive,
            action: delete
        ) {
            if let upstream, upstream.branch == store.defaultBranchName {
                // Tracking the default branch is common; deleting it never is.
                AviPopupNote("Its upstream is '\(upstream.branch)', the default branch on '\(upstream.remote)', which stays.")
            } else if let upstream {
                AviPopupGroup {
                    AviPopupOption(
                        "Also delete '\(upstream.branch)' on '\(upstream.remote)'",
                        detail: upstream.branch != branch.name ? "That is its upstream, which has a different name." : nil,
                        detailTone: .warning,
                        isOn: $alsoOnRemote
                    )
                }
                if alsoOnRemote {
                    AviPopupCallout(
                        "Removes it for everyone who uses '\(upstream.remote)'."
                            + ((branch.behind ?? 0) > 0
                                ? " It has \(branch.behind ?? 0) commit\(branch.behind == 1 ? "" : "s") that \(branch.name) does not."
                                : ""),
                        tone: .warning
                    )
                }
            }
            AviPopupNote("Git refuses when the branch has commits the current branch does not; Avi then asks before forcing.")
        }
    }

    private func delete() {
        let upstream = store.upstreamParts(of: branch)
        let remote = alsoOnRemote && upstream?.branch != store.defaultBranchName
        Task {
            if await store.deleteBranch(branch, alsoOnRemote: remote, force: false) == .needsForce {
                needsForce(branch)
            }
        }
    }
}
