import AppKit
import Foundation
import GitKit

/// What to show after a push or a pull request: one line at the top of the window.
struct PullRequestNotice: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Avi created it.
        case created(PullRequestInfo)
        /// The branch already had one open.
        case existing(PullRequestInfo)
        /// The forge's form opened in the browser, filled in.
        case openedInBrowser
        /// Creating failed; the form in the browser is the way out.
        case failed(message: String, fallback: URL?)
        /// A branch reached the remote for the first time and has no pull request.
        case pushedNewBranch(branch: String, remote: String)
    }

    let id = UUID()
    let kind: Kind
    let forge: Forge
}

/// A Push sheet to open: from the toolbar, from Repository > Push and
/// Create Pull Request, or from the offer after a branch's first push.
struct PushSheetRequest: Identifiable, Equatable {
    let id = UUID()
    /// The branch to push; nil is the current one.
    let branch: String?
    /// Starts with "Create pull request" ticked.
    let pullRequest: Bool
}

/// Everything the pull request part of the Push sheet needs for a branch.
struct PullRequestContext: Equatable {
    let forge: Forge
    let remote: String
    let branch: String
    /// Branches on the remote the request can merge into, the default first.
    let bases: [String]
    let defaultBase: String
    /// The title made from the branch name.
    let title: String
    /// Other titles to pick from: the branch name as it is, its last commit's subject.
    let titleAlternatives: [String]
    /// The repository's template, else what the branch's commits say.
    let body: String
    let route: PullRequestRoute
    /// An open request from this branch, which makes creating one pointless.
    let existing: PullRequestInfo?
}

extension RepositoryStore {
    /// GitHub or GitLab, for the remote `branch` pushes to; nil when neither.
    func pullRequestForge(for branch: String) -> Forge? {
        Forge(pullRequestProvider(for: branch))
    }

    /// Whether `branch` can have a pull request at all: it is on a GitHub or
    /// GitLab remote and is not the branch requests merge into.
    func canOfferPullRequest(for branch: String?) -> Bool {
        guard let branch, pullRequestForge(for: branch) != nil else { return false }
        return branch != defaultBranchName
    }

    /// Reads what the Push sheet offers for a pull request of `branch` to
    /// `remote`: forge, bases, suggested title and description, how it would
    /// be created, and whether one is open already.
    /// `route` skips asking gh, glab and Settings, for tests.
    func loadPullRequestContext(branch: String, remote preferredRemote: String? = nil, route knownRoute: PullRequestRoute? = nil) async -> PullRequestContext? {
        guard let root,
              let remoteName = preferredRemote ?? pushRemoteName(for: branch),
              let gitRemote = remotes.first(where: { $0.name == remoteName }) else { return nil }
        var hint = RemoteURLParser.hint(from: gitRemote, knownHosts: KnownProviderHosts.shared.hosts)
        if hint == .unknown {
            // A self-hosted GitLab `glab` was signed in to after the list loaded.
            await KnownProviderHosts.shared.refresh()
            hint = RemoteURLParser.hint(from: gitRemote, knownHosts: KnownProviderHosts.shared.hosts)
        }
        guard let forge = Forge(hint) else { return nil }

        let prefix = remoteName + "/"
        var bases = refs.remoteBranches
            .map(\.name)
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .filter { $0 != "HEAD" && $0 != branch }
        let detected = await (try? git.defaultBranch(remote: remoteName, in: root)) ?? nil
        let defaultBase = [detected, defaultBranchName, "main", "master"]
            .compactMap(\.self)
            .first { bases.contains($0) } ?? detected ?? bases.first ?? "main"
        bases.removeAll { $0 == defaultBase }
        bases.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        bases.insert(defaultBase, at: 0)

        let names = await pullRequestTitleNames(forge: forge)
        let config = ConfigStore.shared.config.pullRequests
        let title = PullRequestTitle.make(branch: branch, rules: PullRequestTitle.Rules(config), knownNames: names)
        var alternatives: [String] = []
        for candidate in [branch, refs.localBranches.first { $0.name == branch }?.subject] {
            if let candidate, !candidate.isEmpty, candidate != title, !alternatives.contains(candidate) {
                alternatives.append(candidate)
            }
        }

        let body: String
        if let template = Self.pullRequestTemplate(in: root, forge: forge) {
            body = template
        } else {
            body = await pullRequestCommitSummary(branch: branch, base: "\(remoteName)/\(defaultBase)")
        }

        var route = knownRoute
        if route == nil {
            route = await PullRequestService.route(for: forge)
        }
        let resolvedRoute = route ?? .browser
        var existing: PullRequestInfo?
        if let ref = refs.localBranches.first(where: { $0.name == branch }), branchExistsOnPullRequestRemote(ref) || refs.remoteBranches.contains(where: { $0.name == prefix + branch }) {
            existing = await PullRequestService.existing(head: branch, on: forge, via: resolvedRoute, in: root)
        }
        guard !Task.isCancelled else { return nil }
        if let existing {
            openPullRequests[branch] = existing
        } else {
            openPullRequests[branch] = nil
        }

        return PullRequestContext(
            forge: forge,
            remote: remoteName,
            branch: branch,
            bases: bases,
            defaultBase: defaultBase,
            title: title,
            titleAlternatives: alternatives,
            body: body,
            route: resolvedRoute,
            existing: existing
        )
    }

    /// Pushes `branch`, with `tags` in the same atomic push, then creates its
    /// pull request when `pullRequest` is given. A branch that reaches a
    /// GitHub or GitLab remote for the first time without one gets the offer
    /// to create it.
    func publish(
        branch: String?,
        remote: String?,
        force: Bool,
        pushTags: Bool,
        tags: [String] = [],
        pullRequest: (request: PullRequestRequest, context: PullRequestContext)? = nil
    ) async {
        let name = branch ?? self.branch?.name
        let remoteName = remote ?? name.flatMap { pushRemoteName(for: $0) }
        let wasOnRemote = name.map { branchName in
            refs.remoteBranches.contains { $0.name == "\(remoteName ?? "")/\(branchName)" }
        } ?? true
        pullRequestNotice = nil

        await push(branch: branch, remote: remote, force: force, pushTags: pushTags, tags: tags)
        guard errorMessage == nil else { return }

        if let pullRequest {
            await createPullRequest(pullRequest.request, context: pullRequest.context)
        } else if let name, let remoteName, !wasOnRemote, canOfferPullRequest(for: name),
                  openPullRequests[name] == nil, let forge = pullRequestForge(for: name) {
            pullRequestNotice = PullRequestNotice(kind: .pushedNewBranch(branch: name, remote: remoteName), forge: forge)
        }
    }

    /// Creates the request the way `context.route` says, or opens the
    /// forge's form when Avi cannot create it itself.
    func createPullRequest(_ request: PullRequestRequest, context: PullRequestContext) async {
        guard let root else { return }
        let forge = context.forge
        let fallback = PullRequestService.browserURL(for: request, on: forge)
        guard context.route.createsInApp else {
            if let fallback {
                NSWorkspace.shared.open(fallback)
            }
            pullRequestNotice = PullRequestNotice(kind: .openedInBrowser, forge: forge)
            return
        }
        do {
            let created = try await PullRequestService.create(request, on: forge, via: context.route, in: root)
            openPullRequests[request.head] = created
            pullRequestNotice = PullRequestNotice(kind: .created(created), forge: forge)
        } catch {
            pullRequestNotice = PullRequestNotice(kind: .failed(message: error.localizedDescription, fallback: fallback), forge: forge)
        }
    }

    /// Hyphenated file and folder names of the repository, and its own
    /// names, read once per commit.
    func pullRequestTitleNames(forge: Forge) async -> Set<String> {
        let extras = [repositoryName, forge.projectName]
        guard ConfigStore.shared.config.pullRequests.learnNamesFromRepository, let root else {
            return PullRequestTitle.knownNames(fromPaths: [], extra: extras)
        }
        let head = branch?.oid ?? ""
        if let titleNames, titleNames.head == head, !head.isEmpty {
            return titleNames.names
        }
        // A lookup that failed, or was cancelled because the sheet's inputs
        // changed, is not remembered: the next one tries again.
        guard let paths = try? await git.trackedPaths(in: root) else {
            return PullRequestTitle.knownNames(fromPaths: [], extra: extras)
        }
        let names = PullRequestTitle.knownNames(fromPaths: paths, extra: extras)
        titleNames = (head, names)
        return names
    }

    /// One commit: its description. Several: their subjects as a list.
    private func pullRequestCommitSummary(branch: String, base: String) async -> String {
        guard let root else { return "" }
        let commits = await (try? git.history(in: root, limit: 50, filter: HistoryFilter(scope: .ref("\(base)..\(branch)")))) ?? []
        if commits.count == 1 {
            return commits[0].body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return commits.reversed().map { "- \($0.subject)" }.joined(separator: "\n")
    }

    /// The repository's pull or merge request template, where GitHub and
    /// GitLab look for it.
    nonisolated static func pullRequestTemplate(in root: URL, forge: Forge) -> String? {
        let files: [String]
        let folders: [String]
        switch forge {
        case .github:
            files = [
                ".github/pull_request_template.md",
                "pull_request_template.md",
                "docs/pull_request_template.md"
            ]
            folders = [".github/PULL_REQUEST_TEMPLATE"]
        case .gitlab:
            files = [".gitlab/merge_request_templates/Default.md"]
            folders = [".gitlab/merge_request_templates"]
        }
        let manager = FileManager.default
        var candidates = files.map { root.appendingPathComponent($0) }
        for folder in folders {
            let url = root.appendingPathComponent(folder)
            let contents = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            candidates += contents
                .filter { $0.pathExtension.lowercased() == "md" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        for candidate in candidates {
            if let text = try? String(contentsOf: candidate, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }
}
