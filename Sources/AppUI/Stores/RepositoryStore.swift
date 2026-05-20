import Foundation
import GitKit

/// Observable state for one open repository: status entries, the selected file's
/// diff, and the working-copy actions. All git work runs through `GitProviding`.
@MainActor
@Observable
public final class RepositoryStore: Identifiable {
    public let id = UUID()

    public private(set) var root: URL?
    public private(set) var branch: BranchInfo?
    public private(set) var entries: [FileStatus] = []
    public private(set) var selectedPath: String?
    public private(set) var diff: FileDiff?
    public private(set) var historyRows: [CommitGraphRow] = []
    public private(set) var selectedCommitOID: String?
    public private(set) var commitFiles: [CommitFileChange] = []
    public private(set) var selectedCommitPath: String?
    public private(set) var commitDiff: FileDiff?
    public private(set) var refs: RepositoryRefs = .empty
    public private(set) var remotes: [GitRemote] = []
    public private(set) var remoteOutput: String?
    public private(set) var isLoading = false
    public private(set) var isHistoryLoading = false
    public private(set) var isRefsLoading = false
    public private(set) var isRemoteOperationRunning = false
    public private(set) var errorMessage: String?

    public var commitMessage: String = ""
    public var amend: Bool = false

    private let git: GitProviding
    private var watcher: RepositoryWatcher?
    private var autoRefreshTask: Task<Void, Never>?

    public init(git: GitProviding = CLIGitProvider()) {
        self.git = git
    }

    public var stagedEntries: [FileStatus] { entries.filter(\.isStaged) }

    public var unstagedEntries: [FileStatus] {
        entries.filter { $0.hasUnstagedChanges || $0.isUntracked }
    }

    public var selectedFile: FileStatus? {
        entries.first { $0.path == selectedPath }
    }

    public var selectedCommit: CommitSummary? {
        historyRows.first { $0.commit.oid == selectedCommitOID }?.commit
    }

    public var selectedCommitFile: CommitFileChange? {
        commitFiles.first { $0.path == selectedCommitPath }
    }

    public var canAmend: Bool {
        branch?.isUnborn == false
    }

    public var canCommit: Bool {
        let hasMessage = !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasMessage && ((amend && canAmend) || !stagedEntries.isEmpty)
    }

    public var canStageAll: Bool {
        !unstagedEntries.isEmpty && !isLoading
    }

    public var canUnstageAll: Bool {
        !stagedEntries.isEmpty && !isLoading
    }

    public func open(_ url: URL) async {
        do {
            let resolved = try await git.repositoryRoot(for: url)
            autoRefreshTask?.cancel()
            watcher = nil
            root = resolved
            selectedPath = nil
            diff = nil
            refs = .empty
            remotes = []
            remoteOutput = nil
            clearHistorySelection()
            startWatching(resolved)
            RecentRepositories.add(resolved)
            await refresh()
        } catch {
            errorMessage = "Not a git repository: \(url.path)"
        }
    }

    public func refresh() async {
        guard let root else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let status = try await git.status(in: root)
            branch = status.branch
            entries = status.entries
            if status.branch.isUnborn {
                amend = false
                historyRows = []
                clearHistorySelection()
            }
            errorMessage = nil
            if let selectedFile {
                await loadDiff(for: selectedFile)
            } else {
                selectedPath = nil
                diff = nil
            }
            await refreshRemotes()
            if !status.branch.isUnborn {
                await refreshRefs()
                await refreshHistory()
            } else {
                refs = .empty
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ file: FileStatus?) async {
        selectedPath = file?.path
        if let file {
            await loadDiff(for: file)
        } else {
            diff = nil
        }
    }

    public func stage(_ file: FileStatus) async {
        await perform { try await $0.stage(path: file.path, in: $1) }
    }

    public func stageAll() async {
        await perform { try await $0.stageAll(in: $1) }
    }

    public func unstage(_ file: FileStatus) async {
        await perform { try await $0.unstage(path: file.path, in: $1) }
    }

    public func unstageAll() async {
        await perform { try await $0.unstageAll(in: $1) }
    }

    public func discard(_ file: FileStatus) async {
        await perform { try await $0.discard(file, in: $1) }
    }

    public func refreshRefs() async {
        guard let root else { return }
        isRefsLoading = true
        defer { isRefsLoading = false }

        do {
            refs = try await git.refs(in: root)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func checkout(_ ref: GitReference) async {
        await perform {
            try await $0.checkout(ref, in: $1)
        }
    }

    public func createBranch(named name: String, checkout: Bool) async {
        await perform {
            try await $0.createBranch(named: name, startPoint: nil, checkout: checkout, in: $1)
        }
    }

    public func deleteBranch(named name: String) async {
        await perform {
            try await $0.deleteBranch(named: name, in: $1)
        }
    }

    public func refreshRemotes() async {
        guard let root else { return }
        do {
            remotes = try await git.remotes(in: root)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func fetch(remote: String?) async {
        await performRemoteOperation {
            try await $0.fetch(remote: remote, in: $1)
        }
    }

    public func pull() async {
        await performRemoteOperation {
            try await $0.pull(in: $1)
        }
    }

    public func push() async {
        await performRemoteOperation {
            try await $0.push(in: $1)
        }
    }

    public func refreshHistory(limit: Int = 200) async {
        guard let root else { return }
        isHistoryLoading = true
        defer { isHistoryLoading = false }

        do {
            let commits = try await git.history(in: root, limit: limit)
            historyRows = CommitGraph.assignRows(for: commits)

            if let selectedCommitOID,
               let row = historyRows.first(where: { $0.commit.oid == selectedCommitOID }) {
                await selectCommit(row.commit)
            } else {
                await selectCommit(historyRows.first?.commit)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectCommit(_ commit: CommitSummary?) async {
        guard let root, let commit else {
            clearHistorySelection()
            return
        }

        selectedCommitOID = commit.oid
        commitFiles = []
        selectedCommitPath = nil
        commitDiff = nil

        do {
            commitFiles = try await git.changedFiles(in: commit.oid, in: root)
            await selectCommitFile(commitFiles.first)
        } catch {
            errorMessage = error.localizedDescription
            commitFiles = []
            commitDiff = nil
        }
    }

    public func selectCommitFile(_ file: CommitFileChange?) async {
        guard let root, let selectedCommitOID, let file else {
            selectedCommitPath = nil
            commitDiff = nil
            return
        }

        selectedCommitPath = file.path
        do {
            commitDiff = try await git.diff(commitOID: selectedCommitOID, path: file.path, in: root)
        } catch {
            errorMessage = error.localizedDescription
            commitDiff = nil
        }
    }

    public func commit() async {
        guard let root, canCommit else { return }
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if amend {
                try await git.amend(message: message, in: root)
            } else {
                try await git.commit(message: message, in: root)
            }
            commitMessage = ""
            amend = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// When amend is enabled and no message has been typed, prefill the last commit message.
    public func prepareAmendIfNeeded() async {
        guard amend, commitMessage.isEmpty, let root else { return }
        commitMessage = (try? await git.lastCommitMessage(in: root)) ?? ""
    }

    public func dismissError() {
        errorMessage = nil
    }

    private func loadDiff(for file: FileStatus) async {
        guard let root else { return }
        let source: DiffSource = file.isUntracked ? .untracked : (file.hasUnstagedChanges ? .unstaged : .staged)
        do {
            diff = try await git.diff(path: file.path, source: source, in: root)
        } catch {
            errorMessage = error.localizedDescription
            diff = nil
        }
    }

    private func perform(_ action: (GitProviding, URL) async throws -> Void) async {
        guard let root else { return }
        do {
            try await action(git, root)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRemoteOperation(_ action: (GitProviding, URL) async throws -> GitRemoteOperationResult) async {
        guard let root else { return }
        isRemoteOperationRunning = true
        defer { isRemoteOperationRunning = false }

        do {
            let result = try await action(git, root)
            remoteOutput = result.isEmpty ? "Done" : result.output
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startWatching(_ url: URL) {
        let watcher = RepositoryWatcher(url: url) { [weak self] in
            Task { @MainActor in
                self?.scheduleAutoRefresh()
            }
        }
        self.watcher = watcher
        watcher.start()
    }

    private func scheduleAutoRefresh() {
        guard root != nil, !isLoading, !isRemoteOperationRunning else { return }
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func clearHistorySelection() {
        selectedCommitOID = nil
        commitFiles = []
        selectedCommitPath = nil
        commitDiff = nil
    }
}
