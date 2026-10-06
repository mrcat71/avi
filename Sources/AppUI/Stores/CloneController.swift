import AppKit
import Foundation
import SwiftUI

/// State machine and view-model for `CloneSheet`. Owns the lifecycle of a clone
/// request from source selection through progress streaming to completion.
@MainActor
@Observable
public final class CloneController {
    public enum State: Equatable {
        case pickingSource
        case loadingRepos(CloneAccount)
        case browsingRepos(CloneAccount)
        case pickingDestination
        case cloning
        case finished(URL)
        case failed(String)
    }

    public var state: State = .pickingSource
    public private(set) var accountList = CloneAccountList()
    public private(set) var isLoadingAccounts = true
    public var repos: [RemoteRepo] = []
    public var selectedRepoID: String?
    /// The URL typed or pasted in the From URL step.
    public var pastedURL: String = "" {
        didSet {
            if pastedURL != oldValue {
                urlChanged()
            }
        }
    }

    public var transport: CloneURL.Transport
    /// The account that authenticates an HTTPS clone; nil leaves it to Git.
    public var credentialAccountID: String?
    public var destinationPath: String = "" {
        didSet {
            if !settingDestination {
                destinationEdited = true
            }
        }
    }

    public var progress: CloneProgress?
    public var openAfterClone: Bool
    /// Shown with the finished clone, such as credentials that could not be kept.
    public private(set) var finishedWarning: String?

    private var browsingAccount: CloneAccount?
    private var destinationEdited = false
    private var settingDestination = false
    private var loadTask: Task<Void, Never>?
    private var cloneTask: Task<Void, Never>?

    public init() {
        let config = ConfigStore.shared.config.clone
        openAfterClone = config.openAfterClone
        transport = config.preferredProtocol == "ssh" ? .ssh : .https
    }

    public var selectedRepo: RemoteRepo? {
        guard let id = selectedRepoID else { return nil }
        return repos.first { $0.id == id }
    }

    /// The remote being cloned, when Avi can switch it between HTTPS and SSH.
    public var cloneURL: CloneURL? {
        if let repo = selectedRepo {
            return CloneURL.from(repo)
        }
        return CloneURL(pastedURL)
    }

    /// The accounts that can sign an HTTPS clone of `cloneURL`.
    public var credentialChoices: [CloneAccount] {
        guard transport == .https, let host = cloneURL?.host else { return [] }
        return CloneAccounts.usable(accountList.accounts, on: host)
    }

    public var credentialAccount: CloneAccount? {
        credentialChoices.first { $0.id == credentialAccountID }
    }

    /// Exactly what `git clone` gets: the remote in the chosen transport with
    /// the chosen account's name, or a URL Avi cannot rewrite, as typed.
    public var effectiveURL: String? {
        if let url = cloneURL {
            return url.string(for: transport, user: credentialAccount?.login)
        }
        let typed = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty || typed.contains(where: \.isWhitespace) ? nil : typed
    }

    public var isCloning: Bool {
        if case .cloning = state {
            return true
        }
        return false
    }

    public var canGoBack: Bool {
        switch state {
        case .browsingRepos, .pickingDestination, .failed:
            return true
        default:
            return false
        }
    }

    public var primaryTitle: String? {
        switch state {
        case .pickingSource: return nil
        case .loadingRepos: return nil
        case .browsingRepos: return "Next"
        case .pickingDestination: return "Clone"
        case .cloning: return "Cancel"
        case .finished: return nil
        case .failed: return nil
        }
    }

    public var primaryEnabled: Bool {
        switch state {
        case .browsingRepos:
            return selectedRepoID != nil
        case .pickingDestination:
            return effectiveURL != nil && !destinationPath.trimmingCharacters(in: .whitespaces).isEmpty
        case .cloning:
            return true
        default:
            return false
        }
    }

    public var statusLabel: String? {
        switch state {
        case .browsingRepos: return repos.isEmpty ? nil : "\(repos.count) repositories"
        case .pickingDestination:
            guard let repo = selectedRepo else { return nil }
            return "Cloning \(repo.nameWithOwner)"
        case .cloning:
            return "Press Cancel to abort"
        default:
            return nil
        }
    }

    public func refreshAuth() async {
        isLoadingAccounts = true
        accountList = await CloneAccountList.load()
        isLoadingAccounts = false
    }

    public func pick(account: CloneAccount) {
        guard account.canBrowse else { return }
        browsingAccount = account
        state = .loadingRepos(account)
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let list: [RemoteRepo]
                switch account.source {
                case .gh: list = try await GhCLI.listRepos(account: account)
                case .glab: list = try await GlabCLI.listRepos(account: account)
                case .token: list = []
                }
                if Task.isCancelled {
                    return
                }
                repos = list
                state = .browsingRepos(account)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Opens the From URL step, taking a remote URL from the clipboard when
    /// one is there.
    public func pickURL() {
        selectedRepoID = nil
        browsingAccount = nil
        destinationEdited = false
        if pastedURL.isEmpty, let clip = NSPasteboard.general.string(forType: .string), CloneURL(clip) != nil {
            pastedURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            urlChanged()
        }
        state = .pickingDestination
    }

    public func setTransport(_ value: CloneURL.Transport) {
        transport = value
        if value == .https, credentialAccount == nil {
            credentialAccountID = defaultCredentialID()
        }
    }

    public func goBack() {
        switch state {
        case .browsingRepos:
            state = .pickingSource
            repos = []
            selectedRepoID = nil
            browsingAccount = nil
        case .pickingDestination:
            if selectedRepo != nil, let account = browsingAccount {
                state = .browsingRepos(account)
            } else {
                state = .pickingSource
            }
        case .failed:
            state = .pickingSource
        default:
            break
        }
    }

    public func primaryAction() async {
        switch state {
        case .browsingRepos:
            guard selectedRepo != nil else { return }
            destinationEdited = false
            urlChanged()
            state = .pickingDestination
        case .pickingDestination:
            await startClone()
        case .cloning:
            cloneTask?.cancel()
            state = .failed("Clone cancelled.")
        default:
            break
        }
    }

    public func reset() {
        loadTask?.cancel()
        cloneTask?.cancel()
        repos = []
        selectedRepoID = nil
        browsingAccount = nil
        pastedURL = ""
        setDestination("")
        destinationEdited = false
        progress = nil
        finishedWarning = nil
        state = .pickingSource
    }

    public func setDestinationDirectory(_ url: URL) {
        destinationPath = url.appendingPathComponent(repositoryName).path
    }

    /// A next step for the error the last clone failed with, if there is one.
    public func hint(for message: String) -> String? {
        cloneFailureHint(for: message, host: cloneURL?.host)
    }

    private var repositoryName: String {
        selectedRepo?.name ?? cloneURL?.repositoryName ?? "repository"
    }

    /// A new remote picks its transport, its account, and, unless you typed
    /// one, its destination folder.
    private func urlChanged() {
        if selectedRepo == nil, let url = CloneURL(pastedURL) {
            transport = url.transport
        }
        credentialAccountID = defaultCredentialID()
        if !destinationEdited {
            setDestination(defaultDestination())
        }
    }

    /// The account you browsed with, else the first account on the host.
    private func defaultCredentialID() -> String? {
        let choices = credentialChoices
        if let browsing = browsingAccount, choices.contains(browsing) {
            return browsing.id
        }
        return choices.first?.id
    }

    private func setDestination(_ path: String) {
        settingDestination = true
        destinationPath = path
        settingDestination = false
    }

    private func startClone() async {
        guard let url = effectiveURL else {
            state = .failed("Enter the URL of the repository to clone.")
            return
        }
        let credential: CloneCredential
        switch credentialAccount?.source {
        case .gh?:
            guard let path = GhCLI.executablePath() else {
                state = .failed("GitHub CLI not found. Install it with `brew install gh`, or pick another account.")
                return
            }
            credential = .cliHelper(executable: path)
        case .glab?:
            guard let path = GlabCLI.executablePath() else {
                state = .failed("GitLab CLI not found. Install it with `brew install glab`, or pick another account.")
                return
            }
            credential = .cliHelper(executable: path)
        case .token(let item)?:
            guard let token = KeychainStore.getString(account: item), let account = credentialAccount else {
                state = .failed("The token for this account is missing from the Keychain. Add it again in Settings.")
                return
            }
            credential = .token(username: account.login.isEmpty ? "oauth2" : account.login, secret: token)
        case nil:
            credential = .gitDefault
        }
        let spec = CloneRunner.Spec(
            url: url,
            destination: URL(fileURLWithPath: expand(path: destinationPath), isDirectory: true),
            credential: credential,
            host: cloneURL?.host
        )

        state = .cloning
        progress = nil
        finishedWarning = nil
        cloneTask?.cancel()
        cloneTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await CloneRunner.clone(spec: spec) { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update
                    }
                }
                if Task.isCancelled {
                    return
                }
                if outcome.success {
                    finishedWarning = outcome.warning
                    state = .finished(outcome.destination)
                } else {
                    state = .failed(outcome.stderrTail.isEmpty ? "Clone failed (exit \(outcome.exitCode))." : outcome.stderrTail)
                }
            } catch {
                if !(error is CancellationError) {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func defaultDestination() -> String {
        let base = expand(path: ConfigStore.shared.config.clone.defaultDirectory)
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(repositoryName).path
    }

    private func expand(path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
