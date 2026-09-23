import Foundation

/// Messages on Avi's control socket: one JSON request per connection, one
/// JSON response back, each on a single line. Version 1.
public enum AgentProtocol {
    public static let version = 1
    /// Largest request the app reads, so a stuck or hostile client cannot grow memory.
    public static let maxRequestBytes = 1 << 20

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// Default socket location, overridable with `AVI_SOCKET` for tests and dev builds.
    public static func socketPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["AVI_SOCKET"], !override.isEmpty {
            return override
        }
        let home = environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Avi/control.sock").path
    }
}

public enum AgentMethod: String, Codable, Sendable {
    case status
    case open
    case propose
}

public struct AgentRequest: Codable, Equatable, Sendable {
    public var v: Int
    public var method: AgentMethod
    public var params: AgentParams

    public init(method: AgentMethod, params: AgentParams = AgentParams()) {
        v = AgentProtocol.version
        self.method = method
        self.params = params
    }
}

public struct AgentParams: Codable, Equatable, Sendable {
    /// Absolute path of the repository (or linked worktree) root.
    public var repo: String?
    public var agent: String?
    public var session: String?
    public var title: String?
    public var commits: [AgentCommit]?
    public var replace: Bool?
    public var focus: Bool?

    public init(
        repo: String? = nil,
        agent: String? = nil,
        session: String? = nil,
        title: String? = nil,
        commits: [AgentCommit]? = nil,
        replace: Bool? = nil,
        focus: Bool? = nil
    ) {
        self.repo = repo
        self.agent = agent
        self.session = session
        self.title = title
        self.commits = commits
        self.replace = replace
        self.focus = focus
    }
}

public struct AgentCommit: Codable, Equatable, Sendable {
    public var message: String
    /// Paths relative to the repository root. Empty or missing: fill the
    /// message only, for whatever is already staged.
    public var files: [String]?

    public init(message: String, files: [String]? = nil) {
        self.message = message
        self.files = files
    }
}

public struct AgentResponse: Codable, Equatable, Sendable {
    public var v: Int
    public var ok: Bool
    public var result: AgentResult?
    public var error: AgentErrorBody?

    public static func success(_ result: AgentResult) -> AgentResponse {
        AgentResponse(v: AgentProtocol.version, ok: true, result: result, error: nil)
    }

    public static func failure(_ error: AgentErrorBody) -> AgentResponse {
        AgentResponse(v: AgentProtocol.version, ok: false, result: nil, error: error)
    }
}

public struct AgentResult: Codable, Equatable, Sendable {
    public var app: AgentAppInfo
    public var placement: ProposalPlacement?
    public var commits: Int?
    public var staged: [String]?
    public var notes: [String]?
    public var repo: AgentRepoStatus?
    public var repositories: [AgentRepoStatus]?

    public init(
        app: AgentAppInfo,
        placement: ProposalPlacement? = nil,
        commits: Int? = nil,
        staged: [String]? = nil,
        notes: [String]? = nil,
        repo: AgentRepoStatus? = nil,
        repositories: [AgentRepoStatus]? = nil
    ) {
        self.app = app
        self.placement = placement
        self.commits = commits
        self.staged = staged
        self.notes = notes
        self.repo = repo
        self.repositories = repositories
    }
}

public struct AgentAppInfo: Codable, Equatable, Sendable {
    public var version: String
}

/// One repository as Avi sees it right now.
public struct AgentRepoStatus: Codable, Equatable, Sendable {
    public var path: String
    public var open: Bool
    public var branch: String?
    public var staged: Int?
    public var unstaged: Int?
    public var untracked: Int?
    /// True when the commit field holds text, yours or an agent's.
    public var commitFieldInUse: Bool?
    public var commitField: AgentPendingDraft?
    public var drafts: [AgentPendingDraft]?
}

/// A pending commit and who proposed it.
public struct AgentPendingDraft: Codable, Equatable, Sendable {
    /// `agent`, `ai`, or `manual`.
    public var source: String
    public var agent: String?
    public var session: String?
    public var subject: String
    public var files: [String]
    public var edited: Bool
}

public enum AgentErrorCode: String, Codable, Sendable {
    case badRequest = "bad_request"
    case unsupportedVersion = "unsupported_version"
    case disabled
    case notRunning = "not_running"
    case blocked
    case noWindow = "no_window"
    case notTrusted = "not_trusted"
    case notARepository = "not_a_repository"
    case noCommits = "no_commits"
    case emptyMessage = "empty_message"
    case filesRequired = "files_required"
    case unknownPath = "unknown_path"
    case duplicatePath = "duplicate_path"
    case conflicts
    case fileClaimed = "file_claimed"
    case editedByUser = "edited_by_user"
    case busy
    case failed
}

public struct AgentErrorBody: Error, Codable, Equatable, Sendable {
    public var code: AgentErrorCode
    public var message: String
    /// The paths the error is about.
    public var paths: [String]?
    /// Every path that currently has changes, so a caller can fix its plan.
    public var changed: [String]?
    /// Path to the name of the agent or source holding it.
    public var owners: [String: String]?

    public init(code: AgentErrorCode, message: String, paths: [String]? = nil, changed: [String]? = nil, owners: [String: String]? = nil) {
        self.code = code
        self.message = message
        self.paths = paths
        self.changed = changed
        self.owners = owners
    }
}

extension AgentErrorBody {
    init(_ rejection: ProposalRejection) {
        let message = rejection.localizedDescription
        switch rejection {
        case .noCommits:
            self.init(code: .noCommits, message: message)
        case .emptyMessage:
            self.init(code: .emptyMessage, message: message)
        case .filesRequired:
            self.init(code: .filesRequired, message: message)
        case .unknownPaths(let paths, let changed):
            self.init(code: .unknownPath, message: message, paths: paths, changed: changed)
        case .duplicatePaths(let paths):
            self.init(code: .duplicatePath, message: message, paths: paths)
        case .conflicts(let paths):
            self.init(code: .conflicts, message: message, paths: paths)
        case .fileClaimed(let owners):
            self.init(code: .fileClaimed, message: message, paths: owners.keys.sorted(), owners: owners)
        case .editedByUser:
            self.init(code: .editedByUser, message: message)
        case .busy:
            self.init(code: .busy, message: message)
        }
    }
}
