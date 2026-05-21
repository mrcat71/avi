import Foundation
import Observation

/// Manages provider accounts: persistence in `IntegrationsConfig.accounts`,
/// secret storage in Keychain, and validation against provider `/user` endpoints.
@MainActor
@Observable
public final class AccountManager {
    public static let shared = AccountManager()

    private var store: ConfigStore { ConfigStore.shared }

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
            account.status = "unreachable"
        }
        updateAccount(account)
    }

    public func addGitHubPATAccount(token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let id = UUID().uuidString
        let keychainItem = "avi.account.\(id)"
        try KeychainStore.setString(trimmed, account: keychainItem)

        var account = ProviderAccount(
            id: id,
            kind: "github",
            instanceURL: "",
            username: "(validating)",
            keychainItem: keychainItem,
            lastValidatedISO: "",
            status: "unknown"
        )

        do {
            let username = try await fetchUsername(for: account, token: trimmed)
            account.username = username
            account.status = "ok"
            account.lastValidatedISO = ISO8601DateFormatter().string(from: Date())
        } catch {
            account.status = "invalid"
        }

        addAccount(account)
    }

    public func addGitLabPATAccount(token: String, instanceURL: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInstance = instanceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let id = UUID().uuidString
        let keychainItem = "avi.account.\(id)"
        try KeychainStore.setString(trimmed, account: keychainItem)

        let effectiveInstance = normalizedInstance.isEmpty || normalizedInstance == "https://gitlab.com" ? "" : normalizedInstance

        var account = ProviderAccount(
            id: id,
            kind: "gitlab",
            instanceURL: effectiveInstance,
            username: "(validating)",
            keychainItem: keychainItem,
            lastValidatedISO: "",
            status: "unknown"
        )

        do {
            let username = try await fetchUsername(for: account, token: trimmed)
            account.username = username
            account.status = "ok"
            account.lastValidatedISO = ISO8601DateFormatter().string(from: Date())
        } catch {
            account.status = "invalid"
        }

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
            if account.kind == "github" && remoteHost == "github.com" {
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
        let url: URL
        switch account.kind {
        case "github":
            url = URL(string: "https://api.github.com/user")!
        case "gitlab":
            let base = account.instanceURL.isEmpty ? "https://gitlab.com" : account.instanceURL
            url = URL(string: "\(base)/api/v4/user")!
        default:
            throw NSError(domain: "AccountManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown provider kind"])
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "AccountManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Provider returned non-2xx"])
        }
        struct UserResponse: Decodable {
            let login: String?
            let username: String?
        }
        let decoded = try JSONDecoder().decode(UserResponse.self, from: data)
        return decoded.login ?? decoded.username ?? "(unknown)"
    }
}
