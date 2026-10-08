@testable import AppUI
import Foundation
import Testing

struct AvatarSourceTests {
    struct URLCase: Sendable, CustomTestStringConvertible {
        let name: String
        let email: String
        let gitLabHost: String?
        let expected: [String]

        var testDescription: String {
            name
        }
    }

    static let urlCases: [URLCase] = [
        URLCase(
            name: "a GitHub no-reply address with an account ID",
            email: "12345+mrcat71@users.noreply.github.com", gitLabHost: nil,
            expected: [
                "https://avatars.githubusercontent.com/u/12345?s=40&v=4",
                "https://gravatar.com/avatar/" + sha("12345+mrcat71@users.noreply.github.com") + "?s=40&d=404"
            ]
        ),
        URLCase(
            name: "an older GitHub no-reply address",
            email: "mrcat71@users.noreply.github.com", gitLabHost: nil,
            expected: [
                "https://github.com/mrcat71.png?size=40",
                "https://gravatar.com/avatar/" + sha("mrcat71@users.noreply.github.com") + "?s=40&d=404"
            ]
        ),
        URLCase(
            name: "Gravatar gets a hash of the trimmed, lowercased address",
            email: "  Test@Example.com ", gitLabHost: nil,
            expected: ["https://gravatar.com/avatar/973dfe463ec85785f5f95af5ba3906eedb2d931c24e69824a89ea65dba4e813b?s=40&d=404"]
        ),
        URLCase(
            name: "a GitLab repository asks its instance first",
            email: "a.svinarenko+ops@example.com", gitLabHost: "git.devspt.com",
            expected: [
                "https://git.devspt.com/api/v4/avatar?email=a.svinarenko%2Bops@example.com&size=40",
                "https://gravatar.com/avatar/" + sha("a.svinarenko+ops@example.com") + "?s=40&d=404"
            ]
        ),
        URLCase(name: "no address, no lookup", email: "  ", gitLabHost: nil, expected: [])
    ]

    @Test(arguments: urlCases)
    func urls(_ testCase: URLCase) {
        let urls = AvatarSource.urls(email: testCase.email, gitLabHost: testCase.gitLabHost, pixels: 40)
        #expect(urls.map(\.absoluteString) == testCase.expected)
    }

    @Test(arguments: [
        ("Andrey Svinarenko", "AS"),
        ("renovate-okira[bot]", "R"),
        ("j.doe", "JD"),
        ("Zoë Müller Schmidt", "ZM"),
        ("", "?"),
        ("123", "?")
    ])
    func initials(_ name: String, _ expected: String) {
        #expect(AvatarSource.initials(for: name) == expected)
    }

    private static func sha(_ text: String) -> String {
        AvatarSource.gravatarURL(email: text, pixels: 40)!.lastPathComponent
    }
}
