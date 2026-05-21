import Foundation

public struct GitLabMergeRequest: Decodable {
    public let iid: Int
    public let web_url: String
    public let title: String
}

enum GitLabAPIError: Error, CustomStringConvertible, LocalizedError {
    case http(Int, String)
    case decoding(String)

    var description: String { errorDescription ?? "" }
    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "GitLab API error \(code): \(body.prefix(300))"
        case .decoding(let msg):
            return "GitLab decoding error: \(msg)"
        }
    }
}

struct GitLabAPI: Sendable {
    let baseURL: String     // e.g. https://gitlab.com
    let token: String

    /// `projectPath` is the URL-encoded "group/name" path.
    func createMergeRequest(
        projectPath: String,
        title: String,
        description: String,
        sourceBranch: String,
        targetBranch: String
    ) async throws -> GitLabMergeRequest {
        let encodedPath = projectPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? projectPath
        let url = URL(string: "\(baseURL)/api/v4/projects/\(encodedPath)/merge_requests")!

        struct Body: Encodable {
            let title: String
            let description: String
            let source_branch: String
            let target_branch: String
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            title: title,
            description: description,
            source_branch: sourceBranch,
            target_branch: targetBranch
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitLabAPIError.decoding("No response")
        }
        if !(200..<300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GitLabAPIError.http(http.statusCode, text)
        }
        return try JSONDecoder().decode(GitLabMergeRequest.self, from: data)
    }

    static func projectWebURL(host: String, projectPath: String) -> URL? {
        URL(string: "https://\(host)/\(projectPath)")
    }

    static func commitWebURL(host: String, projectPath: String, sha: String) -> URL? {
        URL(string: "https://\(host)/\(projectPath)/-/commit/\(sha)")
    }

    static func branchWebURL(host: String, projectPath: String, branch: String) -> URL? {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        return URL(string: "https://\(host)/\(projectPath)/-/tree/\(encoded)")
    }
}
