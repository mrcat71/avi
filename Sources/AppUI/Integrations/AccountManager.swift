import Foundation
import Observation

/// Manages provider accounts: persistence in `IntegrationsConfig.accounts`,
/// secret storage in Keychain, and validation against provider `/user` endpoints.
@MainActor
@Observable
public final class AccountManager {
    public static let shared = AccountManager()

    private var store: ConfigStore {
        ConfigStore.shared
    }

    private init() {}

    public func addAccount(_ account: ProviderAccount) {
        store.update { config in
            // Replace existing by id, else append.
            if let idx = config.integrations.accounts.firstIndex(where: { $0.id == account.id }) {
                config.integrations.accounts[idx] = account
            } else {
                config.integrations.accounts.append(account)
            }
        }
    }

    public func removeAccount(id: String) {
        // Find the account first to discover its Keychain item, then delete both.
        if let account = store.config.integrations.accounts.first(where: { $0.id == id }) {
            KeychainStore.deleteString(account: account.keychainItem)
        }
        store.update { config in
            config.integrations.accounts.removeAll { $0.id == id }
        }
    }

    public func validate(accountID: String) async {
        guard var account = store.config.integrations.accounts.first(where: { $0.id == accountID }) else { return }
        guard let token = KeychainStore.getString(account: account.keychainItem) else {
            account.status = "invalid"
            updateAccount(account)
            return
        }
        do {
            let username = try await fetchUsername(for: account, token: token)
            account.username = username
            account.status = "ok"
            account.lastValidatedISO = ISO8601DateFormatter().string(from: Date())
        } catch {
            // A refused token is invalid; anything else may pass.
            account.status = (error as? AccountError)?.refusedToken == true ? "invalid" : "unreachable"
        }
        updateAccount(account)
    }

    public func addGitHubPATAccount(token: String) async throws {
        try await addPATAccount(kind: "github", instanceURL: "", token: token)
    }

    public func addGitLabPATAccount(token: String, instanceURL: String) async throws {
        let instance = instanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInstance = instance.isEmpty || instance == "https://gitlab.com" ? "" : instance
        try await addPATAccount(kind: "gitlab", instanceURL: effectiveInstance, token: token)
    }

    /// Checks the token with the provider before keeping it, so a mistyped
    /// or expired one leaves no account and no Keychain item behind.
    private func addPATAccount(kind: String, instanceURL: String, token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AccountError(message: "Paste a token first.") }
        let id = UUID().uuidString
        var account = ProviderAccount(
            id: id,
            kind: kind,
            instanceURL: instanceURL,
            username: "",
            keychainItem: "avi.account.\(id)",
            lastValidatedISO: "",
            status: "unknown"
        )
        account.username = try await fetchUsername(for: account, token: trimmed)
        try KeychainStore.setString(trimmed, account: account.keychainItem)
        account.status = "ok"
        account.lastValidatedISO = ISO8601DateFormatter().string(from: Date())
        addAccount(account)
    }

    public func token(for account: ProviderAccount) -> String? {
        KeychainStore.getString(account: account.keychainItem)
    }

    public func accounts(matching kind: String) -> [ProviderAccount] {
        store.config.integrations.accounts.filter { $0.kind == kind }
    }

    public func account(matching remoteHost: String) -> ProviderAccount? {
        for account in store.config.integrations.accounts {
            if account.kind == "github", remoteHost == "github.com" {
                return account
            }
            if account.kind == "gitlab" {
                let host = URL(string: account.instanceURL.isEmpty ? "https://gitlab.com" : account.instanceURL)?.host ?? ""
                if host == remoteHost {
                    return account
                }
            }
        }
        return nil
    }

    private func updateAccount(_ account: ProviderAccount) {
        store.update { config in
            if let idx = config.integrations.accounts.firstIndex(where: { $0.id == account.id }) {
                config.integrations.accounts[idx] = account
            }
        }
    }

    /// Calls `GET /user` on GitHub or `/api/v4/user` on GitLab.
    private func fetchUsername(for account: ProviderAccount, token: String) async throws -> String {
        let address: String
        switch account.kind {
        case "github":
            address = "https://api.github.com/user"
        case "gitlab":
            let base = account.instanceURL.isEmpty ? "https://gitlab.com" : account.instanceURL
            address = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v4/user"
        default:
            throw AccountError(message: "Avi does not know the provider \(account.kind).")
        }
        guard let url = URL(string: address), url.scheme == "https" || url.scheme == "http", url.host != nil else {
            throw AccountError(message: "\(account.instanceURL) is not a web address, such as https://gitlab.example.com.")
        }

        var request = URLRequest(url: url)
        switch account.kind {
        case "github":
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        case "gitlab":
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        default: break
        }

        let provider = account.kind == "github" ? "GitHub" : "GitLab"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccountError(message: "\(provider) sent no answer Avi understands.")
        }
        switch http.statusCode {
        case 200 ..< 300:
            break
        case 401:
            throw AccountError(message: "\(provider) did not accept the token. It may be mistyped, expired, or revoked.", refusedToken: true)
        case 403:
            throw AccountError(message: "\(provider) refused the token. It may lack the scope Avi needs.", refusedToken: true)
        default:
            throw AccountError(message: "\(provider) answered with HTTP \(http.statusCode).")
        }
        struct UserResponse: Decodable {
            let login: String?
            let username: String?
        }
        let decoded = try JSONDecoder().decode(UserResponse.self, from: data)
        return decoded.login ?? decoded.username ?? "(unknown)"
    }
}

/// Why an account could not be added or checked, in words for Settings.
struct AccountError: LocalizedError {
    let message: String
    /// The provider answered that the token is not good, rather than not
    /// answering at all.
    var refusedToken = false

    var errorDescription: String? {
        message
    }
}
