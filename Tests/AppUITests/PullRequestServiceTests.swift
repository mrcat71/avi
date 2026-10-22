@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Pull requests")
struct PullRequestServiceTests {
    private let github = Forge.github(owner: "mrcat71", repo: "avi")
    private let gitlab = Forge.gitlab(host: "git.example.com", projectPath: "ops/k8s-infra")
    private let request = PullRequestRequest(
        title: "-rf INFRA-1 fix ingress",
        body: "Line one\nLine two",
        head: "feature/INFRA-1-fix-ingress",
        base: "main",
        isDraft: true
    )

    @Test func ghGetsEveryValueAttachedToItsFlag() {
        #expect(PullRequestService.createArguments(request, on: github) == [
            "pr", "create",
            "--repo=mrcat71/avi",
            "--head=feature/INFRA-1-fix-ingress",
            "--base=main",
            "--title=-rf INFRA-1 fix ingress",
            "--body=Line one\nLine two",
            "--draft"
        ])
    }

    @Test func glabGetsTheProjectURLAndNeverAsks() {
        #expect(PullRequestService.createArguments(request, on: gitlab) == [
            "mr", "create",
            "--repo=https://git.example.com/ops/k8s-infra",
            "--source-branch=feature/INFRA-1-fix-ingress",
            "--target-branch=main",
            "--title=-rf INFRA-1 fix ingress",
            "--description=Line one\nLine two",
            "--yes",
            "--draft"
        ])
        #expect(PullRequestService.cliEnvironment(for: gitlab)["NO_PROMPT"] == "1")
        #expect(PullRequestService.cliEnvironment(for: github)["GH_PROMPT_DISABLED"] == "1")
    }

    @Test func listingAsksForOpenRequestsFromTheBranch() {
        #expect(PullRequestService.listArguments(head: "fix", on: github).contains("--head=fix"))
        #expect(PullRequestService.listArguments(head: "fix", on: github).contains("--state=open"))
        #expect(PullRequestService.listArguments(head: "fix", on: gitlab).contains("--source-branch=fix"))
    }

    @Test func theCreatedAddressIsFoundInWhatTheCLIPrinted() throws {
        let gh = "Warning: 1 uncommitted change\nhttps://github.com/mrcat71/avi/pull/42\n"
        let ghURL = try #require(PullRequestService.createdURL(in: gh, forge: github))
        #expect(ghURL.absoluteString == "https://github.com/mrcat71/avi/pull/42")
        #expect(PullRequestService.number(in: ghURL) == 42)

        let glab = "Creating merge request for feature into main in ops/k8s-infra\n\n!7 fix ingress (feature)\n https://git.example.com/ops/k8s-infra/-/merge_requests/7\n"
        let glabURL = try #require(PullRequestService.createdURL(in: glab, forge: gitlab))
        #expect(glabURL.absoluteString == "https://git.example.com/ops/k8s-infra/-/merge_requests/7")
        #expect(PullRequestService.number(in: glabURL) == 7)
        #expect(PullRequestService.createdURL(in: "nothing here", forge: github) == nil)
    }

    @Test func openRequestsAreReadFromEitherCLI() throws {
        let gh = Data(#"[{"number":5,"url":"https://github.com/mrcat71/avi/pull/5","title":"fix","isDraft":true}]"#.utf8)
        #expect(try PullRequestService.firstOpen(in: gh, forge: github)
            == PullRequestInfo(number: 5, url: #require(URL(string: "https://github.com/mrcat71/avi/pull/5")), title: "fix", isDraft: true))

        let glab = Data(#"[{"iid":3,"web_url":"https://git.example.com/ops/k8s-infra/-/merge_requests/3","title":"fix","draft":false,"state":"opened"}]"#.utf8)
        #expect(PullRequestService.firstOpen(in: glab, forge: gitlab)?.number == 3)
        #expect(PullRequestService.firstOpen(in: Data("[]".utf8), forge: github) == nil)
        #expect(PullRequestService.firstOpen(in: Data("not json".utf8), forge: gitlab) == nil)
    }

    @Test func gitlabDraftsAreMarkedInTheTitle() {
        #expect(PullRequestService.draftTitle(request, on: gitlab) == "Draft: -rf INFRA-1 fix ingress")
        #expect(PullRequestService.draftTitle(request, on: github) == request.title)
        var ready = request
        ready.isDraft = false
        #expect(PullRequestService.draftTitle(ready, on: gitlab) == request.title)
    }

    @Test func theBrowserFormIsFilledIn() throws {
        let githubURL = try #require(PullRequestService.browserURL(for: request, on: github))
        let githubItems = URLComponents(url: githubURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(githubURL.path == "/mrcat71/avi/compare/main...feature/INFRA-1-fix-ingress")
        #expect(githubItems.contains(URLQueryItem(name: "title", value: request.title)))
        #expect(githubItems.contains(URLQueryItem(name: "body", value: request.body)))

        let gitlabURL = try #require(PullRequestService.browserURL(for: request, on: gitlab))
        let gitlabItems = URLComponents(url: gitlabURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(gitlabItems.contains(URLQueryItem(name: "merge_request[source_branch]", value: request.head)))
        #expect(gitlabItems.contains(URLQueryItem(name: "merge_request[title]", value: "Draft: \(request.title)")))
        #expect(gitlabItems.contains(URLQueryItem(name: "merge_request[description]", value: request.body)))
    }

    @Test func theRepositoryTemplateIsFoundWhereEachForgeLooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-pr-template-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".github"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".gitlab/merge_request_templates"), withIntermediateDirectories: true)
        try "## Summary\n".write(to: root.appendingPathComponent(".github/pull_request_template.md"), atomically: true, encoding: .utf8)
        try "## Change\n".write(to: root.appendingPathComponent(".gitlab/merge_request_templates/Infra.md"), atomically: true, encoding: .utf8)

        #expect(RepositoryStore.pullRequestTemplate(in: root, forge: github) == "## Summary\n")
        #expect(RepositoryStore.pullRequestTemplate(in: root, forge: gitlab) == "## Change\n")
        #expect(RepositoryStore.pullRequestTemplate(in: root.appendingPathComponent("missing"), forge: github) == nil)
    }
}

@Suite("Pull request context")
@MainActor
struct PullRequestContextTests {
    @Test func theTitleKeepsTicketsAndNamesFromTheRepository() async throws {
        let fake = provider(branch: "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress")
        fake.trackedPaths = ["environments/k8s-infra-ah-ams1/main.tf", "README.md"]
        fake.defaultBranchName = "main"
        let store = try await openStore(fake)

        let context = try #require(await store.loadPullRequestContext(branch: "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress", route: .browser))

        #expect(context.forge == .github(owner: "mrcat71", repo: "infra"))
        #expect(context.title == "INFRA-12345 upgrade k8s-infra-ah-ams1 ingress")
        #expect(context.titleAlternatives.first == "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress")
        #expect(context.defaultBase == "main")
        #expect(context.bases == ["main", "release"])
        #expect(context.existing == nil)
    }

    /// The Push sheet's first load is cancelled when its inputs settle; a
    /// failed lookup must not stick for the commit.
    @Test func aFailedNameLookupIsNotRemembered() async throws {
        let fake = provider(branch: "upgrade-k8s-infra-ah-ams1")
        fake.trackedPaths = ["environments/k8s-infra-ah-ams1/main.tf"]
        fake.trackedPathsError = CancellationError()
        let store = try await openStore(fake)
        let forge = Forge.github(owner: "mrcat71", repo: "infra")

        #expect(await !(store.pullRequestTitleNames(forge: forge)).contains("k8s-infra-ah-ams1"))
        fake.trackedPathsError = nil
        #expect(await store.pullRequestTitleNames(forge: forge).contains("k8s-infra-ah-ams1"))
    }

    @Test func aRemoteThatIsNeitherGitHubNorGitLabHasNoPullRequests() async throws {
        let fake = provider(branch: "fix", url: "git@example.com:org/repo.git")
        let store = try await openStore(fake)

        #expect(await store.loadPullRequestContext(branch: "fix", route: .browser) == nil)
        #expect(!store.canOfferPullRequest(for: "fix"))
    }

    @Test func aFirstPushOffersToCreateThePullRequest() async throws {
        let fake = provider(branch: "fix-login")
        let store = try await openStore(fake)

        await store.publish(branch: "fix-login", remote: "origin", force: false, pushTags: false)

        #expect(store.errorMessage == nil)
        #expect(store.pullRequestNotice?.kind == .pushedNewBranch(branch: "fix-login", remote: "origin"))
    }

    @Test func theDefaultBranchIsNeverOfferedAPullRequest() async throws {
        let fake = provider(branch: "main")
        fake.defaultBranchName = "main"
        let store = try await openStore(fake)
        await store.refreshDefaultBranch()

        #expect(!store.canOfferPullRequest(for: "main"))
    }

    private func provider(branch: String, url: String = "git@github.com:mrcat71/infra.git") -> FakeGitProvider {
        let oid = String(repeating: "a", count: 40)
        return FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: branch, oid: oid), entries: []),
            refs: RepositoryRefs(
                localBranches: [
                    GitReference(name: branch, fullName: "refs/heads/\(branch)", oid: oid, kind: .localBranch, isCurrent: true, subject: "Upgrade the ingress")
                ],
                remoteBranches: ["origin/HEAD", "origin/main", "origin/release"].map {
                    GitReference(name: $0, fullName: "refs/remotes/\($0)", oid: oid, kind: .remoteBranch)
                },
                tags: []
            ),
            commits: [],
            remotes: [GitRemote(name: "origin", fetchURL: url, pushURL: url)]
        )
    }

    private func openStore(_ fake: FakeGitProvider) async throws -> RepositoryStore {
        let store = RepositoryStore(git: fake)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-pull-requests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }
}
