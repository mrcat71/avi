import AppKit
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
    public private(set) var stashes: [StashEntry] = []
    public private(set) var remotes: [GitRemote] = []
    public private(set) var defaultBranchName: String?
    public private(set) var remoteOutput: String?
    public private(set) var lastFetched: Date?
    public private(set) var isLoading = false
    public private(set) var isHistoryLoading = false
    public private(set) var isRefsLoading = false
    public private(set) var isRemoteOperationRunning = false
    public private(set) var errorMessage: String?
    public var historyFilter: HistoryFilter = .default

    public var commitSummary: String = ""
    public var commitBody: String = ""
    public var amend: Bool = false
    public var expandedFolders: Set<String> = []
    public var isGeneratingCommitMessage: Bool = false
    public var aiErrorDetail: AIErrorDetail?
    public var aiPendingPreview: AIPendingPreview?
    public var aiDebugDrawerVisible: Bool = false
    public var aiDebugMinimized: Bool = false
    public var aiDebugDrawerHeight: CGFloat = AIDebugDrawer.loadHeight()
    public var aiDebugLatestRun: AIRunResult?
    public var aiRewordPreview: AIRewordPreview?
    public var aiSplitPreview: AISplitPreview?
    public var isAIWorking: Bool = false
    public var rebaseInProgress: Bool = false
    private var aiTask: Task<Void, Never>?
    private var pendingDefaultExpand: Bool = false

    public var commitMessage: String {
        let trimmedSummary = commitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = commitBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty { return trimmedSummary }
        return trimmedSummary + "\n\n" + trimmedBody
    }

    private let git: GitProviding
    private var watcher: RepositoryWatcher?
    private var autoRefreshTask: Task<Void, Never>?

    public init(git: GitProviding = CLIGitProvider()) {
        self.git = git
    }

    public var stagedEntries: [FileStatus] {
        entries.filter(\.isStaged)
    }

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
        let hasSummary = !commitSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasSummary && ((amend && canAmend) || !stagedEntries.isEmpty)
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
            stashes = []
            remotes = []
            defaultBranchName = nil
            remoteOutput = nil
            clearHistorySelection()
            let saved = loadExpandedFolders(for: resolved)
            expandedFolders = saved ?? []
            pendingDefaultExpand = (saved == nil)
            startWatching(resolved)
            RecentRepositories.add(resolved)
            await refresh()
        } catch {
            errorMessage = "Not a git repository: \(url.path)"
        }
    }

    public func toggleFolderExpanded(_ path: String) {
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
        }
        if let root {
            saveExpandedFolders(for: root)
        }
    }

    public func setFolderExpanded(_ path: String, expanded: Bool) {
        if expanded {
            expandedFolders.insert(path)
        } else {
            expandedFolders.remove(path)
        }
        if let root {
            saveExpandedFolders(for: root)
        }
    }

    public func expandAllFolders() {
        expandedFolders = FileTreeBuilder.allFolderIds(for: entries)
        if let root {
            saveExpandedFolders(for: root)
        }
    }

    public func collapseAllFolders() {
        expandedFolders.removeAll()
        if let root {
            saveExpandedFolders(for: root)
        }
    }

    private func expandedFoldersKey(for root: URL) -> String {
        "avi.expandedFolders.\(root.standardizedFileURL.path)"
    }

    /// Returns the persisted set if the key exists, or `nil` to signal the repo has no
    /// prior expansion state yet. Callers can then apply a default (expand all).
    private func loadExpandedFolders(for root: URL) -> Set<String>? {
        let key = expandedFoldersKey(for: root)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(raw)
    }

    private func saveExpandedFolders(for root: URL) {
        UserDefaults.standard.set(Array(expandedFolders), forKey: expandedFoldersKey(for: root))
    }

    public func refresh() async {
        guard let root else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let status = try await git.status(in: root)
            branch = status.branch
            entries = status.entries
            if pendingDefaultExpand, !entries.isEmpty {
                pendingDefaultExpand = false
                expandedFolders = FileTreeBuilder.allFolderIds(for: entries)
                saveExpandedFolders(for: root)
            }
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
            refreshLastFetched()
            if !status.branch.isUnborn {
                await refreshRefs()
                await refreshHistory()
                await refreshStashes()
                await refreshDefaultBranch()
            } else {
                refs = .empty
                stashes = []
                defaultBranchName = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLastFetched() {
        guard let root else {
            lastFetched = nil
            return
        }
        let fetchHead = root.appendingPathComponent(".git").appendingPathComponent("FETCH_HEAD")
        let attributes = try? FileManager.default.attributesOfItem(atPath: fetchHead.path)
        lastFetched = attributes?[.modificationDate] as? Date
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

    public func refreshStashes() async {
        guard let root else { return }
        do {
            stashes = try await git.stashes(in: root)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolve the "protected" branch for sorting purposes: prefer the remote
    /// HEAD (origin's default branch); fall back to a `main`/`master` heuristic.
    public func refreshDefaultBranch() async {
        guard let root else { return }
        let remoteName: String? = {
            if remotes.contains(where: { $0.name == "origin" }) { return "origin" }
            return remotes.first?.name
        }()
        if let remoteName {
            let detected = (try? await git.defaultBranch(remote: remoteName, in: root)) ?? nil
            if let detected, !detected.isEmpty {
                defaultBranchName = detected
                return
            }
        }
        let localNames = Set(refs.localBranches.map(\.name))
        if localNames.contains("main") {
            defaultBranchName = "main"
        } else if localNames.contains("master") {
            defaultBranchName = "master"
        } else {
            defaultBranchName = nil
        }
    }

    public func applyStash(ref: String) async {
        await perform { try await $0.applyStash(ref: ref, in: $1) }
        await refreshStashes()
    }

    public func popStash(ref: String) async {
        await perform { try await $0.popStash(ref: ref, in: $1) }
        await refreshStashes()
    }

    public func dropStash(ref: String) async {
        await perform { try await $0.dropStash(ref: ref, in: $1) }
        await refreshStashes()
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

    public func createBranch(named name: String, startPoint: String?, checkout: Bool) async {
        await perform {
            try await $0.createBranch(named: name, startPoint: startPoint, checkout: checkout, in: $1)
        }
    }

    public func deleteBranch(named name: String) async {
        await perform {
            try await $0.deleteBranch(named: name, in: $1)
        }
    }

    public func createTag(name: String, targetOID: String, message: String?) async {
        await perform {
            try await $0.createTag(name: name, targetOID: targetOID, message: message, in: $1)
        }
    }

    public func pushTag(name: String, remote: String? = nil) async {
        await performRemoteOperation {
            try await $0.pushTag(name: name, remote: remote, in: $1)
        }
    }

    public func renameBranch(from oldName: String, to newName: String) async {
        await perform {
            try await $0.renameBranch(from: oldName, to: newName, in: $1)
        }
    }

    public func setUpstream(branch: String, upstream: String) async {
        await perform {
            try await $0.setUpstream(branch: branch, upstream: upstream, in: $1)
        }
    }

    public func unsetUpstream(branch: String) async {
        await perform {
            try await $0.unsetUpstream(branch: branch, in: $1)
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

    public func pull(branch: String?) async {
        await performRemoteOperation {
            try await $0.pull(branch: branch, in: $1)
        }
    }

    public func push() async {
        await performRemoteOperation {
            try await $0.push(in: $1)
        }
    }

    public func push(branch: String?) async {
        await performRemoteOperation {
            try await $0.push(branch: branch, in: $1)
        }
    }

    public func push(branch: String?, remote: String?, force: Bool, pushTags: Bool) async {
        await performRemoteOperation {
            try await $0.push(branch: branch, remote: remote, force: force, pushTags: pushTags, in: $1)
        }
    }

    /// Push `branch` (setting upstream if needed) and open the provider's
    /// new-PR/MR compare page in the browser, with title pre-filled to the branch name.
    public func pushAndOpenPullRequestPage(branch: String) async {
        guard let root else { return }
        errorMessage = nil

        let resolvedRemoteName = resolveRemoteName(forBranch: branch)
        guard let remoteName = resolvedRemoteName else {
            errorMessage = "No remote configured for this repository."
            return
        }
        guard let gitRemote = remotes.first(where: { $0.name == remoteName }) else {
            errorMessage = "Remote '\(remoteName)' not found."
            return
        }

        await push(branch: branch, remote: remoteName, force: false, pushTags: false)
        // performRemoteOperation surfaces failures via errorMessage; bail if push failed.
        if errorMessage != nil { return }

        let hint = RemoteURLParser.hint(from: gitRemote)
        let detected = (try? await git.defaultBranch(remote: remoteName, in: root)) ?? nil
        let base: String
        if let detected, !detected.isEmpty {
            base = detected
        } else {
            base = "main"
        }

        let url: URL?
        switch hint {
        case .github(let owner, let repo):
            url = GitHubAPI.compareWebURL(owner: owner, repo: repo, base: base, head: branch, title: branch)
        case .gitlab(let host, let projectPath):
            url = GitLabAPI.newMergeRequestWebURL(host: host, projectPath: projectPath, sourceBranch: branch, targetBranch: base, title: branch)
        case .unknown:
            errorMessage = "Remote '\(remoteName)' is not GitHub or GitLab; cannot open PR page."
            return
        }

        guard let url else {
            errorMessage = "Failed to build PR page URL."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Pick the remote name to use when pushing `branch`: prefer the branch's upstream remote,
    /// else "origin" if configured, else the first remote. Returns `nil` when no remotes exist.
    private func resolveRemoteName(forBranch branch: String) -> String? {
        if let ref = refs.localBranches.first(where: { $0.name == branch }),
           let upstream = ref.upstream,
           let head = upstream.split(separator: "/", maxSplits: 1).first {
            return String(head)
        }
        if remotes.contains(where: { $0.name == "origin" }) { return "origin" }
        return remotes.first?.name
    }

    public func setHistoryFilter(_ filter: HistoryFilter) async {
        historyFilter = filter
        await refreshHistory()
    }

    public func refreshHistory(limit: Int = 200) async {
        guard let root else { return }
        isHistoryLoading = true
        defer { isHistoryLoading = false }

        do {
            // Fetch the requested window. If the resulting commits reference
            // parent OIDs we didn't load (a branch that forked far enough back
            // that its merge-base is outside the window), pull progressively
            // larger windows so the graph never dangles a lane into empty
            // space. Capped so a pathological branch can't blow the budget.
            var effectiveLimit = limit
            var commits = try await git.history(in: root, limit: effectiveLimit, filter: historyFilter)
            var extensions = 0
            while extensions < Self.maxAutoExtendSteps, !orphanParents(in: commits).isEmpty {
                let nextLimit = effectiveLimit + Self.autoExtendStep
                let next = try await git.history(in: root, limit: nextLimit, filter: historyFilter)
                if next.count <= commits.count {
                    // Repo is shorter than the new limit; further extensions won't help.
                    break
                }
                effectiveLimit = nextLimit
                commits = next
                extensions += 1
            }

            historyRows = CommitGraph.assignRows(for: commits, refs: refs)

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

    private static let maxAutoExtendSteps = 3
    private static let autoExtendStep = 200

    private func orphanParents(in commits: [CommitSummary]) -> Set<String> {
        let known = Set(commits.map(\.oid))
        var orphans: Set<String> = []
        for commit in commits {
            for parent in commit.parentOIDs where !known.contains(parent) {
                orphans.insert(parent)
            }
        }
        // The oldest commit's parent (the root-of-window) is always "missing"
        // unless we happen to reach the repo root. That single dangling line
        // looks the same as a real orphan but doesn't warrant another fetch -
        // dropping the oldest commit's parents from the orphan set keeps the
        // loop bounded for normal "linear" histories.
        if let last = commits.last {
            for parent in last.parentOIDs {
                orphans.remove(parent)
            }
        }
        return orphans
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
        let message = commitMessage
        do {
            if amend {
                try await git.amend(message: message, in: root)
            } else {
                try await git.commit(message: message, in: root)
            }
            commitSummary = ""
            commitBody = ""
            amend = false
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// When amend is enabled and no message has been typed, prefill from the last commit message,
    /// splitting summary (first line) from body (everything after the first blank line).
    public func prepareAmendIfNeeded() async {
        guard amend, commitSummary.isEmpty, commitBody.isEmpty, let root else { return }
        guard let last = try? await git.lastCommitMessage(in: root), !last.isEmpty else { return }

        let lines = last.split(separator: "\n", omittingEmptySubsequences: false)
        if let firstBlank = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            commitSummary = lines.prefix(firstBlank).joined(separator: "\n")
            commitBody = lines.suffix(from: firstBlank + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            commitSummary = last
            commitBody = ""
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - AI commit message

    public func generateCommitMessage(config: AIConfig) {
        guard let root else { return }
        aiTask?.cancel()
        aiErrorDetail = nil
        aiPendingPreview = nil
        isGeneratingCommitMessage = true
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isGeneratingCommitMessage = false }

            // Pre-flight validation so we never hang waiting on a broken setup.
            let report = await AICLIValidator.validate(config)
            if Task.isCancelled { return }
            if !report.isValid {
                aiErrorDetail = AIErrorDetail(
                    title: "AI setup not ready",
                    message: report.messages.joined(separator: "\n"),
                    runResult: nil
                )
                return
            }

            do {
                let diff = try await git.stagedDiff(in: root)
                if Task.isCancelled { return }
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    aiErrorDetail = AIErrorDetail(
                        title: "Nothing staged",
                        message: "Stage files first or run the command with all changes.",
                        runResult: nil
                    )
                    return
                }
                let stagedPaths = stagedEntries.map(\.path)
                let context = PromptContext(
                    stagedDiff: diff,
                    branch: branch?.name ?? "",
                    files: stagedPaths,
                    repo: root.lastPathComponent,
                    model: config.model,
                    lowLimit: config.subjectSoftLimit,
                    highLimit: config.subjectHardLimit,
                    guideLine: config.bodyWrap
                )
                let prompt = PromptRenderer.render(template: config.promptTemplate, context: context)
                let engine = AIEngineFactory.make(config: config)
                let text = try await engine.generate(
                    prompt: prompt,
                    model: config.model,
                    temperature: config.temperature,
                    maxTokens: config.maxTokens,
                    reasoningEffort: config.reasoningEffort
                )
                if Task.isCancelled { return }
                let (subject, body) = splitGeneratedMessage(text)
                let runResult = AIRunResult(
                    provider: config.backend,
                    resolvedExecutable: report.resolvedExecutable ?? "",
                    argv: [],
                    model: config.model,
                    exitCode: 0,
                    stdout: text,
                    stderr: "",
                    durationMS: 0,
                    timedOut: false
                )
                aiDebugLatestRun = runResult
                if config.directInsert {
                    // User opted out of the preview/accept flow: replace the
                    // commit fields directly. The debug drawer still has the
                    // run if they want to inspect what was generated.
                    commitSummary = subject
                    commitBody = body
                    aiPendingPreview = nil
                } else {
                    aiPendingPreview = AIPendingPreview(subject: subject, body: body, result: runResult)
                }
                // Success: do NOT auto-open the drawer. Respect prior user state.
            } catch let err as AIEngineError {
                if case .cancelled = err { return }
                self.aiErrorDetail = AIErrorDetail(
                    title: errorTitle(for: err),
                    message: err.errorDescription ?? "AI error",
                    runResult: err.runResult
                )
                if let runResult = err.runResult {
                    self.aiDebugLatestRun = runResult
                    self.openAIDebugDrawer()
                }
            } catch {
                if !(error is CancellationError) {
                    aiErrorDetail = AIErrorDetail(title: "AI error", message: error.localizedDescription, runResult: nil)
                }
            }
        }
    }

    public func cancelCommitMessageGeneration() {
        aiTask?.cancel()
        isGeneratingCommitMessage = false
    }

    public func dismissAIError() {
        aiErrorDetail = nil
    }

    // MARK: - AI debug drawer

    public func openAIDebugDrawer() {
        aiDebugDrawerVisible = true
        aiDebugMinimized = false
    }

    public func closeAIDebugDrawer() {
        aiDebugDrawerVisible = false
    }

    public func toggleAIDebugDrawer() {
        if aiDebugDrawerVisible {
            aiDebugDrawerVisible = false
        } else {
            aiDebugDrawerVisible = true
            aiDebugMinimized = false
        }
    }

    public func toggleAIDebugMinimized() {
        aiDebugMinimized.toggle()
    }

    public func clearAIDebugBuffer() {
        aiDebugLatestRun = nil
    }

    /// Has the latest run ended with a non-zero exit code or a timeout?
    /// Drives the red badge on the ladybug toggle so the user can spot an
    /// unread error after dismissing the drawer.
    public var aiDebugHasUnreadError: Bool {
        guard let run = aiDebugLatestRun else { return false }
        if run.timedOut { return true }
        if let exit = run.exitCode, exit != 0 { return true }
        return false
    }

    public func copyAIDebugLog() {
        guard let run = aiDebugLatestRun else { return }
        let generated = aiPendingPreview?.combined ?? ""
        let text = """
        $ \(run.commandLine)
        --- stdout ---
        \(run.stdout)
        --- stderr ---
        \(run.stderr)
        exit=\(run.exitCode.map(String.init) ?? "?") duration=\(run.durationMS)ms timedOut=\(run.timedOut)
        --- generated ---
        \(generated)
        """
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func acceptAIPreview(_ mode: AIAcceptMode) {
        guard let preview = aiPendingPreview else { return }
        switch mode {
        case .replace:
            commitSummary = preview.subject
            commitBody = preview.body
        case .appendAsBody:
            let appended = preview.body.isEmpty ? preview.subject : preview.subject + "\n\n" + preview.body
            commitBody = commitBody.isEmpty ? appended : commitBody + "\n\n" + appended
        }
        aiPendingPreview = nil
    }

    public func discardAIPreview() {
        aiPendingPreview = nil
    }

    private func errorTitle(for err: AIEngineError) -> String {
        switch err {
        case .timedOut: return "AI generation timed out"
        case .subprocessFailed: return "AI command failed"
        case .binaryNotFound: return "Binary not found"
        case .binaryNotExecutable: return "Binary not executable"
        case .missingAPIKey: return "Missing API key"
        case .noModelConfigured: return "No model"
        case .invalidResponse: return "Invalid response"
        case .cancelled: return "Cancelled"
        }
    }

    public enum AIAcceptMode {
        case replace
        case appendAsBody
    }

    private func splitGeneratedMessage(_ text: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        let firstLine = lines.first.map(String.init) ?? trimmed
        if let firstBlankIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }), firstBlankIndex > 0 {
            let body = lines.suffix(from: firstBlankIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return (firstLine.trimmingCharacters(in: .whitespacesAndNewlines), body)
        }
        return (firstLine.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    // MARK: - File actions (AppKit wrappers, no GitKit)

    public func absoluteURL(for file: FileStatus) -> URL? {
        guard let root else { return nil }
        return root.appendingPathComponent(file.path)
    }

    public func openFile(_ file: FileStatus) {
        guard let url = absoluteURL(for: file) else { return }
        NSWorkspace.shared.open(url)
    }

    public func revealInFinder(_ file: FileStatus) {
        guard let url = absoluteURL(for: file), let root else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: root.path)
    }

    public func copyAbsolutePath(_ file: FileStatus) {
        guard let url = absoluteURL(for: file) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    public func copyRelativePath(_ file: FileStatus) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(file.path, forType: .string)
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
        let priorPath = selectedPath
        let priorEntries = entries
        do {
            try await action(git, root)
            await refresh()
            await preserveSelection(priorPath: priorPath, priorEntries: priorEntries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// After a stage/unstage/discard, if the previously selected file no longer exists
    /// in the working tree, pick the next surviving neighbour from the prior list so
    /// the user keeps their place instead of losing selection entirely.
    private func preserveSelection(priorPath: String?, priorEntries: [FileStatus]) async {
        guard let priorPath else { return }
        let survives = entries.contains { $0.path == priorPath }
        if survives { return }
        guard let priorIndex = priorEntries.firstIndex(where: { $0.path == priorPath }) else { return }
        let livingPaths = Set(entries.map(\.path))
        let forward = priorEntries.suffix(from: priorIndex + 1).first { livingPaths.contains($0.path) }
        let backward = priorEntries.prefix(priorIndex).reversed().first { livingPaths.contains($0.path) }
        if let candidate = forward ?? backward,
           let live = entries.first(where: { $0.path == candidate.path }) {
            await select(live)
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

    // MARK: - AI reword / split

    public func rewordCommitWithAI(oid: String) {
        guard let root else { return }
        let config = ConfigStore.shared.config.ai
        aiTask?.cancel()
        aiErrorDetail = nil
        aiRewordPreview = nil
        isAIWorking = true
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAIWorking = false }

            let report = await AICLIValidator.validate(config)
            if Task.isCancelled { return }
            if !report.isValid {
                aiErrorDetail = AIErrorDetail(
                    title: "AI setup not ready",
                    message: report.messages.joined(separator: "\n"),
                    runResult: nil
                )
                return
            }

            do {
                guard let existing = try await git.commitMessage(for: oid, in: root) else {
                    aiErrorDetail = AIErrorDetail(title: "Commit not found", message: oid, runResult: nil)
                    return
                }
                let diff = try await git.commitDiff(for: oid, in: root)
                let context = PromptContext(
                    stagedDiff: "",
                    branch: branch?.name ?? "",
                    files: [],
                    repo: root.lastPathComponent,
                    model: config.model,
                    lowLimit: config.subjectSoftLimit,
                    highLimit: config.subjectHardLimit,
                    guideLine: config.bodyWrap,
                    existingMessage: existing,
                    commitDiff: diff
                )
                let prompt = PromptRenderer.render(template: config.rewordPromptTemplate, context: context)
                let engine = AIEngineFactory.make(config: config)
                let raw = try await engine.generate(
                    prompt: prompt,
                    model: config.model,
                    temperature: config.temperature,
                    maxTokens: config.maxTokens,
                    reasoningEffort: config.reasoningEffort
                )
                if Task.isCancelled { return }
                let proposed = Self.cleanRewordResponse(raw)
                aiDebugLatestRun = AIRunResult(
                    provider: config.backend,
                    resolvedExecutable: report.resolvedExecutable ?? "",
                    argv: [],
                    model: config.model,
                    exitCode: 0,
                    stdout: raw,
                    stderr: "",
                    durationMS: 0,
                    timedOut: false
                )
                aiRewordPreview = AIRewordPreview(
                    oid: oid,
                    oldMessage: existing,
                    proposed: proposed
                )
            } catch let err as AIEngineError {
                if case .cancelled = err { return }
                aiErrorDetail = AIErrorDetail(
                    title: errorTitle(for: err),
                    message: err.errorDescription ?? "AI error",
                    runResult: err.runResult
                )
                if let r = err.runResult {
                    aiDebugLatestRun = r
                    openAIDebugDrawer()
                }
            } catch {
                if !(error is CancellationError) {
                    aiErrorDetail = AIErrorDetail(title: "AI error", message: error.localizedDescription, runResult: nil)
                }
            }
        }
    }

    public func dismissAIRewordPreview() {
        aiRewordPreview = nil
    }

    public func applyAIRewordPreview() {
        guard let preview = aiRewordPreview, let root else { return }
        let edited = preview.proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.isEmpty else { return }
        aiRewordPreview = nil
        Task { @MainActor in
            do {
                let headOID = await currentHeadOID() ?? ""
                if preview.oid == "HEAD" || preview.oid == headOID {
                    try await git.amend(message: edited, in: root)
                } else {
                    try await git.rebaseSingle(commit: preview.oid, action: .reword(newMessage: edited), in: root)
                }
                rebaseInProgress = await git.isRebaseInProgress(in: root)
                await refresh()
                await refreshHistory()
            } catch {
                errorMessage = error.localizedDescription
                rebaseInProgress = await git.isRebaseInProgress(in: root)
            }
        }
    }

    public func splitStagedWithAI() {
        guard let root else { return }
        let config = ConfigStore.shared.config.ai
        aiTask?.cancel()
        aiErrorDetail = nil
        aiSplitPreview = nil
        isAIWorking = true
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAIWorking = false }

            let report = await AICLIValidator.validate(config)
            if Task.isCancelled { return }
            if !report.isValid {
                aiErrorDetail = AIErrorDetail(
                    title: "AI setup not ready",
                    message: report.messages.joined(separator: "\n"),
                    runResult: nil
                )
                return
            }
            do {
                let diff = try await git.stagedDiff(in: root)
                guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    aiErrorDetail = AIErrorDetail(title: "Nothing staged", message: "Stage files first.", runResult: nil)
                    return
                }
                try await runSplit(
                    diff: diff,
                    source: .staged,
                    config: config,
                    report: report
                )
            } catch let err as AIEngineError {
                handleAIError(err)
            } catch {
                if !(error is CancellationError) {
                    aiErrorDetail = AIErrorDetail(title: "AI error", message: error.localizedDescription, runResult: nil)
                }
            }
        }
    }

    /// Recompose a range of consecutive commits via AI. Combines their diffs,
    /// asks the AI to propose new groups, and on Apply replays the new commits
    /// via an interactive rebase that rewinds the whole range.
    /// Caller passes the commit OIDs in any order; we validate consecutiveness
    /// and surface a clear error if the selection has gaps.
    public func recomposeCommitsWithAI(oids: Set<String>) {
        guard let root else { return }
        guard oids.count >= 2 else { return }
        let config = ConfigStore.shared.config.ai

        // Sort selected OIDs by their position in historyRows (newest-first).
        let indexed = historyRows.enumerated().filter { oids.contains($0.element.commit.oid) }
        guard indexed.count == oids.count else {
            aiErrorDetail = AIErrorDetail(
                title: "Selected commits not in history",
                message: "Some of the selected commits are not in the loaded history range. Scroll the history view down to load more commits, then retry.",
                runResult: nil
            )
            return
        }
        let positions = indexed.map(\.offset).sorted()
        // Consecutive in the newest-first array means each position is exactly
        // one more than the previous.
        let isConsecutive = zip(positions, positions.dropFirst()).allSatisfy { $0 + 1 == $1 }
        guard isConsecutive else {
            aiErrorDetail = AIErrorDetail(
                title: "Selection must be consecutive",
                message: "Multi-commit recompose currently requires the selected commits to be next to each other in history (no gaps).",
                runResult: nil
            )
            return
        }

        // Oldest = highest index in newest-first; newest = lowest index.
        guard let newestIdx = positions.first, let oldestIdx = positions.last else { return }
        let newestOID = historyRows[newestIdx].commit.oid
        let oldestOID = historyRows[oldestIdx].commit.oid
        let orderedOIDs = positions.reversed().map { historyRows[$0].commit.oid }

        aiTask?.cancel()
        aiErrorDetail = nil
        aiSplitPreview = nil
        isAIWorking = true
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAIWorking = false }

            let report = await AICLIValidator.validate(config)
            if Task.isCancelled { return }
            if !report.isValid {
                aiErrorDetail = AIErrorDetail(
                    title: "AI setup not ready",
                    message: report.messages.joined(separator: "\n"),
                    runResult: nil
                )
                return
            }
            do {
                // Combined diff: everything that landed across the range.
                let diff = try await git.commitRangeDiff(oldest: oldestOID, newest: newestOID, in: root)
                try await runSplit(
                    diff: diff,
                    source: .commitRange(oids: orderedOIDs),
                    config: config,
                    report: report
                )
            } catch let err as AIEngineError {
                handleAIError(err)
            } catch {
                if !(error is CancellationError) {
                    aiErrorDetail = AIErrorDetail(title: "AI error", message: error.localizedDescription, runResult: nil)
                }
            }
        }
    }

    public func splitOldCommitWithAI(oid: String) {
        guard let root else { return }
        let config = ConfigStore.shared.config.ai
        aiTask?.cancel()
        aiErrorDetail = nil
        aiSplitPreview = nil
        isAIWorking = true
        aiTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAIWorking = false }

            let report = await AICLIValidator.validate(config)
            if Task.isCancelled { return }
            if !report.isValid {
                aiErrorDetail = AIErrorDetail(
                    title: "AI setup not ready",
                    message: report.messages.joined(separator: "\n"),
                    runResult: nil
                )
                return
            }
            do {
                let diff = try await git.commitDiff(for: oid, in: root)
                try await runSplit(
                    diff: diff,
                    source: .oldCommit(oid: oid),
                    config: config,
                    report: report
                )
            } catch let err as AIEngineError {
                handleAIError(err)
            } catch {
                if !(error is CancellationError) {
                    aiErrorDetail = AIErrorDetail(title: "AI error", message: error.localizedDescription, runResult: nil)
                }
            }
        }
    }

    public func dismissAISplitPreview() {
        aiSplitPreview = nil
    }

    public func applyAISplitPreview() {
        guard let preview = aiSplitPreview, let root else { return }
        let groups = preview.groups
        guard !groups.isEmpty else { return }
        Task { @MainActor in
            do {
                switch preview.source {
                case .staged:
                    try await git.unstageAll(in: root)
                    for group in groups {
                        try await stageGroup(group, in: root)
                        try await git.commit(message: group.message, in: root)
                    }
                case .oldCommit(let oid):
                    try await git.rebaseSingle(commit: oid, action: .edit, in: root)
                    try await git.reset(mode: .mixed, target: "HEAD^", in: root)
                    for group in groups {
                        try await stageGroup(group, in: root)
                        try await git.commit(message: group.message, in: root)
                    }
                    _ = try await git.rebaseContinue(in: root)
                case .commitRange(let oids):
                    // oids are oldest-first; replay span is [oldest..newest].
                    guard let oldest = oids.first, let newest = oids.last else { break }
                    try await git.rebaseRangeEdit(oldest: oldest, newest: newest, in: root)
                    try await git.reset(mode: .mixed, target: "\(oldest)^", in: root)
                    for group in groups {
                        try await stageGroup(group, in: root)
                        try await git.commit(message: group.message, in: root)
                    }
                    _ = try await git.rebaseContinue(in: root)
                }
                aiSplitPreview = nil
                rebaseInProgress = await git.isRebaseInProgress(in: root)
                await refresh()
                await refreshHistory()
            } catch {
                errorMessage = error.localizedDescription
                rebaseInProgress = await git.isRebaseInProgress(in: root)
            }
        }
    }

    public func cancelOngoingRebase() {
        guard let root else { return }
        Task { @MainActor in
            try? await git.rebaseAbort(in: root)
            rebaseInProgress = await git.isRebaseInProgress(in: root)
            await refresh()
            await refreshHistory()
        }
    }

    // MARK: - Split helpers

    private func runSplit(
        diff: String,
        source: AISplitPreview.Source,
        config: AIConfig,
        report: AIValidationReport
    ) async throws {
        let context = PromptContext(
            stagedDiff: diff,
            branch: branch?.name ?? "",
            files: [],
            repo: root?.lastPathComponent ?? "",
            model: config.model,
            lowLimit: config.subjectSoftLimit,
            highLimit: config.subjectHardLimit,
            guideLine: config.bodyWrap
        )
        let prompt = PromptRenderer.render(template: config.splitPromptTemplate, context: context)
        let engine = AIEngineFactory.make(config: config)
        let raw = try await engine.generate(
            prompt: prompt,
            model: config.model,
            temperature: config.temperature,
            maxTokens: config.maxTokens,
            reasoningEffort: config.reasoningEffort
        )
        aiDebugLatestRun = AIRunResult(
            provider: config.backend,
            resolvedExecutable: report.resolvedExecutable ?? "",
            argv: [],
            model: config.model,
            exitCode: 0,
            stdout: raw,
            stderr: "",
            durationMS: 0,
            timedOut: false
        )
        do {
            let groups = try AISplitParser.parse(raw)
            aiSplitPreview = AISplitPreview(source: source, groups: groups)
        } catch let err as AISplitParseError {
            aiErrorDetail = AIErrorDetail(
                title: "Could not parse AI response",
                message: err.errorDescription ?? "Parse failed",
                runResult: aiDebugLatestRun
            )
            openAIDebugDrawer()
        }
    }

    private func stageGroup(_ group: AICommitGroup, in root: URL) async throws {
        guard !group.files.isEmpty else { return }
        // Use stageAll-style call per file; the existing API is per-path.
        for path in group.files {
            try await git.stage(path: path, in: root)
        }
    }

    private func handleAIError(_ err: AIEngineError) {
        if case .cancelled = err { return }
        aiErrorDetail = AIErrorDetail(
            title: errorTitle(for: err),
            message: err.errorDescription ?? "AI error",
            runResult: err.runResult
        )
        if let r = err.runResult {
            aiDebugLatestRun = r
            openAIDebugDrawer()
        }
    }

    private func currentHeadOID() async -> String? {
        historyRows.first?.commit.oid
    }

    /// Strip surrounding triple-backtick fencing and trim whitespace from a
    /// reword response that occasionally arrives wrapped in markdown.
    private static func cleanRewordResponse(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
        }
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AIRewordPreview: Equatable, Sendable {
    public let oid: String
    public let oldMessage: String
    public var proposed: String
}

public struct AISplitPreview: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case staged
        case oldCommit(oid: String)
        /// Range of consecutive commits, oldest-first. Apply uses `git rebase -i`
        /// with the newest commit marked `edit` and a `git reset --mixed <oldest>^`
        /// to roll back the entire range before staging the new groups.
        case commitRange(oids: [String])
    }

    public let source: Source
    public var groups: [AICommitGroup]
}
