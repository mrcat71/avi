import Foundation
import GitKit

public enum ProviderHint: Equatable, Sendable {
    case github(owner: String, repo: String)
    case gitlab(host: String, projectPath: String) // projectPath is "owner/repo" or "group/sub/repo"
    case unknown
}

/// Hosts known to run GitLab although their name does not say so, such as a
/// company instance at git.example.com. Compared case-insensitively.
public struct ProviderHosts: Sendable, Equatable {
    public private(set) var gitlab: Set<String>

    public init(gitlab: Set<String> = []) {
        self.gitlab = Set(gitlab.map { $0.lowercased() })
    }
}

enum RemoteURLParser {
    /// Resolve a `ProviderHint` from a remote's fetch or push URL.
    /// Accepts both SSH (`git@github.com:foo/bar.git`) and HTTPS forms.
    static func hint(from remote: GitRemote, knownHosts: ProviderHosts = ProviderHosts()) -> ProviderHint {
        let url = remote.fetchURL ?? remote.pushURL ?? ""
        return hint(from: url, knownHosts: knownHosts)
    }

    static func hint(from url: String, knownHosts: ProviderHosts = ProviderHosts()) -> ProviderHint {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // SSH form: git@host:owner/repo(.git)
        if trimmed.hasPrefix("git@") || trimmed.contains("@") && trimmed.contains(":") && !trimmed.contains("://") {
            let withoutGit = trimmed.dropFirst(trimmed.hasPrefix("git@") ? 4 : 0)
            // Split on the first colon to separate host and path.
            if let colonIdx = withoutGit.firstIndex(of: ":") {
                let host = String(withoutGit[..<colonIdx])
                var path = String(withoutGit[withoutGit.index(after: colonIdx)...])
                if path.hasSuffix(".git") {
                    path.removeLast(4)
                }
                return classify(host: host, path: path, knownHosts: knownHosts)
            }
        }

        // URL form.
        guard let parsed = URL(string: trimmed), let host = parsed.host else { return .unknown }
        var path = parsed.path
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        if path.hasSuffix(".git") {
            path.removeLast(4)
        }
        return classify(host: host, path: path, knownHosts: knownHosts)
    }

    private static func classify(host: String, path: String, knownHosts: ProviderHosts) -> ProviderHint {
        let lower = host.lowercased()
        if lower == "github.com" || lower.hasSuffix(".github.com") {
            let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return .unknown }
            return .github(owner: parts[0], repo: parts[1])
        }
        // Any host containing "gitlab" is treated as GitLab, and so is any
        // self-hosted instance Avi knows from `glab` or a saved token.
        if lower.contains("gitlab") || knownHosts.gitlab.contains(lower) {
            guard !path.isEmpty else { return .unknown }
            return .gitlab(host: host, projectPath: path)
        }
        return .unknown
    }
}
