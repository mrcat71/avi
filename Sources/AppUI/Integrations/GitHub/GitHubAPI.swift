import Foundation

public struct GitHubPullRequest: Decodable {
    public let number: Int
    public let html_url: String
    public let title: String
}

enum GitHubAPIError: Error, CustomStringConvertible, LocalizedError {
    case http(Int, String)
    case decoding(String)

    var description: String {
        errorDescription ?? ""
    }

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "GitHub API error \(code): \(body.prefix(300))"
        case .decoding(let msg):
            return "GitHub decoding error: \(msg)"
        }
    }
}

struct GitHubAPI {
    let token: String

    func createPullRequest(
        owner: String,
        repo: String,
        title: String,
        body: String,
        head: String,
        base: String,
        draft: Bool = false
    ) async throws -> GitHubPullRequest {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls")!
        struct Body: Encodable {
            let title: String
            let body: String
            let head: String
            let base: String
            let draft: Bool
        }
        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(title: title, body: body, head: head, base: base, draft: draft))
        let data = try await send(request)
        return try JSONDecoder().decode(GitHubPullRequest.self, from: data)
    }

    /// The open pull request from `head` in the same repository, if any.
    func openPullRequest(owner: String, repo: String, head: String) async throws -> PullRequestInfo? {
        var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls")
        components?.queryItems = [
            URLQueryItem(name: "head", value: "\(owner):\(head)"),
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = components?.url else { return nil }
        let data = try await send(authorizedRequest(url))
        struct Item: Decodable {
            let number: Int
            let html_url: String
            let title: String
            let draft: Bool?
        }
        guard let item = try JSONDecoder().decode([Item].self, from: data).first,
              let web = URL(string: item.html_url) else { return nil }
        return PullRequestInfo(number: item.number, url: web, title: item.title, isDraft: item.draft ?? false)
    }

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.decoding("No response")
        }
        if !(200 ..< 300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GitHubAPIError.http(http.statusCode, text)
        }
        return data
    }

    static func repoWebURL(owner: String, repo: String) -> URL? {
        URL(string: "https://github.com/\(owner)/\(repo)")
    }

    static func commitWebURL(owner: String, repo: String, sha: String) -> URL? {
        URL(string: "https://github.com/\(owner)/\(repo)/commit/\(sha)")
    }

    static func branchWebURL(owner: String, repo: String, branch: String) -> URL? {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        return URL(string: "https://github.com/\(owner)/\(repo)/tree/\(encoded)")
    }

    /// "New pull request" compare page, filled in.
    static func compareWebURL(owner: String, repo: String, base: String, head: String, title: String, body: String = "") -> URL? {
        let baseEncoded = base.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? base
        let headEncoded = head.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? head
        var components = URLComponents(string: "https://github.com/\(owner)/\(repo)/compare/\(baseEncoded)...\(headEncoded)")
        var items = [
            URLQueryItem(name: "expand", value: "1"),
            URLQueryItem(name: "title", value: title)
        ]
        if !body.isEmpty {
            items.append(URLQueryItem(name: "body", value: body))
        }
        components?.queryItems = items
        return components?.url
    }
}
