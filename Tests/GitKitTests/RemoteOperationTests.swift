import Foundation
@testable import GitKit
import Testing

struct RemoteOperationTests {
    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    @Test func remotesListsConfiguredOrigin() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }

        let remotes = try await CLIGitProvider(gitURL: gitURL).remotes(in: fixture.repo.url)

        #expect(remotes.count == 1)
        #expect(remotes[0].name == "origin")
        #expect(remotes[0].fetchURL != nil)
        #expect(remotes[0].pushURL != nil)
    }

    @Test func fetchUpdatesRemoteBranches() async throws {
        let fixture = try await makeEmptyRepoWithOrigin()
        defer { fixture.removeAll() }

        let result = try await CLIGitProvider(gitURL: gitURL).fetch(remote: "origin", in: fixture.repo.url)
        let refs = try await CLIGitProvider(gitURL: gitURL).refs(in: fixture.repo.url)

        #expect(!result.output.isEmpty)
        #expect(refs.remoteBranches.contains { $0.name == "origin/main" })
    }

    @Test func pullOnUpToDateCloneSucceeds() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }

        let result = try await CLIGitProvider(gitURL: gitURL).pull(in: fixture.repo.url)

        #expect(result.output.contains("Already up to date") || result.output.contains("Already up-to-date"))
    }

    @Test func pushWithoutOriginThrows() async throws {
        let repo = try await GitFixture.make()
        defer { repo.removeDirectory() }
        try repo.write("a.txt", "v1\n")
        try await repo.git("add", "a.txt")
        try await repo.git("commit", "-q", "-m", "initial")

        do {
            _ = try await CLIGitProvider(gitURL: gitURL).push(in: repo.url)
            Issue.record("Expected push without origin to throw.")
        } catch GitError.invalidInput(let message) {
            #expect(message == "No upstream configured and no origin remote found.")
        } catch {
            Issue.record("Expected invalidInput, got \(error).")
        }
    }

    @Test func pushFromDetachedHeadThrows() async throws {
        let repo = try await GitFixture.make()
        defer { repo.removeDirectory() }
        try repo.write("a.txt", "v1\n")
        try await repo.git("add", "a.txt")
        try await repo.git("commit", "-q", "-m", "initial")
        try await repo.git("switch", "--detach", "HEAD")

        do {
            _ = try await CLIGitProvider(gitURL: gitURL).push(in: repo.url)
            Issue.record("Expected detached push to throw.")
        } catch GitError.invalidInput(let message) {
            #expect(message == "Cannot push from detached HEAD.")
        } catch {
            Issue.record("Expected invalidInput, got \(error).")
        }
    }

    private func makeClone() async throws -> RemoteRepoFixture {
        let remote = try await makeBareRemote()
        let cloneURL = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-clone-\(UUID().uuidString)")
        try await git(["clone", "-q", remote.path, cloneURL.path], in: nil)
        return RemoteRepoFixture(repo: GitFixture(url: cloneURL), remoteURL: remote)
    }

    private func makeEmptyRepoWithOrigin() async throws -> RemoteRepoFixture {
        let remote = try await makeBareRemote()
        let repo = try await GitFixture.make()
        try await repo.git("remote", "add", "origin", remote.path)
        return RemoteRepoFixture(repo: repo, remoteURL: remote)
    }

    private func makeBareRemote() async throws -> URL {
        let seed = try await GitFixture.make()
        try seed.write("a.txt", "v1\n")
        try await seed.git("add", "a.txt")
        try await seed.git("commit", "-q", "-m", "initial")
        try await seed.git("branch", "-M", "main")

        let remote = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-remote-\(UUID().uuidString).git")
        try await git(["clone", "--bare", "-q", seed.url.path, remote.path], in: nil)
        seed.removeDirectory()
        return remote
    }

    @discardableResult
    private func git(_ arguments: [String], in workingDirectory: URL?) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: gitURL,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(
                command: "git " + arguments.joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result
    }
}

private struct RemoteRepoFixture {
    let repo: GitFixture
    let remoteURL: URL

    func removeAll() {
        repo.removeDirectory()
        try? FileManager.default.removeItem(at: remoteURL)
    }
}
