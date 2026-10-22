@testable import AppUI
import Testing

@Suite("Pull request titles from branch names")
struct PullRequestTitleTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let branch: String
        var ticketPrefixes: [String] = []
        var keepHyphenated: [String] = []
        var capitalize = false
        var knownNames: Set<String> = []
        let expected: String

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(name: "hyphens become spaces", branch: "fix-login-timeout", expected: "fix login timeout"),
        Case(name: "underscores become spaces", branch: "update_helm_chart", expected: "update helm chart"),
        Case(name: "a ticket key keeps its hyphen", branch: "INFRA-12345-fix-ingress-timeouts", expected: "INFRA-12345 fix ingress timeouts"),
        Case(name: "a ticket key in the middle", branch: "bump-chart-for-OPS-7", expected: "bump chart for OPS-7"),
        Case(name: "folders are dropped", branch: "feature/add-dark-mode", expected: "add dark mode"),
        Case(name: "a user folder is dropped", branch: "andrei/feature/add-dark-mode", expected: "add dark mode"),
        Case(name: "a ticket folder is kept in front", branch: "INFRA-12345/fix-ingress", expected: "INFRA-12345 fix ingress"),
        Case(
            name: "a listed lower-case ticket project is written in capitals",
            branch: "infra-12345-bump-chart", ticketPrefixes: ["INFRA"],
            expected: "INFRA-12345 bump chart"
        ),
        Case(name: "an unlisted lower-case word and number split", branch: "python-3-upgrade", expected: "python 3 upgrade"),
        Case(
            name: "a name found in the repository keeps its hyphens",
            branch: "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress",
            knownNames: ["k8s-infra-ah-ams1"],
            expected: "INFRA-12345 upgrade k8s-infra-ah-ams1 ingress"
        ),
        Case(
            name: "the longest known name wins",
            branch: "deploy-k8s-infra-ah-ams1",
            knownNames: ["k8s-infra", "k8s-infra-ah-ams1"],
            expected: "deploy k8s-infra-ah-ams1"
        ),
        Case(
            name: "known names match in any case and keep the branch's",
            branch: "move-K8s-Infra-ah-ams1-dns",
            knownNames: ["k8s-infra-ah-ams1"],
            expected: "move K8s-Infra-ah-ams1 dns"
        ),
        Case(
            name: "the documented example",
            branch: "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress",
            ticketPrefixes: ["INFRA", "OPS"], keepHyphenated: ["k8s-*-*-ams1", "/[a-z0-9]+-[a-z]{3}[0-9]+/"],
            expected: "INFRA-12345 upgrade k8s-infra-ah-ams1 ingress"
        ),
        Case(
            name: "the documented expression on its own",
            branch: "move-edge-fra2-dns", keepHyphenated: ["/[a-z0-9]+-[a-z]{3}[0-9]+/"],
            expected: "move edge-fra2 dns"
        ),
        Case(name: "a literal name from the rules", branch: "fix-k8s-infra-ah-ams1-dns", keepHyphenated: ["k8s-infra-ah-ams1"], expected: "fix k8s-infra-ah-ams1 dns"),
        Case(name: "a glob where a star is one word", branch: "fix-k8s-infra-ah-ams1-dns", keepHyphenated: ["k8s-*-*-ams1"], expected: "fix k8s-infra-ah-ams1 dns"),
        Case(
            name: "a glob does not reach across words it does not cover",
            branch: "fix-k8s-infra-ah-ams1-dns", keepHyphenated: ["k8s-*"],
            expected: "fix k8s-infra ah ams1 dns"
        ),
        Case(
            name: "a regular expression between slashes",
            branch: "roll-out-k8s-infra-ah-ams1-and-k8s-web-fra2",
            keepHyphenated: ["/k8s-[a-z]+(-[a-z]+)?-[a-z]+[0-9]/"],
            expected: "roll out k8s-infra-ah-ams1 and k8s-web-fra2"
        ),
        Case(name: "a match inside a word does not count", branch: "rework-infra-docs", keepHyphenated: ["fra-docs"], expected: "rework infra docs"),
        Case(name: "capitalizing skips the ticket key", branch: "INFRA-1-fix-login", capitalize: true, expected: "INFRA-1 Fix login"),
        Case(name: "capitalizing skips a kept name", branch: "k8s-infra-ah-ams1-dns", capitalize: true, knownNames: ["k8s-infra-ah-ams1"], expected: "k8s-infra-ah-ams1 Dns"),
        Case(name: "repeated separators count once", branch: "fix--double__separators", expected: "fix double separators"),
        Case(name: "dots stay in their word", branch: "release-1.2.3-notes", expected: "release 1.2.3 notes"),
        Case(name: "a plain name stays as it is", branch: "main", expected: "main"),
        Case(name: "nothing but separators falls back to the branch", branch: "---", expected: "---")
    ]

    @Test(arguments: cases)
    func title(_ testCase: Case) {
        let rules = PullRequestTitle.Rules(
            ticketPrefixes: testCase.ticketPrefixes,
            keepHyphenated: testCase.keepHyphenated,
            capitalize: testCase.capitalize
        )
        #expect(PullRequestTitle.make(branch: testCase.branch, rules: rules, knownNames: testCase.knownNames) == testCase.expected)
    }

    @Test
    func repositoryNamesComeFromFileAndFolderNames() {
        let names = PullRequestTitle.knownNames(
            fromPaths: [
                "environments/k8s-infra-ah-ams1/values.yaml",
                "clusters/k8s-web-fra2.tfvars",
                ".pre-commit-config.yaml",
                "README.md",
                "docs/how_to/release.md"
            ],
            extra: ["my-repo"]
        )
        #expect(names == ["k8s-infra-ah-ams1", "k8s-web-fra2", "pre-commit-config", "how_to", "my-repo"])
    }

    @Test
    func repositoryNamesStopAtTheLimit() {
        let paths = (0 ..< 10).map { "dir-\($0)/file" }
        #expect(PullRequestTitle.knownNames(fromPaths: paths, limit: 3).count == 3)
    }
}

struct PullRequestSettingsTextTests {
    @Test(arguments: [
        ("INFRA, ops", ["INFRA", "ops"]),
        ("INFRA,", ["INFRA"]),
        (" , ,", []),
        ("", [])
    ])
    func prefixesAreSeparatedByCommas(text: String, entries: [String]) {
        #expect(PullRequestSettingsText.entries(commaSeparated: text) == entries)
    }

    @Test func namesTakeOneLineEach() {
        let text = "k8s-*-*-ams1\n\n  /k8s-[a-z]{2,4}-[0-9]+/  \ninfra-live\n"
        #expect(PullRequestSettingsText.entries(lines: text) == ["k8s-*-*-ams1", "/k8s-[a-z]{2,4}-[0-9]+/", "infra-live"])
    }
}
