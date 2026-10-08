@testable import AppUI
import Foundation
import GitKit
import Testing

private let sha1 = String(repeating: "a", count: 40)
private let sha2 = String(repeating: "b", count: 40)
private let sha3 = String(repeating: "c", count: 40)
private let sha4 = String(repeating: "d", count: 40)

struct ForgeAvatarQueryTests {
    @Test(arguments: [
        ("a full SHA-1", "0123456789abcdef0123456789ABCDEF01234567", true),
        ("a full SHA-256", String(repeating: "f", count: 64), true),
        ("a short SHA", String(repeating: "a", count: 39), false),
        ("a quote that would end the string", "\") { x }" + String(repeating: "a", count: 32), false),
        ("letters past f", String(repeating: "g", count: 40), false),
        ("fullwidth digits", String(repeating: "\u{FF10}", count: 13) + "a", false),
        ("a ref name", "HEAD", false)
    ])
    func objectNames(_ name: String, _ text: String, _ expected: Bool) {
        #expect(ForgeAvatarQuery.isObjectName(text) == expected, "\(name)")
    }

    @Test func gitHubAsksForEachCommitsAuthorAccount() {
        let text = ForgeAvatarQuery.text(for: .gitHub, commits: [sha1, sha2], pixels: 64)
        let field = { (index: Int, sha: String) in
            "c\(index): object(oid: \"\(sha)\") { ... on Commit { author { user { avatarUrl(size: 64) } } } }"
        }
        #expect(text == "query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { \(field(0, sha1)) \(field(1, sha2)) } }")
    }

    @Test func gitLabAsksForEachCommitsAuthor() {
        let text = ForgeAvatarQuery.text(for: .gitLab, commits: [sha1], pixels: 64)
        #expect(text == "query($path: ID!) { project(fullPath: $path) { repository { c0: commit(ref: \"\(sha1)\") { author { avatarUrl } } } } }")
    }

    @Test(arguments: [
        (AvatarOrigin(forge: .gitHub, host: "github.com", project: "mrcat71/avi"), ["owner": "mrcat71", "name": "avi"]),
        (AvatarOrigin(forge: .gitLab, host: "git.example.com", project: "group/sub/project"), ["path": "group/sub/project"])
    ])
    func theProjectGoesInAsVariables(_ origin: AvatarOrigin, _ expected: [String: String]) {
        #expect(ForgeAvatarQuery.variables(for: origin) == expected)
    }

    struct AnswerCase: Sendable, CustomTestStringConvertible {
        let name: String
        let forge: AvatarOrigin.Forge
        let json: String
        let count: Int
        let expected: [ForgeAvatarQuery.Answer]?

        var testDescription: String {
            name
        }
    }

    static let answerCases: [AnswerCase] = [
        AnswerCase(
            name: "GitHub: an account, an address no account has, and a commit GitHub lacks",
            forge: .gitHub,
            json: #"{"data":{"repository":{"c0":{"author":{"user":{"avatarUrl":"https://avatars.githubusercontent.com/u/1?s=64"}}},"c1":{"author":{"user":null}},"c2":null}}}"#,
            count: 3,
            expected: [.account(URL(string: "https://avatars.githubusercontent.com/u/1?s=64")!), .noAccount, .unknownCommit]
        ),
        AnswerCase(
            name: "GitHub: a repository the account cannot see",
            forge: .gitHub,
            json: #"{"data":{"repository":null},"errors":[{"message":"Could not resolve to a Repository"}]}"#,
            count: 1,
            expected: nil
        ),
        AnswerCase(
            name: "GitLab: an absolute picture, a relative one, a placeholder, no account, an unknown commit",
            forge: .gitLab,
            json: #"""
            {"data":{"project":{"repository":{
              "c0":{"author":{"avatarUrl":"https://secure.gravatar.com/avatar/x?s=80&d=identicon"}},
              "c1":{"author":{"avatarUrl":"/uploads/-/system/user/avatar/7/avatar.png"}},
              "c2":{"author":{"avatarUrl":"/assets/no_avatar-849f9c04.png"}},
              "c3":{"author":null},
              "c4":null}}}}
            """#,
            count: 5,
            expected: [
                .account(URL(string: "https://secure.gravatar.com/avatar/x?s=80&d=identicon")!),
                .account(URL(string: "https://git.example.com/uploads/-/system/user/avatar/7/avatar.png")!),
                .noAccount, .noAccount, .unknownCommit
            ]
        ),
        AnswerCase(
            name: "GitLab: a project the account cannot see",
            forge: .gitLab,
            json: #"{"data":{"project":null}}"#,
            count: 1,
            expected: nil
        ),
        AnswerCase(
            name: "a picture that is not on the web",
            forge: .gitHub,
            json: #"{"data":{"repository":{"c0":{"author":{"user":{"avatarUrl":"file:///etc/passwd"}}}}}}"#,
            count: 1,
            expected: [.noAccount]
        ),
        AnswerCase(name: "not JSON", forge: .gitHub, json: "gh: not logged in", count: 1, expected: nil)
    ]

    @Test(arguments: answerCases)
    func answers(_ testCase: AnswerCase) {
        let answers = ForgeAvatarQuery.answers(
            from: Data(testCase.json.utf8), forge: testCase.forge, count: testCase.count,
            base: URL(string: "https://git.example.com")
        )
        #expect(answers == testCase.expected)
    }

    @Test(arguments: [
        ("mrcat71/avi", sha1, "https://api.github.com/repos/mrcat71/avi/commits?sha=\(sha1)&per_page=1"),
        ("mrcat71/avi.js", sha1, "https://api.github.com/repos/mrcat71/avi.js/commits?sha=\(sha1)&per_page=1"),
        ("owner/repo/extra", sha1, nil),
        ("owner/re po", sha1, nil),
        ("mrcat71/avi", "main", nil)
    ])
    func gitHubRESTURLs(_ project: String, _ commit: String, _ expected: String?) {
        #expect(ForgeAvatarQuery.gitHubRESTURL(project: project, commit: commit)?.absoluteString == expected)
    }

    @Test(arguments: [
        ("an account", 200, #"[{"sha":"\#(sha1)","author":{"avatar_url":"https://avatars.githubusercontent.com/u/9?v=4"}}]"#,
         ForgeAvatarQuery.Answer.account(URL(string: "https://avatars.githubusercontent.com/u/9?v=4")!)),
        ("no account", 200, #"[{"sha":"\#(sha1)","author":null}]"#, .noAccount),
        ("another commit first", 200, #"[{"sha":"\#(sha2)","author":null}]"#, .unknownCommit),
        ("a commit GitHub lacks", 404, #"{"message":"No commit found for SHA: \#(sha1)"}"#, .unknownCommit),
        ("a private repository", 404, #"{"message":"Not Found"}"#, nil),
        ("a server error", 500, "", nil)
    ] as [(String, Int, String, ForgeAvatarQuery.Answer?)])
    func gitHubRESTAnswers(_ name: String, _ status: Int, _ json: String, _ expected: ForgeAvatarQuery.Answer?) {
        #expect(ForgeAvatarQuery.gitHubRESTAnswer(status: status, data: Data(json.utf8), commit: sha1) == expected, "\(name)")
    }

    @Test func eachAuthorIsAskedAboutTheirOldestThenNewestCommit() {
        let commits = [
            commit(sha3, email: "ada@example.com"),
            commit(sha2, email: "bob@example.com"),
            commit(sha1, email: " ADA@example.com ")
        ]
        #expect(ForgeAvatarQuery.candidates(in: commits) == [
            "ada@example.com": [sha1, sha3],
            "bob@example.com": [sha2]
        ])
    }

    @Test(arguments: [
        (ProviderHint.github(owner: "mrcat71", repo: "avi"), AvatarOrigin(forge: .gitHub, host: "github.com", project: "mrcat71/avi")),
        (.gitlab(host: "Git.Example.com", projectPath: "group/project"), AvatarOrigin(forge: .gitLab, host: "git.example.com", project: "group/project")),
        (.unknown, nil)
    ] as [(ProviderHint, AvatarOrigin?)])
    func originsComeFromTheRemote(_ hint: ProviderHint, _ expected: AvatarOrigin?) {
        #expect(AvatarOrigin(hint) == expected)
    }

    @Test(arguments: [
        (AvatarOrigin.Forge.gitHub, "", "https://api.github.com/graphql"),
        (.gitLab, "", "https://gitlab.com/api/graphql"),
        (.gitLab, "https://git.example.com", "https://git.example.com/api/graphql"),
        (.gitLab, "https://example.com/gitlab", "https://example.com/gitlab/api/graphql")
    ])
    @MainActor
    func graphQLEndpoints(_ forge: AvatarOrigin.Forge, _ instanceURL: String, _ expected: String) {
        let origin = AvatarOrigin(forge: forge, host: "example.com", project: "a/b")
        #expect(ForgeAvatars.graphQLEndpoint(for: origin, instanceURL: instanceURL)?.absoluteString == expected)
    }

    /// `-F` would read a value starting with "@" as a file; `-f` passes it
    /// as it is. `echo` stands in for `gh` to show the arguments.
    @Test @MainActor
    func theCLIGetsVariablesAsPlainStrings() async throws {
        let transport = ForgeAvatars.cli("/bin/echo", host: "github.com")
        let output = try await transport.send("query { x }", ["owner": "@etc/passwd", "name": "avi"])
        #expect(String(decoding: output, as: UTF8.self)
            == "api graphql --hostname github.com -f query=query { x } -f name=avi -f owner=@etc/passwd\n")
    }

    @Test(arguments: [
        ("https://git.example.com/api/graphql", true),
        ("https://GIT.example.com/other", true),
        ("https://storage.example.net/bucket/x", false)
    ])
    func aTokenFollowsRedirectsOnlyWithinItsHost(_ target: String, _ followed: Bool) async throws {
        let source = try #require(URL(string: "https://git.example.com/api/graphql"))
        let task = URLSession.shared.dataTask(with: URLRequest(url: source))
        let response = try #require(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let next = try URLRequest(url: #require(URL(string: target)))
        let result = await SameHostRedirects().urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: next)
        #expect((result != nil) == followed)
    }

    private func commit(_ oid: String, email: String) -> CommitSummary {
        CommitSummary(
            oid: oid, parentOIDs: [], authorName: "A", authorEmail: email,
            authorDate: Date(timeIntervalSince1970: 0), subject: "s", body: ""
        )
    }
}

@MainActor
struct ForgeAvatarsTests {
    private let gitHub = AvatarOrigin(forge: .gitHub, host: "github.com", project: "mrcat71/avi")
    private let gitLab = AvatarOrigin(forge: .gitLab, host: "git.example.com", project: "group/project")

    @Test func authorsWantedTogetherGoOutAsOneQuery() async {
        let calls = Calls()
        let transport = ForgeAvatars.Transport(name: "fake") { query, _ in
            await calls.record(query)
            return Data(#"{"data":{"repository":{"c0":null,"c1":{"author":{"user":{"avatarUrl":"https://avatars.githubusercontent.com/u/1"}}},"c2":{"author":{"user":null}}}}}"#.utf8)
        }
        let avatars = ForgeAvatars(transports: { _ in [transport] }, anonymousGET: Self.unexpected, gathering: .milliseconds(100))
        async let ada = avatars.avatarURL(email: "ada@example.com", commits: [sha1, sha2], origin: gitHub, pixels: 32)
        async let bob = avatars.avatarURL(email: "bob@example.com", commits: [sha3], origin: gitHub, pixels: 32)
        #expect(await ada == URL(string: "https://avatars.githubusercontent.com/u/1"), "the newest commit is not pushed, the oldest is")
        #expect(await bob == nil, "no account has Bob's address")
        #expect(await calls.count == 1)
    }

    @Test func aLargeScreenOfAuthorsGoesOutInBatches() async {
        let calls = Calls()
        let transport = ForgeAvatars.Transport(name: "fake") { query, _ in
            await calls.record(query)
            let count = query.components(separatedBy: "object(oid:").count - 1
            let fields = (0 ..< count).map { #""c\#($0)":{"author":{"user":{"avatarUrl":"https://example.com/\#($0).png"}}}"# }
            return Data(#"{"data":{"repository":{\#(fields.joined(separator: ","))}}}"#.utf8)
        }
        let avatars = ForgeAvatars(transports: { _ in [transport] }, anonymousGET: Self.unexpected, gathering: .milliseconds(100))
        let urls = await withTaskGroup(of: URL?.self) { group in
            for index in 0 ..< 21 {
                let commits = [String(format: "%040x", index * 2 + 1), String(format: "%040x", index * 2 + 2)]
                group.addTask { await avatars.avatarURL(email: "author\(index)@example.com", commits: commits, origin: gitHub, pixels: 32) }
            }
            var urls: [URL?] = []
            for await url in group {
                urls.append(url)
            }
            return urls
        }
        #expect(urls.allSatisfy { $0 != nil })
        #expect(await calls.count == 2, "40 commits fit one query; 42 need two")
    }

    @Test func aFailingWayFallsThroughAndTheOneThatAnsweredIsKept() async {
        let calls = Calls()
        let broken = ForgeAvatars.Transport(name: "broken") { _, _ in
            await calls.record("broken")
            throw ForgeAvatarError.http(401)
        }
        let working = ForgeAvatars.Transport(name: "working") { _, _ in
            await calls.record("working")
            return Data(#"{"data":{"repository":{"c0":{"author":{"user":{"avatarUrl":"https://example.com/a.png"}}}}}}"#.utf8)
        }
        let avatars = ForgeAvatars(transports: { _ in [broken, working] }, anonymousGET: Self.unexpected, gathering: .milliseconds(10))
        #expect(await avatars.avatarURL(email: "a@example.com", commits: [sha1], origin: gitHub, pixels: 32) == URL(string: "https://example.com/a.png"))
        #expect(await avatars.avatarURL(email: "b@example.com", commits: [sha2], origin: gitHub, pixels: 32) == URL(string: "https://example.com/a.png"))
        #expect(await calls.names == ["broken", "working", "working"])
    }

    @Test func withoutAWayInGitHubIsAskedAnonymouslyUntilTheAllowanceIsSpent() async {
        let requests = Calls()
        let avatars = ForgeAvatars(transports: { _ in [] }, anonymousGET: { url in
            await requests.record(url.absoluteString)
            let query = url.query ?? ""
            if query.contains(sha1) {
                return (Data(#"{"message":"No commit found for SHA: \#(sha1)"}"#.utf8), 404)
            }
            if query.contains(sha2) {
                return (Data(#"[{"sha":"\#(sha2)","author":{"avatar_url":"https://avatars.githubusercontent.com/u/2"}}]"#.utf8), 200)
            }
            return (Data(#"{"message":"API rate limit exceeded"}"#.utf8), 403)
        }, gathering: .milliseconds(10))
        #expect(await avatars.avatarURL(email: "a@example.com", commits: [sha1, sha2], origin: gitHub, pixels: 32)
            == URL(string: "https://avatars.githubusercontent.com/u/2"))
        #expect(await avatars.avatarURL(email: "b@example.com", commits: [sha3], origin: gitHub, pixels: 32) == nil)
        #expect(await avatars.avatarURL(email: "c@example.com", commits: [sha4], origin: gitHub, pixels: 32) == nil)
        #expect(await requests.count == 3, "nothing is asked once the allowance is spent")
    }

    @Test func aProjectNoWayCanSeeIsLeftAloneForTheLaunch() async {
        let calls = Calls()
        let transport = ForgeAvatars.Transport(name: "glab") { _, _ in
            await calls.record("glab")
            return Data(#"{"data":{"project":null}}"#.utf8)
        }
        let avatars = ForgeAvatars(transports: { _ in [transport] }, anonymousGET: Self.unexpected, gathering: .milliseconds(10))
        #expect(await avatars.avatarURL(email: "a@example.com", commits: [sha1], origin: gitLab, pixels: 32) == nil)
        #expect(await avatars.avatarURL(email: "b@example.com", commits: [sha2], origin: gitLab, pixels: 32) == nil)
        #expect(await calls.count == 1)
    }

    @Test func onlyObjectNamesAreSent() async {
        let calls = Calls()
        let transport = ForgeAvatars.Transport(name: "fake") { query, _ in
            await calls.record(query)
            return Data()
        }
        let avatars = ForgeAvatars(transports: { _ in [transport] }, anonymousGET: Self.unexpected, gathering: .milliseconds(10))
        #expect(await avatars.avatarURL(email: "a@example.com", commits: ["HEAD", "\") { evil }"], origin: gitHub, pixels: 32) == nil)
        #expect(await calls.count == 0)
    }

    private static let unexpected: ForgeAvatars.AnonymousGET = { url in
        Issue.record("unexpected anonymous request to \(url)")
        return (Data(), 500)
    }
}

private actor Calls {
    private(set) var names: [String] = []

    var count: Int {
        names.count
    }

    func record(_ name: String) {
        names.append(name)
    }
}
