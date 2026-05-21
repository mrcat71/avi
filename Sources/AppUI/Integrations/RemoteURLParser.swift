import Foundation
import GitKit

public enum ProviderHint: Equatable {
    case github(owner: String, repo: String)
    case gitlab(host: String, projectPath: String)   // projectPath is "owner/repo" or "group/sub/repo"
    case unknown
}

enum RemoteURLParser {
    /// Resolve a `ProviderHint` from a remote's fetch or push URL.
    /// Accepts both SSH (`git@github.com:foo/bar.git`) and HTTPS forms.
    static func hint(from remote: GitRemote) -> ProviderHint {
        let url = remote.fetchURL ?? remote.pushURL ?? ""
        return hint(from: url)
    }

    static func hint(from url: String) -> ProviderHint {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // SSH form: git@host:owner/repo(.git)
        if trimmed.hasPrefix("git@") || trimmed.contains("@") && trimmed.contains(":") && !trimmed.contains("://") {
            let withoutGit = trimmed.dropFirst(trimmed.hasPrefix("git@") ? 4 : 0)
            // Split on the first colon to separate host and path.
            if let colonIdx = withoutGit.firstIndex(of: ":") {
                let host = String(withoutGit[..<colonIdx])
                var path = String(withoutGit[withoutGit.index(after: colonIdx)...])
                if path.hasSuffix(".git") { path.removeLast(4) }
                return classify(host: host, path: path)
            }
        }

        // URL form.
        guard let parsed = URL(string: trimmed), let host = parsed.host else { return .unknown }
        var path = parsed.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        return classify(host: host, path: path)
    }

    private static func classify(host: String, path: String) -> ProviderHint {
        let lower = host.lowercased()
        if lower == "github.com" || lower.hasSuffix(".github.com") {
            let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return .unknown }
            return .github(owner: parts[0], repo: parts[1])
        }
        // Heuristic: any host containing "gitlab" is treated as GitLab.
        if lower.contains("gitlab") {
            return .gitlab(host: host, projectPath: path)
        }
        return .unknown
    }
}
