import Foundation

public struct GitLabMergeRequest: Decodable {
    public let iid: Int
    public let web_url: String
    public let title: String
}

enum GitLabAPIError: Error, CustomStringConvertible, LocalizedError {
    case http(Int, String)
    case decoding(String)

    var description: String {
        errorDescription ?? ""
    }

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "GitLab API error \(code): \(body.prefix(300))"
        case .decoding(let msg):
            return "GitLab decoding error: \(msg)"
        }
    }
}

struct GitLabAPI {
    let baseURL: String // e.g. https://gitlab.com
    let token: String

    /// `projectPath` is the "group/name" path; it is encoded here.
    func createMergeRequest(
        projectPath: String,
        title: String,
        description: String,
        sourceBranch: String,
        targetBranch: String
    ) async throws -> GitLabMergeRequest {
        let url = URL(string: "\(baseURL)/api/v4/projects/\(Self.encodedProject(projectPath))/merge_requests")!
        struct Body: Encodable {
            let title: String
            let description: String
            let source_branch: String
            let target_branch: String
        }
        var request = authorizedRequest(url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(
            title: title,
            description: description,
            source_branch: sourceBranch,
            target_branch: targetBranch
        ))
        let data = try await send(request)
        return try JSONDecoder().decode(GitLabMergeRequest.self, from: data)
    }

    /// The open merge request from `sourceBranch`, if any.
    func openMergeRequest(projectPath: String, sourceBranch: String) async throws -> PullRequestInfo? {
        var components = URLComponents(string: "\(baseURL)/api/v4/projects/\(Self.encodedProject(projectPath))/merge_requests")
        components?.queryItems = [
            URLQueryItem(name: "source_branch", value: sourceBranch),
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "per_page", value: "1")
        ]
        guard let url = components?.url else { return nil }
        let data = try await send(authorizedRequest(url))
        struct Item: Decodable {
            let iid: Int
            let web_url: String
            let title: String
            let draft: Bool?
        }
        guard let item = try JSONDecoder().decode([Item].self, from: data).first,
              let web = URL(string: item.web_url) else { return nil }
        return PullRequestInfo(number: item.iid, url: web, title: item.title, isDraft: item.draft ?? false)
    }

    private static func encodedProject(_ projectPath: String) -> String {
        projectPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? projectPath
    }

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitLabAPIError.decoding("No response")
        }
        if !(200 ..< 300).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GitLabAPIError.http(http.statusCode, text)
        }
        return data
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

    /// "New merge request" page, filled in.
    static func newMergeRequestWebURL(
        host: String,
        projectPath: String,
        sourceBranch: String,
        targetBranch: String,
        title: String,
        description: String = ""
    ) -> URL? {
        var components = URLComponents(string: "https://\(host)/\(projectPath)/-/merge_requests/new")
        var items = [
            URLQueryItem(name: "merge_request[source_branch]", value: sourceBranch),
            URLQueryItem(name: "merge_request[target_branch]", value: targetBranch),
            URLQueryItem(name: "merge_request[title]", value: title)
        ]
        if !description.isEmpty {
            items.append(URLQueryItem(name: "merge_request[description]", value: description))
        }
        components?.queryItems = items
        return components?.url
    }
}
