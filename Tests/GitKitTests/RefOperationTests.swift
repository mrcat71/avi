import Foundation
@testable import GitKit
import Testing

struct RefOperationTests {
    private func provider(_ repo: GitFixture) -> CLIGitProvider {
        CLIGitProvider(gitURL: repo.gitURL)
    }

    @Test func refsListLocalBranchesAndTags() async throws {
        try await withCommittedRepo { repo in
            let initialBranch = try #require(try await provider(repo).status(in: repo.url).branch.name)
            try await repo.git("branch", "feature")
            try await repo.git("tag", "v1.0.0")

            let refs = try await provider(repo).refs(in: repo.url)

            #expect(refs.localBranches.map(\.name).contains(initialBranch))
            #expect(refs.localBranches.map(\.name).contains("feature"))
            #expect(refs.localBranches.first { $0.name == initialBranch }?.isCurrent == true)
            #expect(refs.tags.map(\.name) == ["v1.0.0"])
        }
    }

    @Test func createBranchWithCheckoutSwitchesToNewBranch() async throws {
        try await withCommittedRepo { repo in
            try await provider(repo).createBranch(named: "feature", startPoint: nil, checkout: true, in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.branch.name == "feature")
        }
    }

    @Test func checkoutLocalBranchSwitchesBranch() async throws {
        try await withCommittedRepo { repo in
            try await repo.git("branch", "feature")
            let ref = try #require(try await provider(repo).refs(in: repo.url).localBranches.first { $0.name == "feature" })

            try await provider(repo).checkout(ref, in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.branch.name == "feature")
        }
    }

    @Test func checkoutTagDetachesHead() async throws {
        try await withCommittedRepo { repo in
            try await repo.git("tag", "v1.0.0")
            let ref = try #require(try await provider(repo).refs(in: repo.url).tags.first { $0.name == "v1.0.0" })

            try await provider(repo).checkout(ref, in: repo.url)

            let status = try await provider(repo).status(in: repo.url)
            #expect(status.branch.isDetached)
        }
    }

    @Test func deleteBranchRemovesLocalBranch() async throws {
        try await withCommittedRepo { repo in
            try await repo.git("branch", "delete-me")

            try await provider(repo).deleteBranch(named: "delete-me", in: repo.url)

            let refs = try await provider(repo).refs(in: repo.url)
            #expect(!refs.localBranches.map(\.name).contains("delete-me"))
        }
    }

    @Test func createBranchRejectsEmptyName() async throws {
        try await withCommittedRepo { repo in
            do {
                try await provider(repo).createBranch(named: "   ", startPoint: nil, checkout: false, in: repo.url)
                Issue.record("Expected empty branch name to throw.")
            } catch GitError.invalidInput(let message) {
                #expect(message == "Branch name cannot be empty.")
            } catch {
                Issue.record("Expected invalidInput, got \(error).")
            }
        }
    }

    private func withCommittedRepo(_ body: (GitFixture) async throws -> Void) async throws {
        try await withTempRepo { repo in
            try repo.write("a.txt", "v1\n")
            try await repo.git("add", "a.txt")
            try await repo.git("commit", "-q", "-m", "initial")
            try await body(repo)
        }
    }
}
