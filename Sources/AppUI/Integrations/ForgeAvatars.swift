import Foundation
import GitKit
import os

/// The forge that hosts a repository's main remote, as author pictures see it.
struct AvatarOrigin: Hashable, Sendable {
    enum Forge: Hashable, Sendable {
        case gitHub
        case gitLab
    }

    let forge: Forge
    /// "github.com", or the GitLab instance, such as "gitlab.com".
    let host: String
    /// "owner/repo" on GitHub, "group/subgroup/project" on GitLab.
    let project: String

    init(forge: Forge, host: String, project: String) {
        self.forge = forge
        self.host = host.lowercased()
        self.project = project
    }

    init?(_ hint: ProviderHint) {
        switch hint {
        case .github(let owner, let repo):
            self.init(forge: .gitHub, host: "github.com", project: "\(owner)/\(repo)")
        case .gitlab(let host, let projectPath):
            self.init(forge: .gitLab, host: host, project: projectPath)
        case .unknown:
            return nil
        }
    }

    /// The instance whose public avatar lookup `AvatarSource` asks as well.
    var gitLabHost: String? {
        forge == .gitLab ? host : nil
    }

    /// Where relative picture paths in the forge's answers point.
    var webURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url
    }
}

/// The GraphQL that asks a forge who wrote some commits, and the reading of
/// its answers. Only full hexadecimal object names go into the query text;
/// the project travels as a variable.
enum ForgeAvatarQuery {
    /// Commits per request, well inside GitLab's default query complexity.
    static let maxCommits = 40

    /// What the forge said about one commit.
    enum Answer: Equatable, Sendable {
        case account(URL)
        /// The forge has the commit, but no account has its author's address.
        case noAccount
        /// The forge does not have the commit, as when it was never pushed.
        case unknownCommit
    }

    /// A full SHA-1 or SHA-256 object name, and nothing else.
    static func isObjectName(_ text: String) -> Bool {
        (text.utf8.count == 40 || text.utf8.count == 64) && text.utf8.allSatisfy { byte in
            (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a") ... UInt8(ascii: "f")).contains(byte)
                || (UInt8(ascii: "A") ... UInt8(ascii: "F")).contains(byte)
        }
    }

    /// One field per commit, named `c0`, `c1`, … in the order given.
    /// `commits` must already be object names.
    static func text(for forge: AvatarOrigin.Forge, commits: [String], pixels: Int) -> String {
        let fields = commits.enumerated().map { index, commit in
            switch forge {
            case .gitHub:
                "c\(index): object(oid: \"\(commit)\") { ... on Commit { author { user { avatarUrl(size: \(pixels)) } } } }"
            case .gitLab:
                "c\(index): commit(ref: \"\(commit)\") { author { avatarUrl } }"
            }
        }.joined(separator: " ")
        switch forge {
        case .gitHub:
            return "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { \(fields) } }"
        case .gitLab:
            return "query($path: ID!) { project(fullPath: $path) { repository { \(fields) } } }"
        }
    }

    static func variables(for origin: AvatarOrigin) -> [String: String] {
        switch origin.forge {
        case .gitHub:
            let parts = origin.project.split(separator: "/", maxSplits: 1).map(String.init)
            return ["owner": parts.first ?? "", "name": parts.count > 1 ? parts[1] : ""]
        case .gitLab:
            return ["path": origin.project]
        }
    }

    /// The answer about each of `count` commits, by position. Nil when the
    /// response says nothing about the project, as when the account cannot
    /// see it. GitLab answers with a "no_avatar" placeholder for an account
    /// without a picture, which says no more than initials.
    static func answers(from data: Data, forge: AvatarOrigin.Forge, count: Int, base: URL?) -> [Answer]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else { return nil }
        let container = switch forge {
        case .gitHub:
            payload["repository"] as? [String: Any]
        case .gitLab:
            (payload["project"] as? [String: Any])?["repository"] as? [String: Any]
        }
        guard let container else { return nil }
        return (0 ..< count).map { index in
            guard let commit = container["c\(index)"] as? [String: Any] else { return .unknownCommit }
            let author = commit["author"] as? [String: Any]
            let account = forge == .gitHub ? author?["user"] as? [String: Any] : author
            guard let path = account?["avatarUrl"] as? String,
                  let url = URL(string: path, relativeTo: base)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http",
                  !url.path.contains("no_avatar")
            else { return .noAccount }
            return .account(url)
        }
    }

    /// GitHub's REST view of one commit, which a public repository serves
    /// without a token. The list endpoint leaves the diff out.
    static func gitHubRESTURL(project: String, commit: String) -> URL? {
        let parts = project.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts.allSatisfy(isGitHubName), isObjectName(commit) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(parts[0])/\(parts[1])/commits"
        components.queryItems = [URLQueryItem(name: "sha", value: commit), URLQueryItem(name: "per_page", value: "1")]
        return components.url
    }

    /// What GitHub's REST API said about one commit. Nil when the answer is
    /// about the repository instead, as for a private one.
    static func gitHubRESTAnswer(status: Int, data: Data, commit: String) -> Answer? {
        let json = try? JSONSerialization.jsonObject(with: data)
        switch status {
        case 200:
            guard let first = (json as? [[String: Any]])?.first,
                  (first["sha"] as? String)?.lowercased() == commit.lowercased()
            else { return .unknownCommit }
            guard let path = (first["author"] as? [String: Any])?["avatar_url"] as? String,
                  let url = URL(string: path), url.scheme == "https"
            else { return .noAccount }
            return .account(url)
        case 404, 422:
            let message = (json as? [String: Any])?["message"] as? String ?? ""
            return message.hasPrefix("No commit found") ? .unknownCommit : nil
        default:
            return nil
        }
    }

    /// For each author address in `commits`, newest first, the commits to ask
    /// about: the oldest loaded one, the likeliest to be pushed, then the newest.
    static func candidates(in commits: some Sequence<CommitSummary>) -> [String: [String]] {
        var newest: [String: String] = [:]
        var oldest: [String: String] = [:]
        for commit in commits {
            let key = AvatarSource.normalized(commit.authorEmail)
            if newest[key] == nil {
                newest[key] = commit.oid
            }
            oldest[key] = commit.oid
        }
        return oldest.reduce(into: [:]) { result, entry in
            let latest = newest[entry.key] ?? entry.value
            result[entry.key] = latest == entry.value ? [entry.value] : [entry.value, latest]
        }
    }

    private static func isGitHubName(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
}

enum ForgeAvatarError: Error, LocalizedError {
    case http(Int)
    case cli(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .http(let status): "HTTP \(status)"
        case .cli(let message): message.trimmingCharacters(in: .whitespacesAndNewlines)
        case .noToken: "the token is missing from the Keychain"
        }
    }
}

/// Asks the forge that hosts a repository which account wrote a commit, and
/// returns that account's picture, so private commit addresses get one too.
/// Authors wanted within a moment of each other go out together, one GraphQL
/// query per project, signed in with the token from Settings or through `gh`
/// or `glab`. With neither, a public GitHub repository is asked through the
/// REST API, which allows 60 requests an hour without a token.
@MainActor
final class ForgeAvatars {
    static let shared = ForgeAvatars()

    /// Sends one GraphQL query to a forge and returns the body of its answer.
    struct Transport: Sendable {
        let name: String
        let send: @Sendable (_ query: String, _ variables: [String: String]) async throws -> Data
    }

    /// A GET without credentials, returning the body and the HTTP status.
    typealias AnonymousGET = @Sendable (URL) async throws -> (Data, Int)

    private struct Wanted {
        let commits: [String]
        var waiting: [CheckedContinuation<URL?, Never>]
    }

    private let transports: @MainActor (AvatarOrigin) async -> [Transport]
    private let anonymousGET: AnonymousGET
    private let gathering: Duration
    private var wanted: [AvatarOrigin: [String: Wanted]] = [:]
    private var answering: [AvatarOrigin: Transport] = [:]
    private var unreachable: Set<AvatarOrigin> = []
    private var anonymousAllowanceSpent = false

    private static let log = Logger(subsystem: "com.svinarenko.avi", category: "avatars")
    private nonisolated static let session = URLSession(configuration: .ephemeral)

    init(
        transports: @escaping @MainActor (AvatarOrigin) async -> [Transport] = ForgeAvatars.signedInTransports(for:),
        anonymousGET: @escaping AnonymousGET = ForgeAvatars.fetchAnonymously,
        gathering: Duration = .milliseconds(150)
    ) {
        self.transports = transports
        self.anonymousGET = anonymousGET
        self.gathering = gathering
    }

    /// The picture of the account that wrote `commits`, all by the author at
    /// `email`, or nil when the forge cannot say.
    func avatarURL(email: String, commits: [String], origin: AvatarOrigin, pixels: Int) async -> URL? {
        let commits = commits.filter(ForgeAvatarQuery.isObjectName)
        guard !commits.isEmpty, !unreachable.contains(origin) else { return nil }
        return await withCheckedContinuation { continuation in
            if wanted[origin] == nil {
                wanted[origin] = [:]
                Task { await self.send(origin, pixels: pixels) }
            }
            wanted[origin]?[email, default: Wanted(commits: commits, waiting: [])].waiting.append(continuation)
        }
    }

    /// Gathers the authors wanted for `origin`, then asks in batches.
    private func send(_ origin: AvatarOrigin, pixels: Int) async {
        try? await Task.safeSleep(for: gathering)
        let authors = (wanted.removeValue(forKey: origin) ?? [:]).sorted { $0.key < $1.key }
        var batch: [Wanted] = []
        for (_, author) in authors {
            if !batch.isEmpty, batch.reduce(0, { $0 + $1.commits.count }) + author.commits.count > ForgeAvatarQuery.maxCommits {
                await answer(batch, origin: origin, pixels: pixels)
                batch = []
            }
            batch.append(author)
        }
        if !batch.isEmpty {
            await answer(batch, origin: origin, pixels: pixels)
        }
    }

    private func answer(_ batch: [Wanted], origin: AvatarOrigin, pixels: Int) async {
        let commits = batch.flatMap(\.commits)
        var answers = await ask(origin, commits: commits, pixels: pixels)
        if answers == nil {
            answers = await askAnonymously(origin, batch: batch)
        }
        if let found = answers, found.count != commits.count {
            answers = nil
        }
        if answers == nil, !unreachable.contains(origin) {
            unreachable.insert(origin)
            Self.log.info("No way in to \(origin.host, privacy: .public) for author pictures; using the address lookups")
        }
        var offset = 0
        for author in batch {
            let mine = answers.map { Array($0[offset ..< offset + author.commits.count]) } ?? []
            offset += author.commits.count
            let url = mine.lazy.compactMap { answer -> URL? in
                if case .account(let url) = answer {
                    return url
                }
                return nil
            }.first
            for continuation in author.waiting {
                continuation.resume(returning: url)
            }
        }
    }

    /// Each signed-in way to the forge in turn, keeping the first that answers.
    private func ask(_ origin: AvatarOrigin, commits: [String], pixels: Int) async -> [ForgeAvatarQuery.Answer]? {
        guard !unreachable.contains(origin) else { return nil }
        let query = ForgeAvatarQuery.text(for: origin.forge, commits: commits, pixels: pixels)
        let variables = ForgeAvatarQuery.variables(for: origin)
        var ways = answering[origin].map { [$0] } ?? []
        if ways.isEmpty {
            ways = await transports(origin)
        }
        for way in ways {
            do {
                let data = try await way.send(query, variables)
                if let answers = ForgeAvatarQuery.answers(from: data, forge: origin.forge, count: commits.count, base: origin.webURL) {
                    answering[origin] = way
                    return answers
                }
                Self.log.info("\(way.name, privacy: .public) cannot see \(origin.project, privacy: .public) on \(origin.host, privacy: .public)")
            } catch {
                Self.log.info("\(way.name, privacy: .public) failed for \(origin.host, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        answering[origin] = nil
        return nil
    }

    /// GitHub's REST API, one commit at a time, until each author has an
    /// answer. Once GitHub says the hourly allowance is spent, the rest wait
    /// for the next launch.
    private func askAnonymously(_ origin: AvatarOrigin, batch: [Wanted]) async -> [ForgeAvatarQuery.Answer]? {
        guard origin.forge == .gitHub, !anonymousAllowanceSpent else { return nil }
        var answers = Array(repeating: ForgeAvatarQuery.Answer.unknownCommit, count: batch.reduce(0) { $0 + $1.commits.count })
        var offset = 0
        for author in batch {
            defer { offset += author.commits.count }
            for (index, commit) in author.commits.enumerated() where !anonymousAllowanceSpent {
                guard let url = ForgeAvatarQuery.gitHubRESTURL(project: origin.project, commit: commit),
                      let response = try? await anonymousGET(url)
                else { return nil }
                let (data, status) = response
                if status == 403 || status == 429 {
                    anonymousAllowanceSpent = true
                    Self.log.info("GitHub's allowance for requests without a token is spent; author pictures wait for the next launch")
                    break
                }
                guard let answer = ForgeAvatarQuery.gitHubRESTAnswer(status: status, data: data, commit: commit) else { return nil }
                answers[offset + index] = answer
                if answer != .unknownCommit {
                    break
                }
            }
        }
        return answers
    }

    // MARK: - Ways in

    /// The ways in that never prompt: the Settings token for the forge's
    /// host, then `gh` or `glab`, which keep their own tokens. `glab` is used
    /// only for an instance it is signed in to, so a token it holds for one
    /// host never goes to another.
    static func signedInTransports(for origin: AvatarOrigin) async -> [Transport] {
        var ways: [Transport] = []
        if let account = AccountManager.shared.account(matching: origin.host), account.status != "invalid",
           let endpoint = graphQLEndpoint(for: origin, instanceURL: account.instanceURL) {
            ways.append(token(endpoint: endpoint, forge: origin.forge, keychainItem: account.keychainItem))
        }
        switch origin.forge {
        case .gitHub:
            if let gh = GhCLI.executablePath() {
                ways.append(cli(gh, host: "github.com"))
            }
        case .gitLab:
            await KnownProviderHosts.shared.loadIfNeeded()
            if KnownProviderHosts.shared.glabHosts.contains(origin.host), let glab = GlabCLI.executablePath() {
                ways.append(cli(glab, host: origin.host))
            }
        }
        return ways
    }

    nonisolated static func graphQLEndpoint(for origin: AvatarOrigin, instanceURL: String) -> URL? {
        switch origin.forge {
        case .gitHub:
            URL(string: "https://api.github.com/graphql")
        case .gitLab:
            URL(string: instanceURL.isEmpty ? "https://gitlab.com" : instanceURL)?.appendingPathComponent("api/graphql")
        }
    }

    /// The token is read from the Keychain for each request rather than kept,
    /// and a redirect to another host is refused rather than followed with it.
    nonisolated static func token(endpoint: URL, forge: AvatarOrigin.Forge, keychainItem: String) -> Transport {
        Transport(name: "Settings token") { query, variables in
            guard let token = KeychainStore.getString(account: keychainItem) else { throw ForgeAvatarError.noToken }
            var request = URLRequest(url: endpoint, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            switch forge {
            case .gitHub:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .gitLab:
                request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
            let (data, response) = try await session.data(for: request, delegate: SameHostRedirects())
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw ForgeAvatarError.http(status) }
            return data
        }
    }

    /// `gh api graphql` or `glab api graphql`. Variables go in with `-f`,
    /// which passes them as plain strings: `-F` would read a value starting
    /// with "@" as a file.
    nonisolated static func cli(_ executable: String, host: String) -> Transport {
        Transport(name: (executable as NSString).lastPathComponent) { query, variables in
            var arguments = ["api", "graphql", "--hostname", host, "-f", "query=\(query)"]
            for name in variables.keys.sorted() {
                arguments += ["-f", "\(name)=\(variables[name] ?? "")"]
            }
            let result = try await ProviderCLISupport.run(executable: executable, arguments: arguments)
            guard result.exitCode == 0 else { throw ForgeAvatarError.cli(result.stderrString) }
            return result.stdout
        }
    }

    nonisolated static func fetchAnonymously(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Follows a redirect only within the host the request went to, so a token in
/// its headers never reaches another one.
final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        request.url?.host?.lowercased() == task.originalRequest?.url?.host?.lowercased() ? request : nil
    }
}
