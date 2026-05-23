import Foundation
import GitKit

/// Provider kind: GitHub or GitLab. Determines which CLI is invoked.
public enum CloneProvider: String, Sendable, Equatable {
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

    @MainActor
    public static func authStatus() async -> ProviderAuthState {
        guard let path = executablePath() else { return .cliMissing }
        let result = try? await ProviderCLISupport.run(executable: path, arguments: ["auth", "status"])
        guard let result else { return .error(message: "gh auth status failed to start") }
        let combined = result.stdoutString + "\n" + result.stderrString
        if result.exitCode != 0 {
            return .unauthenticated
        }
        // Parse "Logged in to github.com as <username>" from stdout/stderr.
        let username = ProviderCLISupport.parseLogin(from: combined, hostHint: "github.com")
        return .authenticated(username: username ?? "(unknown)", host: "github.com")
    }

    @MainActor
    public static func listRepos(login: String? = nil, limit: Int = 200) async throws -> [RemoteRepo] {
        guard let path = executablePath() else { return [] }
        var args = ["repo", "list"]
        if let login, !login.isEmpty { args.append(login) }
        args.append(contentsOf: [
            "--json", "name,nameWithOwner,description,sshUrl,url,defaultBranchRef,isPrivate,updatedAt",
            "--limit", String(limit)
        ])
        let result = try await ProviderCLISupport.run(executable: path, arguments: args)
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

    @MainActor
    public static func authStatus() async -> ProviderAuthState {
        guard let path = executablePath() else { return .cliMissing }
        let result = try? await ProviderCLISupport.run(executable: path, arguments: ["auth", "status"])
        guard let result else { return .error(message: "glab auth status failed to start") }
        let combined = result.stdoutString + "\n" + result.stderrString
        if combined.lowercased().contains("not logged in") || result.exitCode != 0 {
            return .unauthenticated
        }
        let username = ProviderCLISupport.parseLogin(from: combined, hostHint: "gitlab.com")
        return .authenticated(username: username ?? "(unknown)", host: "gitlab.com")
    }

    @MainActor
    public static func listRepos(perPage: Int = 100) async throws -> [RemoteRepo] {
        guard let path = executablePath() else { return [] }
        let args = ["repo", "list", "--output", "json", "--per-page", String(perPage)]
        let result = try await ProviderCLISupport.run(executable: path, arguments: args)
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

    public static func run(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: URL(fileURLWithPath: executable),
            arguments: arguments,
            workingDirectory: nil,
            environment: environment()
        )
    }

    /// Tries to parse a "Logged in to <host> as <user>" line out of mixed CLI output.
    public static func parseLogin(from text: String, hostHint _: String) -> String? {
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let lower = line.lowercased()
            guard lower.contains("logged in to") else { continue }
            guard let asRange = lower.range(of: " as ") else { continue }
            let after = String(line[asRange.upperBound...])
            let token = after.split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ")" }).first
            if let token { return String(token) }
        }
        return nil
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
