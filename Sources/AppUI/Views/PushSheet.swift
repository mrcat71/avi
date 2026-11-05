import AppKit
import GitKit
import SwiftUI

/// Confirmation sheet for `git push`. A route card says what goes where:
/// the branch, the remote you pick, and what the push does there. "Push all
/// tags" and "Force push" (mapped to `--force-with-lease` for safety) are
/// switches under it. Tags on the commits the push sends are listed; the
/// ticked ones go in the same atomic push as the branch, so none lands on
/// the remote without its commit. On a GitHub or GitLab remote it can create
/// the branch's pull or merge request in the same step, titled after the
/// branch name with ticket keys and names that need their hyphens kept.
struct PushSheet: View {
    let store: RepositoryStore
    /// The branch to push; nil pushes the current branch.
    var branchName: String?
    /// Starts with "Create pull request" ticked.
    var includesPullRequest = false
    let dismiss: () -> Void

    @State private var selectedRemote: String = ""
    @State private var pushAllTags: Bool = false
    @State private var forcePush: Bool = false
    /// Tags on the commits this push sends, and the ones ticked to go along.
    @State private var tagChoices: [PushTagChoice] = []
    @State private var chosenTags: Set<String> = []
    @State private var tagsError: String?
    @State private var createsPullRequest = false
    @State private var context: PullRequestContext?
    @State private var isLoadingContext = false
    @State private var title = ""
    @State private var base = ""
    @State private var description = ""
    @State private var isDraft = ConfigStore.shared.config.pullRequests.draft

    var body: some View {
        AviPopup(title: "Push", subtitle: store.repositoryName, width: 500) {
            routeCard
            options
            if canOfferPullRequest {
                pullRequestSection
            }
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .aviKeyboardShortcut(.cancelAction)
            Button(actionTitle, action: perform)
                .buttonStyle(.aviProminent)
                .aviKeyboardShortcut(.defaultAction)
                .disabled(!canPerform)
        }
        .onAppear {
            createsPullRequest = includesPullRequest && canOfferPullRequest
            configureDefaultRemote()
        }
        .task {
            // A self-hosted GitLab that `glab` was signed in to after Avi
            // read its list of instances.
            if forge == nil, currentBranchName != nil {
                await KnownProviderHosts.shared.refresh()
            }
        }
        .task(id: PullRequestKey(remote: selectedRemote, wanted: createsPullRequest)) {
            guard createsPullRequest, canOfferPullRequest, let branch = currentBranchName else { return }
            await loadContext(branch: branch)
        }
        .task(id: selectedRemote) {
            await loadTags()
        }
    }

    // MARK: - Route

    /// The branch, a line down to the remote it goes to, and what the push
    /// does to the branch there.
    private var routeCard: some View {
        AviPopupGroup {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    PushRouteGlyph(symbol: "arrow.triangle.branch", tint: DS.Palette.accent)
                    // A long name gives up its middle; the tooltip has all of it.
                    Text(currentBranchName ?? "Detached HEAD")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(currentBranchName == nil ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(currentBranchName ?? "HEAD is detached")
                }
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 2, height: 12)
                    .padding(.leading, PushRouteGlyph.size / 2 - 1)
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    PushRouteGlyph(symbol: "cloud", tint: DS.Palette.textSecondary)
                    remoteChoice
                    Spacer(minLength: 8)
                    PushStatusBadge(status: routeStatus)
                        .help(routeHelp)
                        .accessibilityLabel(routeHelp)
                }
            }
            .padding(12)
        }
    }

    /// The remote to push to: a menu when there is a choice, else its name.
    @ViewBuilder
    private var remoteChoice: some View {
        if availableRemotes.count > 1 {
            AviPopupMenu("Remote", options: availableRemotes, selection: $selectedRemote, maxWidth: 160)
        } else {
            Text(availableRemotes.first ?? "No remotes")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(availableRemotes.isEmpty ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Remote: \(availableRemotes.first ?? "none")")
        }
    }

    /// The tags to send along, then the push's own switches. What each does
    /// is in its tooltip; only a force push spells out its safety net.
    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
            AviPopupGroup {
                tagToggles
                AviPopupOption("Push all tags", isOn: $pushAllTags)
                    .help("Also pushes every other local tag, once the branch is in.")
                AviPopupGroupDivider()
                AviPopupOption(
                    "Force push",
                    detail: forcePush ? "With lease: work on the remote you have not fetched is never overwritten." : nil,
                    detailTone: .warning,
                    isOn: $forcePush
                )
                .help("Replaces the remote branch, such as after a rebase.")
            }
            if !tagChoices.isEmpty {
                AviPopupNote(tagNote)
            }
            if let tagsError {
                AviPopupNote("Could not read the tags on these commits: \(tagsError)", tone: .warning)
            }
        }
    }

    // MARK: - Tags

    private var tagToggles: some View {
        ForEach(tagChoices) { choice in
            AviPopupOption(
                "Push tag \(choice.name) with the branch",
                isOn: Binding(
                    get: { chosenTags.contains(choice.name) },
                    set: { chosen in
                        if chosen {
                            chosenTags.insert(choice.name)
                        } else {
                            chosenTags.remove(choice.name)
                        }
                    }
                )
            )
            AviPopupGroupDivider()
        }
    }

    private var tagNote: String {
        let chosen = tagChoices.map(\.name).filter(chosenTags.contains)
        guard !chosen.isEmpty else {
            return "Unticked tags stay here. Push them later from Tags in the sidebar, once the commit is on the remote."
        }
        let remote = selectedRemote.isEmpty ? "The remote" : selectedRemote
        return "One push: \(remote) takes \(currentBranchName ?? "the branch") and \(chosen.joined(separator: ", ")) together, or none of them."
    }

    private func loadTags() async {
        guard let branch = currentBranchName, !selectedRemote.isEmpty else {
            tagChoices = []
            return
        }
        do {
            let choices = try await store.tagsForPush(branch: branch, remote: selectedRemote)
            guard !Task.isCancelled else { return }
            tagChoices = choices
            chosenTags = Set(choices.filter(\.isPreselected).map(\.name))
            tagsError = nil
        } catch {
            guard !Task.isCancelled else { return }
            tagChoices = []
            chosenTags = []
            tagsError = error.localizedDescription
        }
    }

    // MARK: - Pull request

    /// The switch, and once it is on, the request's fields in the same card.
    @ViewBuilder
    private var pullRequestSection: some View {
        let noun = forge?.requestNoun ?? "Pull Request"
        VStack(alignment: .leading, spacing: 6) {
            AviPopupGroup {
                AviPopupOption(
                    "Create \(noun.lowercased())",
                    detail: createsPullRequest ? nil : "On \(forge?.name ?? "the forge"), titled after the branch.",
                    isOn: $createsPullRequest
                )
                if createsPullRequest {
                    if let existing = context?.existing, let forge {
                        AviPopupGroupDivider()
                        AviPopupRow(noun, detail: "Already open. Pushing updates it.", layout: .stacked) {
                            Button("\(forge.reference(existing.number)) \(existing.title)") {
                                NSWorkspace.shared.open(existing.url)
                            }
                            .buttonStyle(.link)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(existing.title)
                        }
                    } else if let context {
                        requestFields(context)
                    } else if isLoadingContext {
                        AviPopupGroupDivider()
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Reading the repository…")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                }
            }
            if createsPullRequest {
                if let context, context.existing == nil {
                    AviPopupNote(routeNote(context))
                } else if context == nil, !isLoadingContext {
                    AviPopupNote("\(selectedRemote) is not on GitHub or GitLab.")
                }
            }
        }
    }

    /// Where the request goes, then what it says. Every control keeps to
    /// the card's width: a remote can have hundreds of branches, and the
    /// longest name must not widen the sheet.
    @ViewBuilder
    private func requestFields(_ context: PullRequestContext) -> some View {
        AviPopupGroupDivider()
        AviPopupRow("Into") {
            AviPopupMenu(
                "Into",
                options: context.bases,
                selection: $base,
                symbol: "arrow.triangle.branch",
                maxWidth: 240
            )
        }
        AviPopupGroupDivider()
        AviPopupRow("Title", layout: .stacked) {
            AviPopupTextField(label: "Title", text: $title, prompt: context.title) {
                titleSuggestions(context)
            }
        }
        AviPopupRow("Description", layout: .stacked) {
            AviPopupTextEditor("Description", text: $description)
        }
        AviPopupGroupDivider()
        AviPopupOption("Draft", isOn: $isDraft)
            .help("Opens it marked as not ready for review.")
    }

    /// The other titles, at the end of the title field.
    private func titleSuggestions(_ context: PullRequestContext) -> some View {
        Menu {
            Button("Made from the Branch: \(context.title)") { title = context.title }
            ForEach(context.titleAlternatives, id: \.self) { alternative in
                Button(alternative) { title = alternative }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Other titles")
        .accessibilityLabel("Other titles")
    }

    private func routeNote(_ context: PullRequestContext) -> String {
        let noun = context.forge.requestNoun.lowercased()
        switch context.route {
        case nil:
            return "On submit, Avi checks for an existing \(noun) and uses gh or glab, your token from Settings, or the browser."
        case .cli(let executable):
            return "Avi creates the \(noun) with \(URL(fileURLWithPath: executable).lastPathComponent), signed in as you."
        case .token:
            return "Avi creates the \(noun) with your \(context.forge.name) token from Settings."
        case .browser:
            let tool = if case .github = context.forge {
                "gh"
            } else {
                "glab"
            }
            return "The filled-in form opens in your browser. Sign in to \(tool), or add a token in Settings, and Avi creates the \(noun) itself."
        }
    }

    private func loadContext(branch: String) async {
        let previous = context
        context = nil
        isLoadingContext = true
        defer {
            if !Task.isCancelled {
                isLoadingContext = false
            }
        }
        let loaded = await store.loadPullRequestContext(branch: branch, remote: selectedRemote.isEmpty ? nil : selectedRemote)
        // A newer load replaced this one.
        guard !Task.isCancelled else { return }
        guard let loaded else {
            context = nil
            return
        }
        // Keep what you already typed when only the remote changed.
        if title.isEmpty || title == previous?.title {
            title = loaded.title
        }
        if base.isEmpty || !loaded.bases.contains(base) {
            base = loaded.defaultBase
        }
        if description.isEmpty || description == previous?.body {
            description = loaded.body
        }
        context = loaded
    }

    // MARK: - Derived state

    private var currentBranchName: String? {
        branchName ?? store.branch?.name
    }

    private var forge: Forge? {
        context?.forge ?? currentBranchName.flatMap { store.pullRequestForge(for: $0) }
    }

    private var canOfferPullRequest: Bool {
        store.canOfferPullRequest(for: currentBranchName)
    }

    /// The remote lacks the branch or some of its commits.
    private var needsPush: Bool {
        guard let name = currentBranchName, let ref = store.refs.localBranches.first(where: { $0.name == name }) else { return true }
        return store.pullRequestNeedsPush(ref) || forcePush || pushAllTags || !chosenTags.isEmpty
    }

    private var actionTitle: String {
        guard createsPullRequest, let context, context.existing == nil else { return "Push" }
        let noun = context.forge.requestNoun
        return needsPush ? "Push and Create \(noun)" : "Create \(noun)"
    }

    private var canPerform: Bool {
        guard currentBranchName != nil, !availableRemotes.isEmpty else { return false }
        guard createsPullRequest else { return true }
        guard !isLoadingContext, let context else { return false }
        guard context.existing == nil else { return true }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !base.isEmpty && base != context.branch
    }

    /// The pushed branch's upstream, which need not be HEAD's.
    private var branchUpstream: String? {
        guard let name = currentBranchName, name != store.branch?.name else { return store.branch?.upstream }
        return store.refs.localBranches.first { $0.name == name }?.upstream
    }

    /// The pushed branch's own ref, for how far it is from its upstream.
    private var branchRef: GitReference? {
        guard let name = currentBranchName else { return nil }
        return store.refs.localBranches.first { $0.name == name }
    }

    /// Spells out whether the push updates a remote branch or creates one, so
    /// pushing never silently publishes a new name.
    nonisolated static func outcome(branch: String?, remote: String, upstream: String?, remoteBranches: [String]) -> String {
        guard let branch else {
            return "HEAD is detached, so there is no branch to push."
        }
        guard !remote.isEmpty else {
            return "Choose a remote to push to."
        }
        let target = "\(remote)/\(branch)"
        // An upstream deleted on the remote is created again.
        guard remoteBranches.contains(target) else {
            return "Creates \(target) and makes it the upstream of \(branch)."
        }
        if upstream == target {
            return "Updates \(target), the upstream of \(branch)."
        }
        return "Updates the existing \(target) and makes it the upstream of \(branch)."
    }

    /// The route card's word or two for `outcome`, with the commits the push
    /// sends, or a warning when the remote has commits the branch lacks.
    nonisolated static func routeStatus(
        branch: String?,
        remote: String,
        upstream: String?,
        remoteBranches: [String],
        ahead: Int?,
        behind: Int?
    ) -> PushRouteStatus {
        guard let branch else { return .detached }
        guard !remote.isEmpty else { return .noRemote }
        let target = "\(remote)/\(branch)"
        guard remoteBranches.contains(target) else { return .creates }
        guard upstream == target else { return .adopts }
        if let behind, behind > 0 {
            return .behind(behind)
        }
        if let ahead, ahead > 0 {
            return .sends(ahead)
        }
        return .upToDate
    }

    private var outcomeDescription: String {
        Self.outcome(
            branch: currentBranchName,
            remote: selectedRemote,
            upstream: branchUpstream,
            remoteBranches: store.refs.remoteBranches.map(\.name)
        )
    }

    private var routeStatus: PushRouteStatus {
        Self.routeStatus(
            branch: currentBranchName,
            remote: selectedRemote,
            upstream: branchUpstream,
            remoteBranches: store.refs.remoteBranches.map(\.name),
            ahead: branchRef?.ahead,
            behind: branchRef?.behind
        )
    }

    /// The status badge's tooltip: the outcome, and why a push behind its
    /// upstream is refused.
    private var routeHelp: String {
        guard case let .behind(count) = routeStatus else { return outcomeDescription }
        let commits = count == 1 ? "1 commit" : "\(count) commits"
        return "\(outcomeDescription) The remote has \(commits) this branch lacks: pull first, or force push."
    }

    private var availableRemotes: [String] {
        let names = store.remotes.map(\.name)
        if names.isEmpty, let upstreamRemote {
            return [upstreamRemote]
        }
        return names
    }

    private var upstreamRemote: String? {
        guard let upstream = branchUpstream,
              let head = upstream.split(separator: "/", maxSplits: 1).first
        else { return nil }
        return String(head)
    }

    private func configureDefaultRemote() {
        if !selectedRemote.isEmpty {
            return
        }
        if let upstreamRemote, availableRemotes.contains(upstreamRemote) {
            selectedRemote = upstreamRemote
        } else if let first = availableRemotes.first {
            selectedRemote = first
        }
    }

    // MARK: - Action

    private func perform() {
        let branch = currentBranchName
        let remote = selectedRemote.isEmpty ? nil : selectedRemote
        let force = forcePush
        let allTags = pushAllTags
        let tags = tagChoices.map(\.name).filter(chosenTags.contains)
        var pullRequest: (request: PullRequestRequest, context: PullRequestContext)?
        if createsPullRequest, let context, context.existing == nil, let branch {
            let request = PullRequestRequest(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: description,
                head: branch,
                base: base,
                isDraft: isDraft
            )
            pullRequest = (request, context)
        }
        dismiss()
        Task {
            await store.publish(branch: branch, remote: remote, force: force, pushTags: allTags, tags: tags, pullRequest: pullRequest)
        }
    }
}

/// Reloads the pull request part when the remote changes or it is ticked.
private struct PullRequestKey: Hashable {
    let remote: String
    let wanted: Bool
}

/// What a push does to the branch on the remote, as the route card's badge
/// shows it.
enum PushRouteStatus: Equatable {
    case detached
    case noRemote
    /// The remote has no branch of that name yet.
    case creates
    /// The remote has the branch, but it is not this branch's upstream yet.
    case adopts
    case upToDate
    /// Commits the upstream lacks.
    case sends(Int)
    /// Commits on the upstream the branch lacks, so a plain push is refused.
    case behind(Int)

    var title: String {
        switch self {
        case .detached: return "Nothing to push"
        case .noRemote: return "No remote"
        case .creates: return "New branch"
        case .adopts: return "Existing branch"
        case .upToDate: return "Up to date"
        case let .sends(count): return count == 1 ? "1 commit" : "\(count) commits"
        case let .behind(count): return "\(count) behind"
        }
    }

    var symbol: String? {
        switch self {
        case .creates: return "plus"
        case .adopts: return "link"
        case .upToDate: return "checkmark"
        case .sends: return "arrow.up"
        case .behind: return "arrow.down"
        case .detached, .noRemote: return nil
        }
    }

    var tint: Color {
        switch self {
        case .creates, .sends: return DS.Palette.accent
        case .behind, .noRemote: return DS.Palette.warning
        case .detached, .adopts, .upToDate: return DS.Palette.textSecondary
        }
    }
}

/// A round glyph at either end of the route card's line.
private struct PushRouteGlyph: View {
    static let size: CGFloat = 24

    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(tint.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

/// The route card's status, as a tinted capsule.
private struct PushStatusBadge: View {
    let status: PushRouteStatus

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = status.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(status.tint.opacity(0.14)))
        .fixedSize()
    }
}
