import AppKit
import Foundation
import GitKit

/// Files the "Stash Files" sheet will stash.
public struct FileStashRequest: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let files: [FileStatus]
}

/// How deleting a branch from the branch menu went.
public enum BranchDeletion: Equatable, Sendable {
    case deleted
    /// Git refused the safe delete because the branch holds commits HEAD lacks.
    case needsForce
    case failed
}

// MARK: - Merge or rebase in progress

public extension RepositoryStore {
    /// Reads whether a merge or rebase waits in this working tree's git dir.
    /// Cheap enough for every refresh: a few file checks, no Git process.
    func refreshOperationState() {
        let state = location.flatMap { GitOperationState.detect(gitDir: $0.gitDir) }
        if operationState != state {
            operationState = state
        }
        guard let state else {
            operationNotice = nil
            // Aborted here or in a terminal: the merge's own message must not
            // linger for the next commit. One you edited stays.
            if let filled = operationMessage, commitMessage == filled {
                commitSummary = ""
                commitBody = ""
            }
            operationMessage = nil
            return
        }
        // A stopped merge commits with Git's prepared message unless you write another.
        if state == .merge, operationMessage == nil, let gitDir = location?.gitDir,
           fillCommitMessage(from: gitDir.appendingPathComponent("MERGE_MSG")) {
            operationMessage = commitMessage
        }
    }

    func continueRebase() async {
        await runIntegration { try await $0.continueRebase(in: $1) }
    }

    func skipRebaseCommit() async {
        await runIntegration { try await $0.skipRebaseCommit(in: $1) }
    }

    func abortOperation() async {
        guard let operation = operationState else { return }
        await perform { try await $0.abortOperation(operation, in: $1) }
    }

    /// Continue the stopped cherry-pick or revert (or rebase).
    func continueOperation() async {
        guard let operation = operationState else { return }
        await runIntegration { try await $0.continueOperation(operation, in: $1) }
    }

    /// Skip the commit the cherry-pick or revert (or rebase) stopped at.
    func skipOperation() async {
        guard let operation = operationState else { return }
        await runIntegration { try await $0.skipOperation(operation, in: $1) }
    }
}

// MARK: - Branch actions

public extension RepositoryStore {
    /// Check out a branch, taking uncommitted changes along when asked.
    func checkout(_ ref: GitReference, carryingLocalChanges: Bool) async {
        guard confirmLeavingDetachedHead(for: ref, carryingLocalChanges: carryingLocalChanges) else { return }
        await checkoutConfirmed(ref, carryingLocalChanges: carryingLocalChanges)
    }

    /// The checkout once nothing, or you, stands in its way.
    func checkoutConfirmed(_ ref: GitReference, carryingLocalChanges: Bool) async {
        guard carryingLocalChanges else {
            await perform { try await $0.checkout(ref, in: $1) }
            return
        }
        guard let root else { return }
        do {
            let outcome = try await git.checkout(ref, carryingLocalChanges: carryingLocalChanges, in: root)
            await refresh()
            if case .changesConflicted(let detail) = outcome {
                workspaceSelection = .localChanges
                errorMessage = "Switched to \(ref.name), but your changes conflict with it. "
                    + "They are in the working tree with conflict markers, and still saved in the stash, so you can start over from there.\n\n\(detail)"
            }
        } catch {
            await refresh()
            errorMessage = error.localizedDescription
        }
    }

    /// Check `branch` out in a new linked worktree, then open it in a tab.
    @discardableResult
    func addWorktree(branch: String, at path: URL, openAfterwards: Bool) async -> Bool {
        guard let root else { return false }
        do {
            try await git.addWorktree(at: path, branch: branch, in: root)
            await refresh()
            if openAfterwards {
                NotificationCenter.default.post(name: .aviOpenRepository, object: path)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Where "Checkout as Worktree" suggests putting `branch`: next to this
    /// repository, named after both.
    func suggestedWorktreePath(for branch: String) -> URL? {
        guard let root = location?.workingTree ?? root else { return nil }
        let safeBranch = branch.map { $0 == "/" || $0 == " " ? "-" : $0 }
        let main = worktrees.first?.path ?? root
        return main.deletingLastPathComponent()
            .appendingPathComponent("\(main.lastPathComponent)-\(String(safeBranch))", isDirectory: true)
    }

    func fastForward(branch: String) async {
        await perform { try await $0.fastForward(branch: branch, in: $1) }
    }

    /// The branch can move to its fetched upstream without merging.
    func canFastForward(_ ref: GitReference) -> Bool {
        ref.upstream != nil && !ref.isUpstreamGone && (ref.behind ?? 0) > 0 && (ref.ahead ?? 0) == 0
    }

    func merge(branch: String, mode: MergeMode) async {
        let completed = await runIntegration { try await $0.merge(branch: branch, mode: mode, in: $1) }
        guard completed, mode == .squash, let gitDir = location?.gitDir else { return }
        // A squash stages the result and leaves the commit to you, with Git's message ready.
        _ = fillCommitMessage(from: gitDir.appendingPathComponent("SQUASH_MSG"))
        workspaceSelection = .localChanges
    }

    func rebase(onto branch: String, autostash: Bool) async {
        await runIntegration { try await $0.rebase(onto: branch, autostash: autostash, in: $1) }
    }

    func rebaseCandidates(onto branch: String) async throws -> [CommitSummary] {
        guard let root else { return [] }
        return try await git.rebaseCandidates(onto: branch, in: root)
    }

    func interactiveRebase(onto branch: String, plan: InteractiveRebasePlan, autostash: Bool) async {
        await runIntegration { try await $0.interactiveRebase(onto: branch, plan: plan, autostash: autostash, in: $1) }
    }

    /// Deletes `ref` here and, with `alsoOnRemote`, its upstream branch first.
    /// The remote goes first so a refusal there leaves everything as it was.
    func deleteBranch(_ ref: GitReference, alsoOnRemote: Bool, force: Bool) async -> BranchDeletion {
        guard let root else { return .failed }
        if alsoOnRemote, let upstream = upstreamParts(of: ref) {
            guard upstream.branch != defaultBranchName else {
                errorMessage = "'\(upstream.branch)' is the default branch on '\(upstream.remote)'. Avi does not delete it there."
                return .failed
            }
            await performRemoteOperation {
                try await $0.deleteRemoteBranch(named: upstream.branch, remote: upstream.remote, in: $1)
            }
            if errorMessage != nil {
                return .failed
            }
        }
        do {
            try await git.deleteBranch(named: ref.name, force: force, in: root)
            await refresh()
            return .deleted
        } catch let error as GitError {
            if !force, case let .commandFailed(_, _, stderr) = error, GitError.indicatesUnmergedBranch(stderr) {
                return .needsForce
            }
            errorMessage = error.localizedDescription
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    /// Splits `origin/feature/x` into a configured remote and its branch.
    /// The longest matching remote wins, since remote names may contain "/".
    func upstreamParts(of ref: GitReference) -> (remote: String, branch: String)? {
        guard let upstream = ref.upstream else { return nil }
        let remote = remotes.map(\.name)
            .filter { upstream.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
        guard let remote else { return nil }
        return (remote, String(upstream.dropFirst(remote.count + 1)))
    }

    /// The remote a push or pull request of `branch` goes to.
    func pushRemoteName(for branch: String) -> String? {
        resolveRemoteName(forBranch: branch)
    }

    /// The GitLab instance this repository's main remote is on, for author pictures.
    var gitLabHost: String? {
        guard let remote = remotes.first(where: { $0.name == "origin" }) ?? remotes.first,
              case .gitlab(let host, _) = RemoteURLParser.hint(from: remote, knownHosts: KnownProviderHosts.shared.hosts)
        else { return nil }
        return host
    }

    /// GitHub, GitLab, or unknown, for the remote a pull request of `branch` targets.
    func pullRequestProvider(for branch: String) -> ProviderHint {
        guard let name = pushRemoteName(for: branch), let remote = remotes.first(where: { $0.name == name }) else {
            return .unknown
        }
        return RemoteURLParser.hint(from: remote, knownHosts: KnownProviderHosts.shared.hosts)
    }

    /// A pull request shows the branch as the remote has it, so it needs a push
    /// when the remote lacks the branch or is missing some of its commits.
    func pullRequestNeedsPush(_ ref: GitReference) -> Bool {
        guard let upstream = upstreamParts(of: ref), !ref.isUpstreamGone,
              upstream.remote == pushRemoteName(for: ref.name)
        else { return true }
        return (ref.ahead ?? 0) > 0
    }

    /// True when `ref`'s upstream exists on the remote the pull request targets.
    func branchExistsOnPullRequestRemote(_ ref: GitReference) -> Bool {
        guard let upstream = upstreamParts(of: ref), !ref.isUpstreamGone else { return false }
        return upstream.remote == pushRemoteName(for: ref.name)
    }

    /// Remote branches `ref` could track: those with its name on each remote,
    /// plus its current upstream.
    func trackingCandidates(for ref: GitReference) -> [String] {
        var names = Set(refs.remoteBranches.compactMap { remoteRef -> String? in
            let parts = remoteRef.name.split(separator: "/", maxSplits: 1)
            return parts.count == 2 && String(parts[1]) == ref.name ? remoteRef.name : nil
        })
        if let upstream = ref.upstream, !ref.isUpstreamGone {
            names.insert(upstream)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

// MARK: - File actions

public extension RepositoryStore {
    func requestStash(of files: [FileStatus]) {
        guard !files.isEmpty else { return }
        fileStashRequest = FileStashRequest(files: files)
    }

    /// Stash only `files`. A staged rename stashes both of its paths.
    func stash(_ files: [FileStatus], message: String) async {
        let paths = withRenamePartners(files.map(\.path))
        let includeUntracked = files.contains(where: \.isUntracked)
        await perform { try await $0.stash(paths: paths, message: message, includeUntracked: includeUntracked, in: $1) }
    }

    func savePatch(for files: [FileStatus], staged: Bool, to url: URL) async {
        guard let root, !files.isEmpty else { return }
        do {
            let patch = try await git.patch(for: files, staged: staged, in: root)
            try patch.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Could not save the patch: \(error.localizedDescription)"
        }
    }

    /// Appends `pattern` to the repository's `.gitignore`, or with `locally`
    /// to `.git/info/exclude`, which only this clone reads.
    func ignore(pattern: String, locally: Bool) async {
        guard let root else { return }
        let file: URL
        if locally {
            let commonDir = location?.commonDir ?? root.appendingPathComponent(".git", isDirectory: true)
            file = commonDir.appendingPathComponent("info/exclude")
        } else {
            file = (location?.workingTree ?? root).appendingPathComponent(".gitignore")
        }
        do {
            try GitIgnore.append(pattern, to: file)
            await refresh()
        } catch {
            errorMessage = "Could not update \(file.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Opens `file` in the external diff tool from Settings > External Tools,
    /// or Git's `diff.tool` when none is set.
    func openExternalDiff(for file: FileStatus, staged: Bool) {
        guard let root else { return }
        let toolPath = ConfigStore.shared.config.externalTools.diffToolPath
        Task {
            do {
                try await git.launchDiffTool(path: file.path, staged: staged, toolPath: toolPath, in: root)
            } catch {
                errorMessage = "Could not open the external diff tool: \(error.localizedDescription)\n\n"
                    + "Choose a tool in Settings > External Tools > Diff Tool, or set Git's diff.tool."
            }
        }
    }

    func open(_ file: FileStatus, withApplicationAt application: URL) {
        guard let url = absoluteURL(for: file) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.errorMessage = "Could not open \(file.path): \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Helpers

extension RepositoryStore {
    /// Runs a merge or rebase. A stop is not an error: the banner explains it
    /// and Changes shows the conflicts. Returns true when it completed.
    @discardableResult
    func runIntegration(_ action: (GitProviding, URL) async throws -> IntegrationOutcome) async -> Bool {
        guard let root else { return false }
        do {
            let outcome = try await action(git, root)
            await refresh()
            switch outcome {
            case .completed:
                operationNotice = nil
                return true
            case .stopped(let detail):
                operationNotice = detail
                workspaceSelection = .localChanges
                return false
            }
        } catch {
            await refresh()
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Puts a message Git prepared into empty commit fields, without its
    /// comment lines. Returns true when the fields now hold it.
    func fillCommitMessage(from file: URL) -> Bool {
        guard commitSummary.isEmpty, commitBody.isEmpty,
              let raw = try? String(contentsOf: file, encoding: .utf8)
        else { return false }
        let text = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("#") }
            .joined(separator: "\n")
        let (summary, body) = splitGeneratedMessage(text)
        guard !summary.isEmpty else { return false }
        commitSummary = summary
        commitBody = body
        return true
    }
}
