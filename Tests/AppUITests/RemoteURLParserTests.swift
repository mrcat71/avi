@testable import AppUI
import Testing

struct RemoteURLParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let url: String
        var knownGitLab: Set<String> = []
        let expected: ProviderHint

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(name: "github over SSH", url: "git@github.com:mrcat71/avi.git", expected: .github(owner: "mrcat71", repo: "avi")),
        Case(name: "github over HTTPS", url: "https://github.com/mrcat71/avi", expected: .github(owner: "mrcat71", repo: "avi")),
        Case(name: "gitlab.com with a subgroup", url: "git@gitlab.com:group/sub/project.git", expected: .gitlab(host: "gitlab.com", projectPath: "group/sub/project")),
        Case(name: "a host named gitlab", url: "https://gitlab.example.com/ops/infra.git", expected: .gitlab(host: "gitlab.example.com", projectPath: "ops/infra")),
        Case(
            name: "a self-hosted GitLab glab knows, over SSH",
            url: "git@git.devspt.com:ops/terraform.git", knownGitLab: ["git.devspt.com"],
            expected: .gitlab(host: "git.devspt.com", projectPath: "ops/terraform")
        ),
        Case(
            name: "a self-hosted GitLab glab knows, over HTTPS",
            url: "https://git.devspt.com/ops/k8s-cluster.git", knownGitLab: ["git.devspt.com"],
            expected: .gitlab(host: "git.devspt.com", projectPath: "ops/k8s-cluster")
        ),
        Case(
            name: "known hosts match regardless of case",
            url: "git@Git.Devspt.com:ops/terraform.git", knownGitLab: ["git.devspt.com"],
            expected: .gitlab(host: "Git.Devspt.com", projectPath: "ops/terraform")
        ),
        Case(
            name: "an SSH URL with a port",
            url: "ssh://git@git.devspt.com:2222/ops/help-arena.git", knownGitLab: ["git.devspt.com"],
            expected: .gitlab(host: "git.devspt.com", projectPath: "ops/help-arena")
        ),
        Case(name: "an unknown host stays unknown", url: "git@git.devspt.com:ops/terraform.git", expected: .unknown),
        Case(name: "a known host without a project", url: "https://git.devspt.com", knownGitLab: ["git.devspt.com"], expected: .unknown),
        Case(name: "an empty URL", url: "  ", expected: .unknown)
    ]

    @Test(arguments: cases)
    func hint(_ testCase: Case) {
        let hosts = ProviderHosts(gitlab: testCase.knownGitLab)
        #expect(RemoteURLParser.hint(from: testCase.url, knownHosts: hosts) == testCase.expected)
    }
}
