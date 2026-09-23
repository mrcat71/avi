import Foundation
import GitKit

// MARK: - Plan editing

public extension RepositoryStore {
    /// Every changed path, in status order. A staged rename appears once, under its new path.
    var planChangedPaths: [String] {
        entries.map(\.path)
    }

    /// Paths a draft may name: every changed path plus the old side of staged renames.
    var changedPathSet: Set<String> {
        Set(entries.map(\.path)).union(entries.compactMap { $0.index == .renamed ? $0.originalPath : nil })
    }

    var unassignedPaths: [String] {
        commitPlan.unassigned(changed: planChangedPaths)
    }

    var selectedDraft: CommitDraft? {
        selectedDraftID.flatMap { commitPlan.draft(id: $0) } ?? commitPlan.drafts.first
    }

    var isApplyingPlan: Bool {
        planProgress != nil
    }

    func issues(of draft: CommitDraft) -> [DraftIssue] {
        commitPlan.issues(of: draft, changed: changedPathSet)
    }

    var canCommitAllDrafts: Bool {
        !commitPlan.isEmpty && !isApplyingPlan && commitPlan.drafts.allSatisfy { issues(of: $0).isEmpty }
    }

    /// The status entry behind a plan path, including the old side of a rename.
    func entry(forPlanPath path: String) -> FileStatus? {
        entries.first { $0.path == path } ?? entries.first { $0.index == .renamed && $0.originalPath == path }
    }

    func showPlan() {
        changesMode = .plan
        hasUnseenProposal = false
        if commitPlan.isEmpty {
            selectedDraftID = commitPlan.addDraft()
        }
    }

    func showFiles() {
        changesMode = .files
        // A draft you opened but never used is not worth keeping.
        commitPlan.drafts.removeAll { $0.source == .manual && $0.files.isEmpty && $0.message.isEmpty }
    }

    func selectDraft(_ id: UUID) {
        selectedDraftID = id
    }

    /// Shows the complete change a draft would commit: the working-tree copy against HEAD.
    func selectPlanFile(_ path: String) async {
        guard let file = entry(forPlanPath: path) else {
            await select(nil)
            return
        }
        let source: DiffSource
        if file.isUntracked {
            source = .untracked
        } else if file.isStaged, file.hasUnstagedChanges {
            source = branch?.isUnborn == false ? .head : .unstaged
        } else if file.isStaged {
            source = .staged
        } else {
            source = .unstaged
        }
        await select(file, source: source)
    }

    func setMessage(_ message: String, forDraft id: UUID) {
        commitPlan.setMessage(message, for: id)
    }

    func addDraft() {
        selectedDraftID = commitPlan.addDraft()
    }

    func moveFiles(_ paths: [String], to target: DraftMoveTarget) {
        if let id = commitPlan.move(withRenamePartners(paths), to: target), target == .newDraft {
            selectedDraftID = id
        }
    }

    func deleteDraft(_ id: UUID) {
        commitPlan.removeDraft(id: id)
        if selectedDraftID == id {
            selectedDraftID = commitPlan.drafts.first?.id
        }
        if commitPlan.isEmpty {
            changesMode = .files
        }
    }

    func moveDraft(_ id: UUID, by offset: Int) {
        commitPlan.moveDraft(id: id, by: offset)
    }

    func discardDrafts(from source: DraftSource) {
        commitPlan.replaceDrafts(from: source, with: [])
        if commitPlan.isEmpty {
            discardPlan()
        } else if selectedDraft == nil || selectedDraftID.flatMap({ commitPlan.draft(id: $0) }) == nil {
            selectedDraftID = commitPlan.drafts.first?.id
        }
    }

    func discardPlan() {
        commitPlan = CommitPlan()
        selectedDraftID = nil
        planNotice = nil
        changesMode = .files
    }

    // MARK: Applying

    func commitAllDrafts() async {
        await commitDrafts(commitPlan.drafts.map(\.id))
    }

    func commitDrafts(from source: DraftSource) async {
        await commitDrafts(commitPlan.drafts(from: source).map(\.id))
    }

    /// Commits the chosen drafts in plan order. Drafts committed before a
    /// failure leave the plan; the rest stay so nothing you wrote is lost.
    func commitDrafts(_ ids: [UUID]) async {
        guard let root, !isApplyingPlan else { return }
        let chosen = Set(ids)
        let ordered = commitPlan.drafts.filter { chosen.contains($0.id) }.map(\.id)
        guard !ordered.isEmpty else { return }
        let plan = commitPlan.fileCommitPlan(for: ordered)
        planProgress = PlanProgress(completed: 0, total: ordered.count)
        var failure: String?
        do {
            try await git.commitFiles(plan, in: root) { [weak self] completed in
                Task { @MainActor in self?.planProgress?.completed = completed }
            }
            commitPlan.removeDrafts(ids: Set(ordered))
        } catch let error as CommitPlanError {
            commitPlan.removeDrafts(ids: Set(ordered.prefix(error.completed)))
            failure = error.localizedDescription
        } catch {
            failure = error.localizedDescription
        }
        planProgress = nil
        if let selectedDraftID, commitPlan.draft(id: selectedDraftID) == nil {
            self.selectedDraftID = commitPlan.drafts.first?.id
        }
        if commitPlan.isEmpty {
            changesMode = .files
            planNotice = nil
        }
        await refresh()
        // After the refresh, which clears errors from earlier reads.
        if let failure {
            errorMessage = failure
        }
    }

    // MARK: One at a time

    /// Commits one draft, then moves on to the draft that followed it.
    func commitDraft(_ id: UUID) async {
        let order = commitPlan.drafts.map(\.id)
        await commitDrafts([id])
        guard commitPlan.draft(id: id) == nil, let index = order.firstIndex(of: id) else { return }
        selectedDraftID = order[(index + 1)...].first { commitPlan.draft(id: $0) != nil } ?? commitPlan.drafts.first?.id
    }

    func mergeDraft(_ id: UUID, withNext next: Bool) {
        if let survivor = commitPlan.merge(id, withNext: next) {
            selectedDraftID = survivor
        }
    }

    // MARK: AI help

    var canUseAIForPlan: Bool {
        ConfigStore.shared.config.ai.enabled
    }

    var isRevisingPlan: Bool {
        !revisingDraftIDs.isEmpty
    }

    /// Opens the sheet where you tell the AI how to rework `ids`.
    func requestRevision(of ids: [UUID], suggestion: String = "") {
        let drafts = commitPlan.drafts
        let title: String
        if ids.count == drafts.count, drafts.count > 1 {
            title = "All \(drafts.count) commits"
        } else if ids.count == 1, let index = drafts.firstIndex(where: { $0.id == ids[0] }) {
            let subject = drafts[index].subject
            title = "Commit \(index + 1)" + (subject.isEmpty ? "" : ": \(subject)")
        } else {
            title = "\(ids.count) commits"
        }
        revisionRequest = PlanRevisionRequest(draftIDs: ids, title: title, suggestion: suggestion)
    }

    func cancelPlanAI() {
        planAITask?.cancel()
        planAITask = nil
        revisingDraftIDs = []
    }

    /// Asks the AI to rework the drafts `ids` as `instructions` say: split,
    /// merge, regroup, or rewrite messages. The answer replaces those drafts in
    /// place; files the AI leaves out go to Not in Plan.
    func reviseDrafts(_ ids: [UUID], instructions: String) {
        let targets = commitPlan.drafts.filter { ids.contains($0.id) }
        guard let root, !targets.isEmpty else { return }
        let config = ConfigStore.shared.config.ai
        planAITask?.cancel()
        revisingDraftIDs = Set(targets.map(\.id))
        planNotice = nil
        planAITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.revisingDraftIDs = [] }
            do {
                let files = targets.flatMap(\.files)
                let diff = try await git.workingTreeDiff(paths: files, in: root)
                let context = PromptContext(
                    stagedDiff: Self.clipped(diff),
                    branch: branch?.name ?? "",
                    files: files,
                    repo: root.lastPathComponent,
                    model: config.model,
                    lowLimit: config.subjectSoftLimit,
                    highLimit: config.subjectHardLimit,
                    guideLine: config.bodyWrap,
                    instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                    plan: Self.planJSON(targets)
                )
                guard let raw = try await askAI(PromptRenderer.render(template: config.planRevisionPromptTemplate, context: context), config: config) else { return }
                let groups = try AISplitParser.parse(raw)
                // Revise only what is still in the plan; you may have edited it meanwhile.
                let still = targets.map(\.id).filter { commitPlan.draft(id: $0) != nil }
                let outcome = commitPlan.applyRevision(groups.map { ($0.files, $0.message) }, replacing: still)
                guard let first = outcome.created.first else {
                    planNotice = "The AI's answer had no usable commits, so nothing changed."
                    return
                }
                selectedDraftID = first
                planNotice = Self.describe(outcome, revised: still.count)
            } catch {
                report(aiFailure: error, doing: "revise the commits")
            }
        }
    }

    /// Writes a fresh message for one draft from exactly its files' changes.
    func improveMessage(forDraft id: UUID) {
        guard let root, let draft = commitPlan.draft(id: id), !draft.files.isEmpty else { return }
        let config = ConfigStore.shared.config.ai
        planAITask?.cancel()
        revisingDraftIDs = [id]
        planNotice = nil
        planAITask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.revisingDraftIDs = [] }
            do {
                let diff = try await git.workingTreeDiff(paths: draft.files, in: root)
                let context = PromptContext(
                    stagedDiff: Self.clipped(diff),
                    branch: branch?.name ?? "",
                    files: draft.files,
                    repo: root.lastPathComponent,
                    model: config.model,
                    lowLimit: config.subjectSoftLimit,
                    highLimit: config.subjectHardLimit,
                    guideLine: config.bodyWrap
                )
                guard let raw = try await askAI(PromptRenderer.render(template: config.promptTemplate, context: context), config: config) else { return }
                let (subject, body) = splitGeneratedMessage(raw)
                guard !subject.isEmpty, commitPlan.draft(id: id) != nil else { return }
                commitPlan.setMessage(CommitMessageParts.join(summary: subject, body: body), for: id)
            } catch {
                report(aiFailure: error, doing: "write the message")
            }
        }
    }
}

extension RepositoryStore {
    /// Runs one AI request with the configured backend. Nil, with the reason in
    /// the plan's notice, when the AI setup is not ready or the task was cancelled.
    private func askAI(_ prompt: String, config: AIConfig) async throws -> String? {
        let report = await AICLIValidator.validate(config)
        try Task.checkCancellation()
        guard report.isValid else {
            planNotice = "AI is not ready: " + report.messages.joined(separator: " ")
            return nil
        }
        // Plans name many files; the reply needs room even when the message limit is small.
        let raw = try await AIEngineFactory.make(config: config).generate(
            prompt: prompt,
            model: config.model,
            temperature: config.temperature,
            maxTokens: max(config.maxTokens, 4000),
            reasoningEffort: config.reasoningEffort
        )
        try Task.checkCancellation()
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
        return raw
    }

    private func report(aiFailure error: Error, doing task: String) {
        if error is CancellationError {
            return
        }
        if let engine = error as? AIEngineError {
            if case .cancelled = engine {
                return
            }
            if let run = engine.runResult {
                aiDebugLatestRun = run
            }
            planNotice = "The AI could not \(task): \(engine.errorDescription ?? "unknown error")"
            return
        }
        planNotice = "The AI could not \(task): \(error.localizedDescription)"
    }

    /// Diffs past this size are cut, so one huge file cannot crowd out the rest.
    static let aiDiffLimit = 150_000

    static func clipped(_ diff: String) -> String {
        guard diff.count > aiDiffLimit else { return diff }
        return String(diff.prefix(aiDiffLimit)) + "\n[diff truncated]\n"
    }

    static func planJSON(_ drafts: [CommitDraft]) -> String {
        struct Entry: Encodable {
            let message: String
            let files: [String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = (try? encoder.encode(drafts.map { Entry(message: $0.message, files: $0.files) })) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func describe(_ outcome: CommitPlan.RevisionOutcome, revised count: Int) -> String {
        let made = outcome.created.count
        var parts = ["The AI turned \(count == 1 ? "1 commit" : "\(count) commits") into \(made == 1 ? "1" : "\(made)")."]
        if !outcome.leftOut.isEmpty {
            parts.append("Moved to Not in Plan: \(outcome.leftOut.joined(separator: ", ")).")
        }
        if !outcome.dropped.isEmpty {
            parts.append("Ignored paths outside these commits: \(outcome.dropped.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }
}

extension RepositoryStore {
    // MARK: AI split

    /// Turns an AI split of the staged changes into drafts. Files the AI named
    /// that are not staged, or that another draft already holds, are left out.
    func adoptAISplit(_ groups: [AICommitGroup]) {
        let staged = Set(stagedEntries.flatMap { [$0.path] + ($0.index == .renamed ? [$0.originalPath].compactMap(\.self) : []) })
        var taken = Set(commitPlan.drafts.filter { $0.source != .ai }.flatMap(\.files))
        var dropped: [String] = []
        var drafts: [CommitDraft] = []
        for group in groups {
            var files: [String] = []
            for path in group.files {
                if staged.contains(path), taken.insert(path).inserted {
                    files.append(path)
                } else if !files.contains(path) {
                    dropped.append(path)
                }
            }
            if !files.isEmpty {
                drafts.append(CommitDraft(message: group.message, files: files, source: .ai))
            }
        }
        commitPlan.replaceDrafts(from: .ai, with: drafts)
        changesMode = .plan
        // The split ran in the background; you may have moved on meanwhile.
        // Changes clears this as soon as you are looking at it.
        hasUnseenProposal = true
        selectedDraftID = drafts.first?.id ?? commitPlan.drafts.first?.id
        planNotice = dropped.isEmpty
            ? nil
            : "Left out paths that are not staged or already belong to another draft: \(dropped.joined(separator: ", "))"
    }
}

// MARK: - Agent proposals

/// A proposal an agent sent over the control socket.
public struct AgentProposal: Equatable, Sendable {
    public struct Commit: Equatable, Sendable {
        public let message: String
        public let files: [String]

        public init(message: String, files: [String]) {
            self.message = message
            self.files = files
        }
    }

    public let agent: String
    public let session: String
    public let title: String?
    public let commits: [Commit]
    /// Replace this session's earlier proposal even after you edited it.
    public let replace: Bool

    public init(agent: String, session: String, title: String?, commits: [Commit], replace: Bool) {
        self.agent = agent
        self.session = session
        self.title = title
        self.commits = commits
        self.replace = replace
    }

    public var source: DraftSource {
        .agent(name: agent, session: session, title: title)
    }
}

public enum ProposalPlacement: String, Codable, Sendable {
    case commitField
    case previewCard
    case plan
}

public struct ProposalOutcome: Equatable, Sendable {
    public let placement: ProposalPlacement
    public let commits: Int
    public let staged: [String]
    public let notes: [String]
}

/// Why a proposal was refused. Nothing in the repository changed.
public enum ProposalRejection: Error, Equatable, Sendable {
    case noCommits
    case emptyMessage(commit: Int)
    case filesRequired(commit: Int)
    case unknownPaths([String], changed: [String])
    case duplicatePaths([String])
    case conflicts([String])
    case fileClaimed([String: String])
    case editedByUser
    case busy
}

extension ProposalRejection: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noCommits:
            return "The proposal has no commits."
        case .emptyMessage(let commit):
            return "Commit \(commit) needs a message."
        case .filesRequired(let commit):
            return "Commit \(commit) needs files. Only a single commit may leave files out to fill the message alone."
        case .unknownPaths(let paths, _):
            return "These paths have no changes: \(paths.joined(separator: ", "))"
        case .duplicatePaths(let paths):
            return "Each file can be in only one commit: \(paths.joined(separator: ", "))"
        case .conflicts(let paths):
            return "The repository has unresolved conflicts: \(paths.joined(separator: ", "))"
        case .fileClaimed(let owners):
            let list = owners.keys.sorted().map { "\($0) (\(owners[$0] ?? "?"))" }
            return "Another pending proposal already holds: \(list.joined(separator: ", "))"
        case .editedByUser:
            return "Your earlier proposal was edited in Avi. Ask the user before replacing it."
        case .busy:
            return "Avi is committing in this repository. Try again shortly."
        }
    }
}

public extension RepositoryStore {
    /// Places an agent proposal. A single commit goes to the commit field when
    /// nothing else is pending and nothing else is staged; everything else
    /// becomes plan drafts. A session replaces only its own earlier proposal.
    /// `revealPlan` switches the Changes view to the plan when drafts arrive,
    /// which callers skip while you are looking at this repository.
    func receiveProposal(_ proposal: AgentProposal, revealPlan: Bool) async throws -> ProposalOutcome {
        guard let root, !isApplyingPlan, !isApplyingAISplit else { throw ProposalRejection.busy }
        guard !proposal.commits.isEmpty else { throw ProposalRejection.noCommits }
        for (index, commit) in proposal.commits.enumerated() {
            if commit.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ProposalRejection.emptyMessage(commit: index + 1)
            }
            if proposal.commits.count > 1, commit.files.isEmpty {
                throw ProposalRejection.filesRequired(commit: index + 1)
            }
        }

        await refresh()
        let conflicted = entries.filter { $0.index == .updatedButUnmerged || $0.worktree == .updatedButUnmerged }
        guard conflicted.isEmpty else { throw ProposalRejection.conflicts(conflicted.map(\.path)) }

        let commits = proposal.commits.map { commit in
            AgentProposal.Commit(
                message: commit.message.trimmingCharacters(in: .whitespacesAndNewlines),
                files: withRenamePartners(commit.files)
            )
        }
        let listed = commits.flatMap(\.files)
        let changed = changedPathSet
        let unknown = orderedUnique(listed.filter { !changed.contains($0) })
        guard unknown.isEmpty else { throw ProposalRejection.unknownPaths(unknown, changed: planChangedPaths) }
        var seen = Set<String>()
        let duplicates = orderedUnique(listed.filter { !seen.insert($0).inserted })
        guard duplicates.isEmpty else { throw ProposalRejection.duplicatePaths(duplicates) }

        let source = proposal.source
        let listedSet = Set(listed)
        var owners: [String: String] = [:]
        for draft in commitPlan.drafts where draft.source.groupKey != source.groupKey {
            for path in draft.files where listedSet.contains(path) {
                owners[path] = draft.source.displayName
            }
        }
        let ownField = fieldProposal?.source.groupKey == source.groupKey ? fieldProposal : nil
        if let other = fieldProposal, ownField == nil {
            for path in other.files where listedSet.contains(path) {
                owners[path] = other.source.displayName
            }
        }
        guard owners.isEmpty else { throw ProposalRejection.fileClaimed(owners) }

        if !proposal.replace {
            let ownDraftsEdited = commitPlan.drafts(from: source).contains(where: \.isEdited)
            if ownDraftsEdited || ownField.map(fieldWasEdited) == true {
                throw ProposalRejection.editedByUser
            }
        }

        let othersPending = commitPlan.drafts.contains { $0.source.groupKey != source.groupKey }
        let otherField = fieldProposal != nil && ownField == nil
        let ownStaged = Set(ownField?.stagedByAvi ?? [])
        let stagedElsewhere = stagedEntries.contains { entry in
            !listedSet.contains(entry.path) && !ownStaged.contains(entry.path)
        }

        // A message without files is for whatever is staged, so staged files are expected.
        let messageOnly = commits.count == 1 && commits[0].files.isEmpty
        if commits.count == 1, !othersPending, !otherField, messageOnly || !stagedElsewhere {
            if revealPlan {
                reveal(.files)
            }
            return try await placeInCommitField(commits[0], source: source, previous: ownField, root: root)
        }

        let commit = commits[0]
        if messageOnly {
            // Nothing to draft without files; the message waits for you.
            let (subject, body) = splitGeneratedMessage(commit.message)
            aiPendingPreview = AIPendingPreview(subject: subject, body: body, result: Self.proposalRun(for: proposal.agent), proposedBy: proposal.agent)
            hasUnseenProposal = true
            if revealPlan {
                reveal(.files)
            }
            return ProposalOutcome(placement: .previewCard, commits: 1, staged: [], notes: [])
        }

        var notes: [String] = []
        if let field = fieldProposal {
            await withdrawFieldProposal(field, keepAsDraft: field.source.groupKey != source.groupKey)
            if field.source.groupKey != source.groupKey {
                notes.append("Moved \(field.source.displayName)'s proposal from the commit field into the plan.")
            }
        }
        let drafts = commits.map { CommitDraft(message: $0.message, files: $0.files, source: source) }
        commitPlan.replaceDrafts(from: source, with: drafts)
        hasUnseenProposal = true
        if revealPlan {
            reveal(.plan)
            selectedDraftID = drafts.first?.id
        }
        return ProposalOutcome(placement: .plan, commits: drafts.count, staged: [], notes: notes)
    }

    /// Withdraws the agent proposal in the commit field: unstages what Avi
    /// staged for it and clears its message.
    func discardFieldProposal() async {
        guard let field = fieldProposal else { return }
        let failure = await withdrawFieldProposal(field, keepAsDraft: false)
        await refresh()
        if let failure {
            errorMessage = failure
        }
    }

    /// Staged files that the proposal in the commit field did not ask for.
    var stagedOutsideFieldProposal: [String] {
        guard let field = fieldProposal else { return [] }
        let proposed = Set(field.files)
        return stagedEntries.map(\.path).filter { !proposed.contains($0) }
    }

    func unstageOutsideFieldProposal() async {
        let extra = stagedOutsideFieldProposal
        guard !extra.isEmpty, let root else { return }
        var failure: String?
        do {
            try await git.unstage(paths: extra, in: root)
        } catch {
            failure = error.localizedDescription
        }
        await refresh()
        if let failure {
            errorMessage = failure
        }
    }
}

extension RepositoryStore {
    private func placeInCommitField(
        _ commit: AgentProposal.Commit,
        source: DraftSource,
        previous: FieldProposal?,
        root: URL
    ) async throws -> ProposalOutcome {
        commitPlan.replaceDrafts(from: source, with: [])
        let alreadyStaged = Set(stagedEntries.map(\.path))
        var stagedByAvi = commit.files.filter { !alreadyStaged.contains($0) }
        if let previous {
            // Files the earlier proposal staged that this one dropped go back.
            let dropped = previous.stagedByAvi.filter { !commit.files.contains($0) }
            if !dropped.isEmpty {
                try await git.unstage(paths: dropped, in: root)
            }
            stagedByAvi = orderedUnique(stagedByAvi + previous.stagedByAvi.filter { commit.files.contains($0) })
        }
        if !commit.files.isEmpty {
            try await git.stage(paths: commit.files, in: root)
        }

        let (subject, body) = splitGeneratedMessage(commit.message)
        let fieldHoldsYourText = previous?.inField != true && !commitMessage.isEmpty
        let placement: ProposalPlacement
        if fieldHoldsYourText {
            aiPendingPreview = AIPendingPreview(subject: subject, body: body, result: Self.proposalRun(for: source.displayName), proposedBy: source.displayName)
            placement = .previewCard
        } else {
            commitSummary = subject
            commitBody = body
            amend = false
            placement = .commitField
        }
        fieldProposal = FieldProposal(
            source: source,
            files: commit.files,
            message: commit.message,
            stagedByAvi: stagedByAvi,
            inField: placement == .commitField
        )
        hasUnseenProposal = true
        await refresh()
        return ProposalOutcome(placement: placement, commits: 1, staged: commit.files, notes: [])
    }

    /// Takes a proposal out of the commit field, optionally keeping it as the
    /// first plan draft, and unstages what Avi staged for it. Returns why the
    /// unstaging failed, for the caller to show once its refresh is done.
    @discardableResult
    private func withdrawFieldProposal(_ field: FieldProposal, keepAsDraft: Bool) async -> String? {
        let edited = fieldWasEdited(field)
        let message = field.inField && !commitMessage.isEmpty ? commitMessage : field.message
        if field.inField {
            commitSummary = ""
            commitBody = ""
        } else if aiPendingPreview?.proposedBy != nil {
            aiPendingPreview = nil
        }
        fieldProposal = nil
        if keepAsDraft, !field.files.isEmpty {
            commitPlan.drafts.insert(CommitDraft(message: message, files: field.files, source: field.source, isEdited: edited), at: 0)
        }
        guard let root, !field.stagedByAvi.isEmpty else { return nil }
        do {
            try await git.unstage(paths: field.stagedByAvi, in: root)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Leaves this repository on Changes, in the mode that shows the proposal,
    /// for when you come back to it. Only called while you are not looking.
    private func reveal(_ mode: ChangesMode) {
        workspaceSelection = .localChanges
        changesMode = mode
    }

    func fieldWasEdited(_ field: FieldProposal) -> Bool {
        field.inField && commitMessage.trimmingCharacters(in: .whitespacesAndNewlines) != field.message
    }

    /// Both sides of a staged rename travel together.
    func withRenamePartners(_ paths: [String]) -> [String] {
        var result: [String] = []
        for path in paths {
            result.append(path)
            if let entry = entries.first(where: { $0.path == path && $0.index == .renamed }), let original = entry.originalPath {
                result.append(original)
            } else if let entry = entries.first(where: { $0.originalPath == path && $0.index == .renamed }) {
                result.append(entry.path)
            }
        }
        return orderedUnique(result)
    }

    static func proposalRun(for agent: String) -> AIRunResult {
        AIRunResult(provider: "agent", resolvedExecutable: agent, argv: [], model: "", exitCode: 0, stdout: "", stderr: "", durationMS: 0, timedOut: false)
    }
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}
