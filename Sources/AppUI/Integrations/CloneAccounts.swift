import Foundation

/// An account the Clone sheet can browse repositories with or clone through:
/// one signed in to `gh` or `glab`, or a token saved in Settings. `gh` keeps
/// several accounts per host and `glab` one per host, so the sheet lists each
/// of them instead of asking the CLI whether "you" are signed in.
public struct CloneAccount: Identifiable, Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Git authenticates through `gh auth git-credential`, which picks the
        /// account named in the clone URL.
        case gh
        /// Git authenticates through `glab auth git-credential` for the host.
        case glab
        /// A personal access token saved in Settings, kept in the Keychain.
        case token(keychainItem: String)
    }

    public var provider: CloneProvider
    public var host: String
    public var login: String
    public var source: Source
    /// The transport the CLI is set to use for Git, when it says.
    public var gitProtocol: String?
    /// Why the account cannot be used, with the command that fixes it.
    public var problem: String?

    public init(
        provider: CloneProvider,
        host: String,
        login: String,
        source: Source,
        gitProtocol: String? = nil,
        problem: String? = nil
    ) {
        self.provider = provider
        self.host = host
        self.login = login
        self.source = source
        self.gitProtocol = gitProtocol
        self.problem = problem
    }

    public var id: String {
        switch source {
        case .gh: return "gh:\(host):\(login)"
        case .glab: return "glab:\(host):\(login)"
        case .token(let item): return "token:\(item)"
        }
    }

    public var isUsable: Bool {
        problem == nil
    }

    /// Only the CLIs can list repositories; a token account clones by URL.
    public var canBrowse: Bool {
        guard isUsable else { return false }
        switch source {
        case .gh, .glab: return true
        case .token: return false
        }
    }

    /// "mrcat71", or "a.svinarenko on git.example.com" off the default host.
    public var title: String {
        let name = login.isEmpty ? host : login
        return host == provider.defaultHost || login.isEmpty ? name : "\(name) on \(host)"
    }

    public var sourceLabel: String {
        switch source {
        case .gh: return "gh"
        case .glab: return "glab"
        case .token: return "token"
        }
    }
}

public extension CloneProvider {
    var defaultHost: String {
        switch self {
        case .github: return "github.com"
        case .gitlab: return "gitlab.com"
        }
    }

    var title: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        }
    }
}

public enum CloneAccounts {
    /// Every account `gh auth status --json hosts` reports, broken ones with
    /// the reason, so one bad token no longer hides the accounts that work.
    static func ghAccounts(fromJSON data: Data) -> [CloneAccount] {
        struct Status: Decodable {
            struct Account: Decodable {
                let host: String?
                let login: String?
                let state: String?
                let error: String?
                let gitProtocol: String?
            }

            let hosts: [String: [Account]]
        }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { return [] }
        return status.hosts.keys.sorted().flatMap { host in
            (status.hosts[host] ?? []).map { raw in
                let accountHost = raw.host ?? host
                let login = raw.login ?? ""
                var problem: String?
                if raw.state != "success" {
                    let reason = raw.error.map { "\($0). " } ?? ""
                    problem = "gh: \(reason)Run `gh auth login -h \(accountHost)`."
                }
                return CloneAccount(
                    provider: .github,
                    host: accountHost,
                    login: login,
                    source: .gh,
                    gitProtocol: raw.gitProtocol,
                    problem: problem
                )
            }
        }
    }

    /// One account per host in `glab auth status --all`, whose output is text:
    /// a line naming each host, then indented lines about it.
    static func glabAccounts(fromStatus text: String) -> [CloneAccount] {
        var accounts: [CloneAccount] = []
        var host: String?
        var login: String?
        var gitProtocol: String?

        func flush() {
            guard let host else { return }
            accounts.append(CloneAccount(
                provider: .gitlab,
                host: host,
                login: login ?? "",
                source: .glab,
                gitProtocol: gitProtocol,
                problem: login == nil ? "glab is not signed in. Run `glab auth login --hostname \(host)`." : nil
            ))
        }

        for rawLine in stripANSI(text).split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix(" "), !line.hasPrefix("\t"), isHostName(trimmed) {
                flush()
                host = trimmed
                login = nil
                gitProtocol = nil
                continue
            }
            guard host != nil else { continue }
            if let range = trimmed.range(of: "Logged in to "), let asRange = trimmed.range(of: " as ", range: range.upperBound ..< trimmed.endIndex) {
                login = trimmed[asRange.upperBound...].split(separator: " ").first.map(String.init)
            } else if trimmed.contains("Git operations for"), let range = trimmed.range(of: "configured to use ") {
                gitProtocol = trimmed[range.upperBound...].split(separator: " ").first.map(String.init)
            }
        }
        flush()
        return accounts
    }

    /// Token accounts saved in Settings > GitHub and Settings > GitLab.
    static func tokenAccounts(_ accounts: [ProviderAccount]) -> [CloneAccount] {
        accounts.compactMap { account in
            let provider: CloneProvider
            switch account.kind {
            case "github": provider = .github
            case "gitlab": provider = .gitlab
            default: return nil
            }
            let host = URL(string: account.instanceURL)?.host ?? provider.defaultHost
            let problem = account.status == "invalid" ? "The saved token was rejected. Replace it in Settings." : nil
            return CloneAccount(
                provider: provider,
                host: host,
                login: account.username,
                source: .token(keychainItem: account.keychainItem),
                problem: problem
            )
        }
    }

    /// The accounts on `host` that can authenticate a clone over HTTPS.
    static func usable(_ accounts: [CloneAccount], on host: String) -> [CloneAccount] {
        accounts.filter { $0.isUsable && $0.host.caseInsensitiveCompare(host) == .orderedSame }
    }

    private static func isHostName(_ text: String) -> Bool {
        !text.isEmpty && text.contains(".") && text.allSatisfy { $0.isLetter || $0.isNumber || ".-:".contains($0) }
    }

    private static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}

/// What the Clone sheet found: the accounts, and which CLIs are missing.
public struct CloneAccountList: Sendable, Equatable {
    public var accounts: [CloneAccount] = []
    public var ghMissing = false
    public var glabMissing = false

    public init(accounts: [CloneAccount] = [], ghMissing: Bool = false, glabMissing: Bool = false) {
        self.accounts = accounts
        self.ghMissing = ghMissing
        self.glabMissing = glabMissing
    }

    @MainActor
    public static func load() async -> CloneAccountList {
        async let gh = GhCLI.accounts()
        async let glab = GlabCLI.accounts()
        let tokens = CloneAccounts.tokenAccounts(ConfigStore.shared.config.integrations.accounts)
        let (ghAccounts, glabAccounts) = await (gh, glab)
        return CloneAccountList(
            accounts: (ghAccounts ?? []) + (glabAccounts ?? []) + tokens,
            ghMissing: ghAccounts == nil,
            glabMissing: glabAccounts == nil
        )
    }
}
