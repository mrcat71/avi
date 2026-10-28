import AppKit
import Foundation
import GitKit

/// A pull request on GitHub or a merge request on GitLab.
struct PullRequestInfo: Equatable, Sendable {
    let number: Int
    let url: URL
    let title: String
    var isDraft = false
}

/// The forge a remote is on, as far as pull requests go.
enum Forge: Equatable, Sendable {
    case github(owner: String, repo: String)
    case gitlab(host: String, projectPath: String)

    init?(_ hint: ProviderHint) {
        switch hint {
        case .github(let owner, let repo): self = .github(owner: owner, repo: repo)
        case .gitlab(let host, let projectPath): self = .gitlab(host: host, projectPath: projectPath)
        case .unknown: return nil
        }
    }

    var name: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        }
    }

    var host: String {
        switch self {
        case .github: return "github.com"
        case .gitlab(let host, _): return host
        }
    }

    /// "Pull Request" or "Merge Request", for titles and menu items.
    var requestNoun: String {
        switch self {
        case .github: return "Pull Request"
        case .gitlab: return "Merge Request"
        }
    }

    /// "#42" on GitHub, "!42" on GitLab.
    func reference(_ number: Int) -> String {
        switch self {
        case .github: return "#\(number)"
        case .gitlab: return "!\(number)"
        }
    }

    /// The project's own name, which keeps its hyphens in titles.
    var projectName: String {
        switch self {
        case .github(_, let repo): return repo
        case .gitlab(_, let projectPath): return projectPath.split(separator: "/").last.map(String.init) ?? projectPath
        }
    }

    var webURL: URL? {
        switch self {
        case .github(let owner, let repo): return GitHubAPI.repoWebURL(owner: owner, repo: repo)
        case .gitlab(let host, let projectPath): return GitLabAPI.projectWebURL(host: host, projectPath: projectPath)
        }
    }

    /// What the CLIs take for `--repo`.
    var cliRepository: String {
        switch self {
        case .github(let owner, let repo): return "\(owner)/\(repo)"
        case .gitlab(let host, let projectPath): return "https://\(host)/\(projectPath)"
        }
    }
}

/// What a new pull request says and joins.
struct PullRequestRequest: Equatable, Sendable {
    var title: String
    var body: String
    /// The branch on the remote that is merged.
    var head: String
    /// The branch it is merged into.
    var base: String
    var isDraft: Bool
}

/// How Avi reaches the forge for pull requests, the first that works:
/// its CLI signed in to the host, a token from Settings, or the browser.
enum PullRequestRoute: Equatable, Sendable {
    case cli(executable: String)
    case token(String)
    case browser

    /// Avi creates the request itself rather than handing over to a web page.
    var createsInApp: Bool {
        self != .browser
    }

    var label: String {
        switch self {
        case .cli(let executable): return URL(fileURLWithPath: executable).lastPathComponent
        case .token: return "your token from Settings"
        case .browser: return "the browser"
        }
    }
}

enum PullRequestError: LocalizedError, Equatable {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

/// Creates and finds pull and merge requests. Every command runs as an
/// argument list, never through a shell, with values attached as
/// `--flag=value` so a title starting with a dash stays a value.
enum PullRequestService {
    // MARK: Route

    #if DEBUG
    /// The route screenshots use, so they never ask gh, glab or GitHub.
    @MainActor static var harnessRoute: PullRequestRoute?
    #endif

    @MainActor
    static func route(for forge: Forge) async -> PullRequestRoute {
        #if DEBUG
        if let harnessRoute {
            return harnessRoute
        }
        #endif
        switch forge {
        case .github:
            if let path = GhCLI.executablePath(),
               let accounts = await GhCLI.accounts(host: forge.host),
               accounts.contains(where: { $0.isUsable && $0.host.caseInsensitiveCompare(forge.host) == .orderedSame }) {
                return .cli(executable: path)
            }
        case .gitlab:
            if let path = GlabCLI.executablePath(),
               let accounts = await GlabCLI.accounts(host: forge.host),
               accounts.contains(where: { $0.isUsable && $0.host.caseInsensitiveCompare(forge.host) == .orderedSame }) {
                return .cli(executable: path)
            }
        }
        if let account = AccountManager.shared.account(matching: forge.host),
           let token = AccountManager.shared.token(for: account), !token.isEmpty {
            return .token(token)
        }
        return .browser
    }

    // MARK: Create

    /// Creates `request` on `forge`. The browser route has nothing to create
    /// and throws; open `browserURL(for:on:)` instead.
    static func create(_ request: PullRequestRequest, on forge: Forge, via route: PullRequestRoute, in root: URL) async throws -> PullRequestInfo {
        switch route {
        case .cli(let executable):
            let result = try await ProviderCLISupport.run(
                executable: executable,
                arguments: createArguments(request, on: forge),
                extraEnvironment: cliEnvironment(for: forge),
                workingDirectory: root
            )
            let output = result.stdoutString + "\n" + result.stderrString
            guard result.exitCode == 0 else {
                throw PullRequestError.failed(cliFailure(output, forge: forge))
            }
            guard let url = createdURL(in: output, forge: forge), let number = number(in: url) else {
                throw PullRequestError.failed("\(forge.name) did not say where the new \(forge.requestNoun.lowercased()) is:\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return PullRequestInfo(number: number, url: url, title: request.title, isDraft: request.isDraft)
        case .token(let token):
            switch forge {
            case .github(let owner, let repo):
                let created = try await GitHubAPI(token: token).createPullRequest(
                    owner: owner, repo: repo, title: request.title, body: request.body,
                    head: request.head, base: request.base, draft: request.isDraft
                )
                guard let url = URL(string: created.html_url) else { throw PullRequestError.failed("GitHub returned no address.") }
                return PullRequestInfo(number: created.number, url: url, title: created.title, isDraft: request.isDraft)
            case .gitlab(let host, let projectPath):
                let created = try await GitLabAPI(baseURL: "https://\(host)", token: token).createMergeRequest(
                    projectPath: projectPath,
                    title: draftTitle(request, on: forge),
                    description: request.body,
                    sourceBranch: request.head,
                    targetBranch: request.base
                )
                guard let url = URL(string: created.web_url) else { throw PullRequestError.failed("GitLab returned no address.") }
                return PullRequestInfo(number: created.iid, url: url, title: created.title, isDraft: request.isDraft)
            }
        case .browser:
            throw PullRequestError.failed("Creating a \(forge.requestNoun.lowercased()) needs gh, glab or a token.")
        }
    }

    /// The open request whose source is `head`, if there is one. Failures
    /// read as none: the lookup only saves you a duplicate.
    static func existing(head: String, on forge: Forge, via route: PullRequestRoute, in root: URL) async -> PullRequestInfo? {
        #if DEBUG
        if await ScreenshotHarness.isActive {
            return nil
        }
        #endif
        switch route {
        case .cli(let executable):
            guard let result = try? await ProviderCLISupport.run(
                executable: executable,
                arguments: listArguments(head: head, on: forge),
                extraEnvironment: cliEnvironment(for: forge),
                workingDirectory: root
            ), result.exitCode == 0 else { return nil }
            return firstOpen(in: result.stdout, forge: forge)
        case .token(let token):
            switch forge {
            case .github(let owner, let repo):
                return try? await GitHubAPI(token: token).openPullRequest(owner: owner, repo: repo, head: head)
            case .gitlab(let host, let projectPath):
                return try? await GitLabAPI(baseURL: "https://\(host)", token: token).openMergeRequest(projectPath: projectPath, sourceBranch: head)
            }
        case .browser:
            return nil
        }
    }

    // MARK: Browser

    /// The forge's own form, filled in, for when Avi cannot create the request itself.
    static func browserURL(for request: PullRequestRequest, on forge: Forge) -> URL? {
        switch forge {
        case .github(let owner, let repo):
            return GitHubAPI.compareWebURL(owner: owner, repo: repo, base: request.base, head: request.head, title: request.title, body: request.body)
        case .gitlab(let host, let projectPath):
            return GitLabAPI.newMergeRequestWebURL(
                host: host, projectPath: projectPath, sourceBranch: request.head, targetBranch: request.base,
                title: draftTitle(request, on: forge), description: request.body
            )
        }
    }

    // MARK: Commands

    static func createArguments(_ request: PullRequestRequest, on forge: Forge) -> [String] {
        switch forge {
        case .github:
            var arguments = [
                "pr", "create",
                "--repo=\(forge.cliRepository)",
                "--head=\(request.head)",
                "--base=\(request.base)",
                "--title=\(request.title)",
                "--body=\(request.body)"
            ]
            if request.isDraft {
                arguments.append("--draft")
            }
            return arguments
        case .gitlab:
            var arguments = [
                "mr", "create",
                "--repo=\(forge.cliRepository)",
                "--source-branch=\(request.head)",
                "--target-branch=\(request.base)",
                "--title=\(request.title)",
                "--description=\(request.body)",
                "--yes"
            ]
            if request.isDraft {
                arguments.append("--draft")
            }
            return arguments
        }
    }

    static func listArguments(head: String, on forge: Forge) -> [String] {
        switch forge {
        case .github:
            return [
                "pr", "list",
                "--repo=\(forge.cliRepository)",
                "--head=\(head)",
                "--state=open",
                "--json=number,url,title,isDraft",
                "--limit=1"
            ]
        case .gitlab:
            return [
                "mr", "list",
                "--repo=\(forge.cliRepository)",
                "--source-branch=\(head)",
                "--output=json"
            ]
        }
    }

    /// The CLIs must never stop to ask: there is nobody at their terminal.
    static func cliEnvironment(for forge: Forge) -> [String: String] {
        switch forge {
        case .github: return ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"]
        case .gitlab(let host, _): return ["NO_PROMPT": "1", "NO_COLOR": "1", "GITLAB_HOST": host]
        }
    }

    // MARK: Parsing

    /// The new request's address in what `gh` or `glab` printed.
    static func createdURL(in output: String, forge: Forge) -> URL? {
        let pattern = switch forge {
        case .github: #"https://\S+/pull/\d+"#
        case .gitlab: #"https://\S+/-/merge_requests/\d+"#
        }
        guard let range = output.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(output[range]))
    }

    /// The number at the end of a request's address.
    static func number(in url: URL) -> Int? {
        Int(url.lastPathComponent)
    }

    /// The first open request in `gh pr list --json` or `glab mr list --output json`.
    static func firstOpen(in data: Data, forge: Forge) -> PullRequestInfo? {
        switch forge {
        case .github:
            struct Item: Decodable {
                let number: Int
                let url: String
                let title: String
                let isDraft: Bool?
            }
            guard let item = (try? JSONDecoder().decode([Item].self, from: data))?.first,
                  let url = URL(string: item.url) else { return nil }
            return PullRequestInfo(number: item.number, url: url, title: item.title, isDraft: item.isDraft ?? false)
        case .gitlab:
            struct Item: Decodable {
                let iid: Int
                let web_url: String
                let title: String
                let draft: Bool?
                let state: String?
            }
            guard let items = try? JSONDecoder().decode([Item].self, from: data),
                  let item = items.first(where: { ($0.state ?? "opened") == "opened" }),
                  let url = URL(string: item.web_url) else { return nil }
            return PullRequestInfo(number: item.iid, url: url, title: item.title, isDraft: item.draft ?? false)
        }
    }

    /// GitLab marks drafts by title.
    static func draftTitle(_ request: PullRequestRequest, on forge: Forge) -> String {
        guard request.isDraft, case .gitlab = forge, !request.title.lowercased().hasPrefix("draft:") else { return request.title }
        return "Draft: \(request.title)"
    }

    /// What went wrong, in the CLI's words, without its colour codes.
    private static func cliFailure(_ output: String, forge: Forge) -> String {
        let trimmed = output
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(forge.name) refused the \(forge.requestNoun.lowercased())." : trimmed
    }
}
