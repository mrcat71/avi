import Foundation

public struct GitHubPullRequest: Decodable {
    public let number: Int
    public let html_url: String
    public let title: String
}

enum GitHubAPIError: Error, CustomStringConvertible, LocalizedError {
    case http(Int, String)
    case decoding(String)

    var description: String { errorDescription ?? "" }
    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "GitHub API error \(code): \(body.prefix(300))"
        case .decoding(let msg):
            return "GitHub decoding error: \(msg)"
        }
    }
}

struct GitHubAPI: Sendable {
    let token: String

    func createPullRequest(owner: String, repo: String, title: String, body: String, head: String, base: String) async throws -> GitHubPullRequest {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/pulls")!
        struct Body: Encodable {
            let title: String
            let body: String
            let head: String
            let base: String
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(title: title, body: body, head: head, base: base))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.decoding("No response")
        }
        if !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GitHubAPIError.http(http.statusCode, text)
        }
        return try JSONDecoder().decode(GitHubPullRequest.self, from: data)
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
}
