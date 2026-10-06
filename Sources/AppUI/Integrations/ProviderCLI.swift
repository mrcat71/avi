import Foundation
import GitKit

/// Provider kind: GitHub or GitLab. Determines which CLI is invoked.
public enum CloneProvider: String, Sendable, Equatable, CaseIterable {
    case github
    case gitlab
}

/// Authentication state for the local `gh` / `glab` CLI.
public enum ProviderAuthState: Sendable, Equatable {
    case authenticated(username: String, host: String)
    case unauthenticated
    case cliMissing
    case error(message: String)
}

/// A remote repository listed by `gh repo list` or `glab repo list`.
public struct RemoteRepo: Sendable, Equatable, Identifiable {
    public var provider: CloneProvider
    public var nameWithOwner: String // "owner/repo" for github, "group/path" for gitlab
    public var name: String
    public var description: String
    public var sshURL: String
    public var httpsURL: String
    public var defaultBranch: String
    public var isPrivate: Bool
    public var updatedAt: Date?

    public var id: String {
        "\(provider.rawValue):\(nameWithOwner)"
    }

    public init(
        provider: CloneProvider,
        nameWithOwner: String,
        name: String,
        description: String,
        sshURL: String,
        httpsURL: String,
        defaultBranch: String,
        isPrivate: Bool,
        updatedAt: Date?
    ) {
        self.provider = provider
        self.nameWithOwner = nameWithOwner
        self.name = name
        self.description = description
        self.sshURL = sshURL
        self.httpsURL = httpsURL
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.updatedAt = updatedAt
    }
}

/// Wrapper around the GitHub CLI (`gh`). Falls back gracefully when the
/// binary is missing or unauthenticated. Token retrieval is on-demand;
/// nothing is stored in the app.
public enum GhCLI {
    @MainActor
    public static func executablePath() -> String? {
        ProviderCLISupport.resolve(preferred: ConfigStore.shared.config.externalTools.ghPath, name: "gh")
    }

    /// Every account `gh` knows, or nil when `gh` is not installed. `gh auth
    /// status` fails as a whole when any one account is broken, so its JSON
    /// is read per account instead.
    @MainActor
    public static func accounts() async -> [CloneAccount]? {
        guard let path = executablePath() else { return nil }
        guard let result = try? await ProviderCLISupport.run(executable: path, arguments: ["auth", "status", "--json", "hosts"]) else {
            return []
        }
        return CloneAccounts.ghAccounts(fromJSON: result.stdout)
    }

    /// The account Settings shows: the active one when it works, else any
    /// account that works.
    @MainActor
    public static func authStatus() async -> ProviderAuthState {
        guard let accounts = await accounts() else { return .cliMissing }
        guard let account = accounts.first(where: \.isUsable) else {
            return .unauthenticated
        }
        return .authenticated(username: account.login, host: account.host)
    }

    /// Repositories of `account`, read with its own token so it does not have
    /// to be the active one.
    @MainActor
    public static func listRepos(account: CloneAccount, limit: Int = 200) async throws -> [RemoteRepo] {
        guard let path = executablePath() else { throw ProviderCLIError.cliMissing(name: "gh") }
        let token = try await ProviderCLISupport.run(
            executable: path,
            arguments: ["auth", "token", "--hostname", account.host, "--user", account.login]
        )
        guard token.exitCode == 0 else {
            throw ProviderCLIError.commandFailed(message: token.stderrString)
        }
        let args = [
            "repo", "list",
            "--json", "name,nameWithOwner,description,sshUrl,url,defaultBranchRef,isPrivate,updatedAt",
            "--limit", String(limit)
        ]
        let result = try await ProviderCLISupport.run(
            executable: path,
            arguments: args,
            extraEnvironment: [
                "GH_HOST": account.host,
                "GH_TOKEN": token.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
        )
        guard result.exitCode == 0 else {
            throw ProviderCLIError.commandFailed(message: result.stderrString)
        }
        struct Raw: Decodable {
            struct Branch: Decodable { let name: String? }
            let name: String
            let nameWithOwner: String
            let description: String?
            let sshUrl: String?
            let url: String?
            let defaultBranchRef: Branch?
            let isPrivate: Bool?
            let updatedAt: String?
        }
        let decoded = try JSONDecoder().decode([Raw].self, from: result.stdout)
        let parser = ISO8601DateFormatter()
        return decoded.map { raw in
            RemoteRepo(
                provider: .github,
                nameWithOwner: raw.nameWithOwner,
                name: raw.name,
                description: raw.description ?? "",
                sshURL: raw.sshUrl ?? "",
                httpsURL: raw.url ?? "",
                defaultBranch: raw.defaultBranchRef?.name ?? "",
                isPrivate: raw.isPrivate ?? false,
                updatedAt: raw.updatedAt.flatMap { parser.date(from: $0) }
            )
        }
    }
}

/// Wrapper around the GitLab CLI (`glab`).
public enum GlabCLI {
    @MainActor
    public static func executablePath() -> String? {
        ProviderCLISupport.resolve(preferred: ConfigStore.shared.config.externalTools.glabPath, name: "glab")
    }

    /// One account per GitLab instance `glab` is set up for, or nil when
    /// `glab` is not installed. One unreachable instance makes `glab auth
    /// status` fail as a whole, so each host is read on its own.
    @MainActor
    public static func accounts() async -> [CloneAccount]? {
        guard let path = executablePath() else { return nil }
        guard let result = try? await ProviderCLISupport.run(executable: path, arguments: ["auth", "status", "--all"]) else {
            return []
        }
        return CloneAccounts.glabAccounts(fromStatus: result.stdoutString + "\n" + result.stderrString)
    }

    @MainActor
    public static func authStatus() async -> ProviderAuthState {
        guard let accounts = await accounts() else { return .cliMissing }
        guard let account = accounts.first(where: \.isUsable) else {
            return .unauthenticated
        }
        return .authenticated(username: account.login, host: account.host)
    }

    /// Projects on `account`'s instance.
    @MainActor
    public static func listRepos(account: CloneAccount, perPage: Int = 100) async throws -> [RemoteRepo] {
        guard let path = executablePath() else { throw ProviderCLIError.cliMissing(name: "glab") }
        let args = ["repo", "list", "--output", "json", "--per-page", String(perPage)]
        let result = try await ProviderCLISupport.run(
            executable: path,
            arguments: args,
            extraEnvironment: ["GITLAB_HOST": account.host]
        )
        guard result.exitCode == 0 else {
            throw ProviderCLIError.commandFailed(message: result.stderrString)
        }
        struct Raw: Decodable {
            let name: String
            let path_with_namespace: String?
            let pathWithNamespace: String?
            let description: String?
            let ssh_url_to_repo: String?
            let sshUrlToRepo: String?
            let http_url_to_repo: String?
            let httpUrlToRepo: String?
            let default_branch: String?
            let defaultBranch: String?
            let visibility: String?
            let last_activity_at: String?
            let lastActivityAt: String?
        }
        let decoded = (try? JSONDecoder().decode([Raw].self, from: result.stdout)) ?? []
        let parser = ISO8601DateFormatter()
        return decoded.map { raw in
            RemoteRepo(
                provider: .gitlab,
                nameWithOwner: raw.path_with_namespace ?? raw.pathWithNamespace ?? raw.name,
                name: raw.name,
                description: raw.description ?? "",
                sshURL: raw.ssh_url_to_repo ?? raw.sshUrlToRepo ?? "",
                httpsURL: raw.http_url_to_repo ?? raw.httpUrlToRepo ?? "",
                defaultBranch: raw.default_branch ?? raw.defaultBranch ?? "",
                isPrivate: (raw.visibility ?? "").lowercased() != "public",
                updatedAt: (raw.last_activity_at ?? raw.lastActivityAt).flatMap { parser.date(from: $0) }
            )
        }
    }
}

public enum ProviderCLIError: Error, LocalizedError, Sendable {
    case cliMissing(name: String)
    case commandFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .cliMissing(let name): return "\(name) CLI not found"
        case .commandFailed(let message): return message
        }
    }
}

/// Shared helpers for invoking provider CLIs (path resolution, environment,
/// argv-only execution via `ProcessRunner`).
public enum ProviderCLISupport {
    public static func resolve(preferred: String, name: String) -> String? {
        if !preferred.isEmpty,
           FileManager.default.isExecutableFile(atPath: preferred) {
            return preferred
        }
        // Common Homebrew + system locations.
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    public static func run(executable: String, arguments: [String], extraEnvironment: [String: String] = [:]) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            workingDirectory: nil,
            environment: environment().merging(extraEnvironment) { _, extra in extra }
        )
    }

    public static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        return env
    }
}
