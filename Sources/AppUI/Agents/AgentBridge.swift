import AppKit
import Foundation
import GitKit
import Observation

/// Serves the control socket: routes each agent request to the window and
/// repository it names, and keeps requests for one repository in order while
/// different repositories proceed side by side.
@MainActor
@Observable
public final class AgentBridge {
    public static let shared = AgentBridge()

    public enum ServerState: Equatable, Sendable {
        case stopped
        case listening(path: String)
        case servedElsewhere(path: String)
        case failed(String)
    }

    public private(set) var state: ServerState = .stopped

    /// A repository an agent asked for that you have not opened in Avi yet.
    /// Avi asks you before touching it; the agent sends again afterwards.
    public struct OpenApproval: Identifiable, Equatable, Sendable {
        public let id = UUID()
        /// Shown to you; control characters replaced.
        public let path: String
        public let requester: String
        /// Opened when you approve.
        let root: URL
    }

    public private(set) var pendingApproval: OpenApproval?

    @ObservationIgnored private var sessions: [WeakSession] = []
    @ObservationIgnored private var server: AgentSocketServer?
    @ObservationIgnored private var chains: [String: Chain] = [:]
    @ObservationIgnored private var observingConfig = false
    @ObservationIgnored private let socketPath: String
    @ObservationIgnored private let appVersion: String
    /// Whether agents may talk to Avi. Tests replace it; the app reads the config.
    @ObservationIgnored var isEnabled: @MainActor () -> Bool = { ConfigStore.shared.config.agents.enabled }
    /// Repositories you opened in Avi before. Opening a repository runs Git in
    /// it, and a repository's own config can make Git run any command, so an
    /// agent (possibly a sandboxed one) must never pick a new repository alone.
    @ObservationIgnored var isKnownRepository: @MainActor (String) -> Bool = { path in
        RecentRepositories.paths().contains { AgentBridge.canonicalPath(URL(fileURLWithPath: $0)) == path }
    }

    private struct WeakSession {
        weak var session: WorkspaceSession?
    }

    private struct Chain {
        let id: UUID
        let tail: Task<Void, Never>
    }

    init(socketPath: String = AgentProtocol.socketPath(), appVersion: String = GitKit.version) {
        self.socketPath = socketPath
        self.appVersion = appVersion
    }

    // MARK: - Lifecycle

    /// Starts or stops the socket to match the config, now and whenever the
    /// config changes, including edits made to the file by hand.
    public func start() {
        syncWithConfig()
        observeConfig()
    }

    public func stop() {
        server?.stop()
        server = nil
        state = .stopped
    }

    private func observeConfig() {
        guard !observingConfig else { return }
        observingConfig = true
        withObservationTracking {
            _ = ConfigStore.shared.config.agents.enabled
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                observingConfig = false
                syncWithConfig()
                observeConfig()
            }
        }
    }

    private func syncWithConfig() {
        let enabled = ConfigStore.shared.config.agents.enabled
        if enabled, server == nil {
            startServer()
        } else if !enabled {
            stop()
        }
    }

    private func startServer() {
        let server = AgentSocketServer(path: socketPath) { [weak self] data in
            await self?.respond(to: data) ?? Data()
        }
        do {
            try server.start()
            self.server = server
            state = .listening(path: socketPath)
        } catch AgentSocketError.servedElsewhere(let path) {
            state = .servedElsewhere(path: path)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Windows

    func register(_ session: WorkspaceSession) {
        sessions.removeAll { $0.session == nil || $0.session === session }
        sessions.append(WeakSession(session: session))
    }

    func unregister(_ session: WorkspaceSession) {
        sessions.removeAll { $0.session == nil || $0.session === session }
        updateDockBadge()
    }

    private var liveSessions: [WorkspaceSession] {
        sessions.compactMap(\.session)
    }

    /// Every open repository across windows, for Settings and `status`.
    var openRepositories: [RepositoryStore] {
        liveSessions.flatMap(\.repositories)
    }

    /// The Dock badge counts repositories with a proposal you have not looked at.
    func updateDockBadge() {
        let count = openRepositories.filter(\.hasUnseenProposal).count
        NSApp?.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // MARK: - Requests

    nonisolated func respond(to data: Data) async -> Data {
        let response: AgentResponse
        if let request = try? JSONDecoder().decode(AgentRequest.self, from: data) {
            response = await handle(request)
        } else {
            response = .failure(Self.malformed(data))
        }
        return (try? AgentProtocol.encoder.encode(response)) ?? Data(#"{"ok":false,"v":1}"#.utf8)
    }

    func handle(_ request: AgentRequest) async -> AgentResponse {
        guard request.v == AgentProtocol.version else {
            return .failure(AgentErrorBody(code: .unsupportedVersion, message: "This Avi speaks protocol \(AgentProtocol.version); update the avi command or the app."))
        }
        guard isEnabled() else {
            return .failure(AgentErrorBody(code: .disabled, message: "Agent proposals are turned off in Avi > Settings > Agents."))
        }
        switch request.method {
        case .status:
            return status(request.params)
        case .open:
            return await open(request.params)
        case .propose:
            return await propose(request.params)
        }
    }

    private func status(_ params: AgentParams) -> AgentResponse {
        var result = AgentResult(app: appInfo, repositories: openRepositories.compactMap(Self.status(of:)))
        if let repo = params.repo {
            let root = URL(fileURLWithPath: repo)
            result.repo = store(at: root).flatMap(Self.status(of:))
                ?? AgentRepoStatus(path: Self.canonicalPath(root), open: false)
        }
        return .success(result)
    }

    private func open(_ params: AgentParams) async -> AgentResponse {
        guard let repo = params.repo, repo.hasPrefix("/") else {
            return .failure(AgentErrorBody(code: .badRequest, message: "`repo` must be an absolute path."))
        }
        let root = URL(fileURLWithPath: repo)
        return await serialized(Self.canonicalPath(root)) { [self] in
            switch await locateOrOpen(root, requester: Self.nonEmpty(params.agent) ?? "the avi command") {
            case .failure(let error):
                return .failure(error)
            case .success(let (session, store)):
                if params.focus == true {
                    focus(store, in: session, showPlan: false)
                }
                return .success(AgentResult(app: appInfo, repo: Self.status(of: store)))
            }
        }
    }

    private func propose(_ params: AgentParams) async -> AgentResponse {
        guard let repo = params.repo, repo.hasPrefix("/") else {
            return .failure(AgentErrorBody(code: .badRequest, message: "`repo` must be an absolute path."))
        }
        guard let commits = params.commits, !commits.isEmpty else {
            return .failure(AgentErrorBody(code: .noCommits, message: "The proposal has no commits."))
        }
        let root = URL(fileURLWithPath: repo)
        let canonicalRoot = Self.canonicalPath(root)
        let proposal = AgentProposal(
            agent: Self.nonEmpty(params.agent) ?? "Agent",
            session: Self.nonEmpty(params.session) ?? "default",
            title: Self.nonEmpty(params.title),
            commits: commits.map { commit in
                AgentProposal.Commit(message: commit.message, files: (commit.files ?? []).map { Self.relativePath($0, root: canonicalRoot) })
            },
            replace: params.replace ?? false
        )
        return await serialized(canonicalRoot) { [self] in
            switch await locateOrOpen(root, requester: proposal.agent) {
            case .failure(let error):
                return .failure(error)
            case .success(let (session, store)):
                do {
                    let outcome = try await store.receiveProposal(proposal, revealPlan: !isVisible(store, in: session))
                    if params.focus == true {
                        focus(store, in: session, showPlan: outcome.placement == .plan)
                    } else if let app = NSApp, !app.isActive {
                        app.requestUserAttention(.informationalRequest)
                    }
                    updateDockBadge()
                    return .success(AgentResult(
                        app: appInfo,
                        placement: outcome.placement,
                        commits: outcome.commits,
                        staged: outcome.staged,
                        notes: outcome.notes,
                        repo: Self.status(of: store)
                    ))
                } catch let rejection as ProposalRejection {
                    return .failure(AgentErrorBody(rejection))
                } catch {
                    return .failure(AgentErrorBody(code: .failed, message: error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Helpers

    private var appInfo: AgentAppInfo {
        AgentAppInfo(version: appVersion)
    }

    private func store(at root: URL) -> RepositoryStore? {
        liveSessions.lazy.compactMap { $0.repository(at: root) }.first
    }

    private func locateOrOpen(_ root: URL, requester: String) async -> Result<(WorkspaceSession, RepositoryStore), AgentErrorBody> {
        for session in liveSessions {
            if let store = session.repository(at: root) {
                return .success((session, store))
            }
        }
        guard let session = liveSessions.first else {
            return .failure(AgentErrorBody(code: .noWindow, message: "Avi has no open window yet."))
        }
        let path = Self.canonicalPath(root)
        guard isKnownRepository(path) else {
            pendingApproval = OpenApproval(
                path: Self.displaySafe(path, limit: 300),
                requester: Self.displaySafe(requester, limit: 40),
                root: URL(fileURLWithPath: path, isDirectory: true)
            )
            if let app = NSApp, !app.isActive {
                app.requestUserAttention(.informationalRequest)
            }
            return .failure(AgentErrorBody(
                code: .notTrusted,
                message: "Avi works only with repositories you have opened in it. Avi is asking you to confirm opening \(path); send again once you have."
            ))
        }
        guard let store = await session.openInBackground(root) else {
            return .failure(AgentErrorBody(code: .notARepository, message: "\(root.path) is not a Git repository."))
        }
        return .success((session, store))
    }

    /// Whether this window shows approval prompts, so only one window asks.
    func presentsApprovals(in session: WorkspaceSession) -> Bool {
        liveSessions.first === session
    }

    /// Your answer to `pendingApproval`. Opening makes the repository known,
    /// so the agent's next request goes through.
    func resolveApproval(open: Bool, in session: WorkspaceSession) {
        guard let approval = pendingApproval else { return }
        pendingApproval = nil
        guard open else { return }
        Task { await session.open(approval.root) }
    }

    /// True when you are looking at this repository's Changes right now.
    private func isVisible(_ store: RepositoryStore, in session: WorkspaceSession) -> Bool {
        (NSApp?.isActive ?? false) && session.selectedRepository?.id == store.id && store.workspaceSelection == .localChanges
    }

    private func focus(_ store: RepositoryStore, in session: WorkspaceSession, showPlan: Bool) {
        session.select(store.id)
        store.workspaceSelection = .localChanges
        if showPlan {
            store.selectedDraftID = store.commitPlan.drafts.first?.id
        }
        store.hasUnseenProposal = false
        NSApp?.activate(ignoringOtherApps: true)
        updateDockBadge()
    }

    /// Runs `body` after every earlier request for the same repository.
    private func serialized(_ key: String, _ body: @escaping @MainActor () async -> AgentResponse) async -> AgentResponse {
        let previous = chains[key]?.tail
        let id = UUID()
        let task = Task { @MainActor () -> AgentResponse in
            await previous?.value
            return await body()
        }
        chains[key] = Chain(id: id, tail: Task { _ = await task.value })
        let response = await task.value
        if chains[key]?.id == id {
            chains.removeValue(forKey: key)
        }
        return response
    }

    static func status(of store: RepositoryStore) -> AgentRepoStatus? {
        guard let root = store.root else { return nil }
        let drafts = store.commitPlan.drafts.map { draft in
            pending(source: draft.source, subject: draft.subject, files: draft.files, edited: draft.isEdited)
        }
        let field = store.fieldProposal.map { proposal in
            pending(source: proposal.source, subject: CommitMessageParts.split(proposal.message).summary, files: proposal.files, edited: store.fieldWasEdited(proposal))
        }
        return AgentRepoStatus(
            path: canonicalPath(root),
            open: true,
            branch: store.branch?.name,
            staged: store.stagedEntries.count,
            unstaged: store.entries.filter { $0.hasUnstagedChanges && !$0.isUntracked }.count,
            untracked: store.entries.filter(\.isUntracked).count,
            commitFieldInUse: !store.commitMessage.isEmpty,
            commitField: field,
            drafts: drafts
        )
    }

    private static func pending(source: DraftSource, subject: String, files: [String], edited: Bool) -> AgentPendingDraft {
        switch source {
        case .agent(let name, let session, _):
            return AgentPendingDraft(source: "agent", agent: name, session: session, subject: subject, files: files, edited: edited)
        case .ai:
            return AgentPendingDraft(source: "ai", subject: subject, files: files, edited: edited)
        case .manual:
            return AgentPendingDraft(source: "manual", subject: subject, files: files, edited: edited)
        }
    }

    /// Request text shown in a trust prompt: control characters and line
    /// breaks become "?", so a crafted folder name cannot add lines to it.
    static func displaySafe(_ text: String, limit: Int) -> String {
        let cleaned = String(text.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? "?" : Character(scalar)
        })
        return cleaned.count > limit ? String(cleaned.prefix(limit - 1)) + "…" : cleaned
    }

    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Accepts `./path` and absolute paths inside the repository as well as the
    /// documented root-relative form.
    static func relativePath(_ path: String, root: String) -> String {
        if path.hasPrefix("/") {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
            return resolved.hasPrefix(prefix) ? String(resolved.dropFirst(prefix.count)) : path
        }
        var relative = path
        while relative.hasPrefix("./") {
            relative.removeFirst(2)
        }
        return relative
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private nonisolated static func malformed(_ data: Data) -> AgentErrorBody {
        struct Probe: Decodable {
            let v: Int?
            let method: String?
        }
        guard let probe = try? JSONDecoder().decode(Probe.self, from: data) else {
            return AgentErrorBody(code: .badRequest, message: "Send one JSON request on a single line.")
        }
        if let v = probe.v, v != AgentProtocol.version {
            return AgentErrorBody(code: .unsupportedVersion, message: "This Avi speaks protocol \(AgentProtocol.version).")
        }
        if let method = probe.method, AgentMethod(rawValue: method) == nil {
            return AgentErrorBody(code: .badRequest, message: "Unknown method `\(method)`.")
        }
        return AgentErrorBody(code: .badRequest, message: "The request does not match protocol \(AgentProtocol.version).")
    }
}
