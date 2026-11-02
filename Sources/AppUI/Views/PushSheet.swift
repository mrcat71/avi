import AppKit
import SwiftUI

/// Fork-style confirmation sheet for `git push`. Surfaces the branch
/// (read-only), lets the user pick the target remote, and exposes "push all
/// tags" + "force push" (mapped to `--force-with-lease` for safety) toggles.
/// Tags on the commits the push sends are listed; the ticked ones go in the
/// same atomic push as the branch, so none lands on the remote without its
/// commit. On a GitHub or GitLab remote it can create the branch's pull or
/// merge request in the same step, titled after the branch name with ticket
/// keys and names that need their hyphens kept.
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
    @Environment(\.aviDensity) private var density

    var body: some View {
        AviPopup(
            symbol: "arrow.up",
            title: sheetTitle,
            subtitle: store.root?.lastPathComponent,
            width: 520
        ) {
            VStack(alignment: .leading, spacing: 6) {
                // Two equal columns under labels on one line; the arrow sits
                // between the controls.
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Branch")
                            .aviLabel(density)
                        branchPill
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 6) {
                        Text(" ")
                            .aviLabel(density)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .frame(height: 22)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To")
                            .aviLabel(density)
                        remotePicker
                    }
                    .frame(maxWidth: .infinity)
                }
                AviPopupNote(outcomeDescription)
            }

            options

            if canOfferPullRequest {
                pullRequestSection
            }
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .keyboardShortcut(.cancelAction)
            Button(actionTitle, action: perform)
                .buttonStyle(.aviProminent)
                .keyboardShortcut(.defaultAction)
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

    private var sheetTitle: String {
        guard createsPullRequest else { return "Push" }
        return "Push and Create \(forge?.requestNoun ?? "Pull Request")"
    }

    /// The tags to send along, then the push's own switches.
    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
            AviPopupGroup {
                tagToggles
                AviPopupOption(
                    "Push all tags",
                    detail: "Also pushes every other local tag, once the branch is in.",
                    isOn: $pushAllTags
                )
                AviPopupGroupDivider()
                AviPopupOption(
                    "Force push",
                    detail: forcePush
                        ? "Uses --force-with-lease, so remote work you have not fetched is never overwritten."
                        : "Replaces the remote branch, such as after a rebase.",
                    detailTone: forcePush ? .warning : .secondary,
                    isOn: $forcePush
                )
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

    // MARK: - Rows

    private var branchPill: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(currentBranchName ?? "(detached HEAD)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .frame(maxWidth: .infinity)
        .background(shape.fill(Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .help(currentBranchName ?? "HEAD is detached")
    }

    private var remotePicker: some View {
        Picker("", selection: $selectedRemote) {
            ForEach(availableRemotes, id: \.self) { remote in
                Text(label(for: remote)).tag(remote)
            }
            if availableRemotes.isEmpty {
                Text("(no remotes)").tag("")
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Remote")
    }

    private func label(for remote: String) -> String {
        if remote == upstreamRemote, let branch = currentBranchName {
            return "default (\(remote)/\(branch))"
        }
        return remote
    }

    // MARK: - Pull request

    @ViewBuilder
    private var pullRequestSection: some View {
        let noun = forge?.requestNoun ?? "Pull Request"
        VStack(alignment: .leading, spacing: 14) {
            AviPopupGroup {
                AviPopupOption(
                    "Create \(noun.lowercased()) on \(forge?.name ?? "the forge")",
                    detail: "Titled after the branch, into the remote's default branch. You can change both.",
                    isOn: $createsPullRequest
                )
            }
            if createsPullRequest {
                if let existing = context?.existing, let forge {
                    AviPopupField(noun, note: "Already open. Pushing updates it.") {
                        Button("\(forge.reference(existing.number)) \(existing.title)") {
                            NSWorkspace.shared.open(existing.url)
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                    }
                } else if let context {
                    requestFields(context)
                } else if isLoadingContext {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reading the repository…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    AviPopupNote("\(selectedRemote) is not on GitHub or GitLab.")
                }
            }
        }
    }

    @ViewBuilder
    private func requestFields(_ context: PullRequestContext) -> some View {
        AviPopupField("Title") {
            HStack(spacing: 4) {
                TextField("", text: $title, prompt: Text(context.title))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .accessibilityLabel("Title")
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
        }
        AviPopupField("Into") {
            Picker("", selection: $base) {
                ForEach(context.bases, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Into")
        }
        AviPopupField("Description") {
            TextEditor(text: $description)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .accessibilityLabel("Description")
        }
        VStack(alignment: .leading, spacing: 6) {
            AviPopupGroup {
                AviPopupOption("Draft", detail: "Opens it marked as not ready for review.", isOn: $isDraft)
            }
            AviPopupNote(routeNote(context))
        }
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
        if upstream == target {
            return "Updates \(target), the upstream of \(branch)."
        }
        if remoteBranches.contains(target) {
            return "Updates the existing \(target) and makes it the upstream of \(branch)."
        }
        return "Creates \(target) and makes it the upstream of \(branch)."
    }

    private var outcomeDescription: String {
        Self.outcome(
            branch: currentBranchName,
            remote: selectedRemote,
            upstream: branchUpstream,
            remoteBranches: store.refs.remoteBranches.map(\.name)
        )
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
