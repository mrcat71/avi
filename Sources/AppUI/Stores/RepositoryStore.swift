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
    public private(set) var remotes: [GitRemote] = []
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
            remotes = []
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
            } else {
                refs = .empty
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

    public func setHistoryFilter(_ filter: HistoryFilter) async {
        historyFilter = filter
        await refreshHistory()
    }

    public func refreshHistory(limit: Int = 200) async {
        guard let root else { return }
        isHistoryLoading = true
        defer { isHistoryLoading = false }

        do {
            let commits = try await git.history(in: root, limit: limit, filter: historyFilter)
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
                    maxTokens: config.maxTokens
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
                aiPendingPreview = AIPendingPreview(subject: subject, body: body, result: runResult)
                aiDebugLatestRun = runResult
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
}
