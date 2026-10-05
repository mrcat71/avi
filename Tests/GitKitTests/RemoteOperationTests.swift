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

    @Test func deleteRemoteTagRemovesOnlyThatTagFromTheRemote() async throws {
        let remote = try await makeBareRemote()
        // A branch named like the tag must survive: only refs/tags/v1 may match.
        try await git(["--git-dir", remote.path, "branch", "v1", "main"], in: nil)
        try await git(["--git-dir", remote.path, "tag", "v1", "main"], in: nil)
        try await git(["--git-dir", remote.path, "tag", "v2", "main"], in: nil)
        let fixture = try await makeClone(of: remote)
        defer { fixture.removeAll() }

        let result = try await CLIGitProvider(gitURL: gitURL).deleteRemoteTag(named: "v1", remote: "origin", in: fixture.repo.url)

        #expect(result.output.contains("[deleted]"))
        let remoteRefs = try await git(["--git-dir", remote.path, "for-each-ref", "--format=%(refname)"], in: nil)
            .stdoutString.split(separator: "\n").map(String.init)
        #expect(remoteRefs.sorted() == ["refs/heads/main", "refs/heads/v1", "refs/tags/v2"])
        // The local tag is a separate delete.
        let localTags = try await CLIGitProvider(gitURL: gitURL).refs(in: fixture.repo.url).tags.map(\.name)
        #expect(localTags.sorted() == ["v1", "v2"])
    }

    /// Git only warns about a full ref name the remote lacks, so "delete here
    /// and on the remote" still works for a tag that was never pushed.
    @Test func deleteRemoteTagSucceedsWhenTheTagWasNeverPushed() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("tag", "local-only")

        _ = try await CLIGitProvider(gitURL: gitURL).deleteRemoteTag(named: "local-only", remote: "origin", in: fixture.repo.url)

        let localTags = try await CLIGitProvider(gitURL: gitURL).refs(in: fixture.repo.url).tags.map(\.name)
        #expect(localTags == ["local-only"])
    }

    /// The current branch already tracks origin/main; that must not stop a
    /// branch without an upstream from getting one.
    @Test func pushingABranchThatIsNotCheckedOutSetsItsOwnUpstream() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("branch", "topic")

        _ = try await CLIGitProvider(gitURL: gitURL).push(branch: "topic", remote: nil, force: false, pushTags: false, in: fixture.repo.url)

        let topic = try await CLIGitProvider(gitURL: gitURL).refs(in: fixture.repo.url).localBranches.first { $0.name == "topic" }
        #expect(topic?.upstream == "origin/topic")
        let remoteHeads = try await git(["--git-dir", fixture.remoteURL.path, "for-each-ref", "--format=%(refname)", "refs/heads"], in: nil)
            .stdoutString.split(separator: "\n").map(String.init)
        #expect(remoteHeads.sorted() == ["refs/heads/main", "refs/heads/topic"])
    }

    @Test func deleteRemoteBranchRemovesOnlyThatBranch() async throws {
        let remote = try await makeBareRemote()
        try await git(["--git-dir", remote.path, "branch", "topic", "main"], in: nil)
        // A tag named like the branch must survive.
        try await git(["--git-dir", remote.path, "tag", "topic", "main"], in: nil)
        let fixture = try await makeClone(of: remote)
        defer { fixture.removeAll() }

        let result = try await CLIGitProvider(gitURL: gitURL).deleteRemoteBranch(named: "topic", remote: "origin", in: fixture.repo.url)

        #expect(result.output.contains("[deleted]"))
        let remoteRefs = try await git(["--git-dir", remote.path, "for-each-ref", "--format=%(refname)"], in: nil)
            .stdoutString.split(separator: "\n").map(String.init)
        #expect(remoteRefs.sorted() == ["refs/heads/main", "refs/tags/topic"])
        let remoteBranches = try await CLIGitProvider(gitURL: gitURL).refs(in: fixture.repo.url).remoteBranches.map(\.name)
        #expect(!remoteBranches.contains("origin/topic"))
    }

    /// The error in the Git Error alert: Git 2.33+ refuses diverged branches
    /// until told how to reconcile them. Avi merges when nothing says otherwise.
    @Test func pullMergesDivergedBranchesWhenGitIsNotToldHow() async throws {
        let fixture = try await makeDivergedClone()
        defer { fixture.removeAll() }
        // A pull.rebase or pull.ff in your global config decides instead.
        for key in ["pull.rebase", "pull.ff"] where try await fixture.repo.gitConfigured(key) {
            return
        }

        _ = try await CLIGitProvider(gitURL: gitURL).pull(in: fixture.repo.url)

        let parents = try await fixture.repo.git("log", "-1", "--format=%P").stdoutString.split(separator: " ")
        #expect(parents.count == 2)
        #expect(try fixture.repo.read("local.txt") == "local\n")
        #expect(try fixture.repo.read("remote.txt") == "remote\n")
    }

    @Test func pullFollowsAConfiguredRebase() async throws {
        let fixture = try await makeDivergedClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("config", "pull.rebase", "true")

        _ = try await CLIGitProvider(gitURL: gitURL).pull(in: fixture.repo.url)

        let parents = try await fixture.repo.git("log", "-1", "--format=%P").stdoutString.split(separator: " ")
        #expect(parents.count == 1)
        #expect(try await fixture.repo.git("log", "-1", "--format=%s").stdoutString == "local work\n")
        #expect(try fixture.repo.read("remote.txt") == "remote\n")
    }

    /// A clone with a commit of its own while the remote got another one.
    private func makeDivergedClone() async throws -> RemoteRepoFixture {
        let remote = try await makeBareRemote()
        let other = try await makeClone(of: remote)
        try await other.repo.git("config", "user.email", "test@example.com")
        try await other.repo.git("config", "user.name", "Avi Test")
        try await other.repo.git("config", "commit.gpgsign", "false")
        try other.repo.write("remote.txt", "remote\n")
        try await other.repo.git("add", "remote.txt")
        try await other.repo.git("commit", "-q", "-m", "remote work")
        try await other.repo.git("push", "-q", "origin", "main")
        other.repo.removeDirectory()

        let fixture = try await makeClone(of: remote)
        try await fixture.repo.git("config", "user.email", "test@example.com")
        try await fixture.repo.git("config", "user.name", "Avi Test")
        try await fixture.repo.git("config", "commit.gpgsign", "false")
        try await fixture.repo.git("reset", "-q", "--hard", "HEAD~1")
        try fixture.repo.write("local.txt", "local\n")
        try await fixture.repo.git("add", "local.txt")
        try await fixture.repo.git("commit", "-q", "-m", "local work")
        return fixture
    }

    private func makeClone() async throws -> RemoteRepoFixture {
        try await makeClone(of: makeBareRemote())
    }

    private func makeClone(of remote: URL) async throws -> RemoteRepoFixture {
        let cloneURL = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-clone-\(UUID().uuidString)")
        try await git(["clone", "-q", remote.path, cloneURL.path], in: nil)
        // Keep the user's global hooks out of pushes made from the clone.
        try await git(["config", "--local", "core.hooksPath", "/dev/null"], in: cloneURL)
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
