import Foundation
import Observation

/// GitLab instances Avi knows about beyond hosts named "gitlab": those with a
/// token in Settings > GitLab, and those `glab` is set up for. The `glab`
/// list loads in the background the first time a remote's provider is
/// unknown, so github.com and gitlab.com users never wait for it.
@MainActor
@Observable
public final class KnownProviderHosts {
    public static let shared = KnownProviderHosts()

    /// Instances `glab` is signed in to, lowercased.
    private(set) var glabHosts: Set<String> = []
    private var hasLoaded = false
    private var loading: Task<Void, Never>?

    private init() {}

    public var hosts: ProviderHosts {
        ProviderHosts(gitlab: glabHosts.union(tokenHosts))
    }

    private var tokenHosts: Set<String> {
        Set(ConfigStore.shared.config.integrations.accounts.compactMap { account in
            guard account.kind == "gitlab" else { return nil }
            return URL(string: account.instanceURL)?.host?.lowercased()
        })
    }

    /// Reads the `glab` hosts once per launch.
    public func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    /// Reads the `glab` hosts again, for an instance signed in to after launch.
    public func refresh() async {
        if let loading {
            await loading.value
            return
        }
        let task = Task { @MainActor in
            let accounts = await GlabCLI.accounts() ?? []
            glabHosts = Set(accounts.map { $0.host.lowercased() })
            hasLoaded = true
        }
        loading = task
        await task.value
        loading = nil
    }
}
