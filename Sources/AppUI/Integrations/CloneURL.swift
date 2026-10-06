import Foundation

/// A Git remote the Clone sheet can fetch over HTTPS or SSH and rewrite from
/// one to the other: `https://host/owner/repo.git`, `ssh://git@host/owner/repo`,
/// or the scp-like `git@host:owner/repo.git`. Other forms, such as `git://`
/// URLs and local paths, are not parsed; the sheet clones them as typed.
public struct CloneURL: Sendable, Equatable {
    public enum Transport: String, Sendable, CaseIterable {
        case https
        case ssh
    }

    public var transport: Transport
    public var host: String
    /// "owner/repo.git" or "group/subgroup/repo", without a leading slash.
    public var path: String
    /// `http` when that is what was pasted; HTTPS otherwise.
    var scheme = "https"
    var port: Int?
    /// A user typed into an HTTPS URL, kept when no account is chosen.
    var httpsUser: String?
    var sshUser = "git"
    /// Whether the SSH form was a `ssh://` URL rather than scp-like.
    var sshURLForm = false

    public init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if text.contains("://") {
            // A password in the URL would end up in the clone's config; such a
            // URL is cloned exactly as typed instead of being rewritten.
            guard let components = URLComponents(string: text), components.password == nil,
                  let scheme = components.scheme?.lowercased(),
                  let host = components.host, !host.isEmpty else { return nil }
            let path = components.path.hasPrefix("/") ? String(components.path.dropFirst()) : components.path
            guard !path.isEmpty else { return nil }
            switch scheme {
            case "https", "http":
                transport = .https
                self.scheme = scheme
                httpsUser = components.user
            case "ssh", "git+ssh", "ssh+git":
                transport = .ssh
                sshURLForm = true
                if let user = components.user, !user.isEmpty {
                    sshUser = user
                }
            default:
                return nil
            }
            self.host = host
            self.path = path
            port = components.port
            return
        }
        // scp-like: [user@]host:path, where the host part has no slash. An
        // absolute path on the server has no HTTPS twin, so it is cloned as typed.
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let authority = text[..<colon]
        let path = String(text[text.index(after: colon)...])
        guard !authority.isEmpty, !authority.contains("/"), !path.isEmpty, !path.hasPrefix("/") else { return nil }
        if let at = authority.lastIndex(of: "@") {
            sshUser = String(authority[..<at])
            host = String(authority[authority.index(after: at)...])
        } else {
            host = String(authority)
        }
        guard !host.isEmpty, !sshUser.isEmpty else { return nil }
        transport = .ssh
        self.path = path
    }

    /// The folder `git clone` would create: the last path part without `.git`.
    public var repositoryName: String {
        let last = path.split(separator: "/").last.map(String.init) ?? host
        return last.hasSuffix(".git") ? String(last.dropLast(4)) : last
    }

    /// The URL for `transport`. Over HTTPS, `user` goes in front of the host
    /// so Git asks the credential helper for that account.
    public func string(for transport: Transport, user: String? = nil) -> String {
        switch transport {
        case .https:
            var components = URLComponents()
            components.scheme = self.transport == .https ? scheme : "https"
            components.host = host
            components.port = self.transport == .https ? port : nil
            components.path = "/" + path
            if let user = user ?? (self.transport == .https ? httpsUser : nil), !user.isEmpty {
                components.user = user
            }
            return components.string ?? "https://\(host)/\(path)"
        case .ssh:
            let sshPath = self.transport == .ssh || path.hasSuffix(".git") ? path : path + ".git"
            if sshURLForm, self.transport == .ssh {
                let portPart = port.map { ":\($0)" } ?? ""
                return "ssh://\(sshUser)@\(host)\(portPart)/\(sshPath)"
            }
            return "\(sshUser)@\(host):\(sshPath)"
        }
    }

    /// A listed repository's address, preferring HTTPS and falling back to SSH.
    static func from(_ repo: RemoteRepo) -> CloneURL? {
        CloneURL(repo.httpsURL) ?? CloneURL(repo.sshURL)
    }
}
