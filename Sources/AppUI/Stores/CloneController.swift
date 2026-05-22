import AppKit
import Foundation
import SwiftUI

/// Source the user can choose for a clone operation.
public enum CloneSource: CaseIterable, Sendable {
    case github
    case gitlab
    case url

    public var title: String {
        switch self {
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .url: return "From URL"
        }
    }

    public var icon: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "globe"
        case .url: return "link"
        }
    }

    public var tint: Color {
        switch self {
        case .github: return .primary
        case .gitlab: return .orange
        case .url: return .blue
        }
    }
}

/// State machine and view-model for `CloneSheet`. Owns the lifecycle of a clone
/// request from source selection through progress streaming to completion.
@MainActor
@Observable
public final class CloneController {
    public enum State: Equatable {
        case pickingSource
        case loadingRepos(CloneProvider)
        case browsingRepos(CloneProvider)
        case pickingDestination
        case cloning
        case finished(URL)
        case failed(String)
    }

    public var state: State = .pickingSource
    public var githubAuth: ProviderAuthState = .cliMissing
    public var gitlabAuth: ProviderAuthState = .cliMissing
    public var repos: [RemoteRepo] = []
    public var selectedRepoID: String?
    public var pastedURL: String = ""
    public var destinationPath: String = ""
    public var progress: CloneProgress?
    public var openAfterClone: Bool

    private var loadTask: Task<Void, Never>?
    private var cloneTask: Task<Void, Never>?

    public init() {
        let config = ConfigStore.shared.config.clone
        openAfterClone = config.openAfterClone
    }

    public var selectedRepo: RemoteRepo? {
        guard let id = selectedRepoID else { return nil }
        return repos.first { $0.id == id }
    }

    public var isCloning: Bool {
        if case .cloning = state { return true }
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
            return !destinationPath.trimmingCharacters(in: .whitespaces).isEmpty
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
        async let gh = GhCLI.authStatus()
        async let glab = GlabCLI.authStatus()
        githubAuth = await gh
        gitlabAuth = await glab
    }

    public func pick(source: CloneSource) {
        switch source {
        case .github:
            startLoading(provider: .github)
        case .gitlab:
            startLoading(provider: .gitlab)
        case .url:
            selectedRepoID = nil
            destinationPath = defaultDestination(for: nil)
            state = .pickingDestination
        }
    }

    public func goBack() {
        switch state {
        case .browsingRepos:
            state = .pickingSource
            repos = []
            selectedRepoID = nil
        case .pickingDestination:
            if let repo = selectedRepo {
                state = .browsingRepos(repo.provider)
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
            guard let repo = selectedRepo else { return }
            destinationPath = defaultDestination(for: repo)
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
        pastedURL = ""
        destinationPath = ""
        progress = nil
        state = .pickingSource
    }

    public func setDestinationDirectory(_ url: URL) {
        let name = selectedRepo?.name ?? URL(string: pastedURL)?.deletingPathExtension().lastPathComponent ?? "repository"
        destinationPath = url.appendingPathComponent(name).path
    }

    private func startLoading(provider: CloneProvider) {
        state = .loadingRepos(provider)
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let list: [RemoteRepo]
                switch provider {
                case .github: list = try await GhCLI.listRepos()
                case .gitlab: list = try await GlabCLI.listRepos()
                }
                if Task.isCancelled { return }
                repos = list
                state = .browsingRepos(provider)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func startClone() async {
        let destination = URL(fileURLWithPath: expand(path: destinationPath), isDirectory: true)
        let cloneConfig = ConfigStore.shared.config.clone
        let ghPath = GhCLI.executablePath()
        let glabPath = GlabCLI.executablePath()

        let spec: CloneRunner.Spec
        if let repo = selectedRepo {
            spec = CloneRunner.Spec(
                repo: repo,
                destination: destination,
                preferredProtocol: cloneConfig.preferredProtocol,
                preferredCLI: cloneConfig.preferredCLI,
                ghPath: ghPath,
                glabPath: glabPath
            )
        } else if let synthetic = syntheticRepo(from: pastedURL) {
            spec = CloneRunner.Spec(
                repo: synthetic,
                destination: destination,
                preferredProtocol: cloneConfig.preferredProtocol,
                preferredCLI: "git",
                ghPath: ghPath,
                glabPath: glabPath
            )
        } else {
            state = .failed("Invalid clone URL.")
            return
        }

        state = .cloning
        progress = nil
        cloneTask?.cancel()
        cloneTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await CloneRunner.clone(spec: spec) { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update
                    }
                }
                if Task.isCancelled { return }
                if outcome.success {
                    state = .finished(outcome.destination)
                    if openAfterClone {
                        // Caller (CloneSheet) is responsible for calling onClone(url).
                    }
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

    private func defaultDestination(for repo: RemoteRepo?) -> String {
        let base = expand(path: ConfigStore.shared.config.clone.defaultDirectory)
        let name = repo?.name ?? "repository"
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(name).path
    }

    private func expand(path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func syntheticRepo(from rawURL: String) -> RemoteRepo? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let name = URL(string: trimmed)?.deletingPathExtension().lastPathComponent ?? "repository"
        return RemoteRepo(
            provider: .github, // value unused; CLI=git skips provider branching
            nameWithOwner: name,
            name: name,
            description: "",
            sshURL: trimmed.hasPrefix("git@") ? trimmed : "",
            httpsURL: trimmed.hasPrefix("http") ? trimmed : "",
            defaultBranch: "",
            isPrivate: false,
            updatedAt: nil
        )
    }
}
