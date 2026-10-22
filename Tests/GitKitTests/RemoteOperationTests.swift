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

    struct NewBranch: Sendable, CustomTestStringConvertible {
        let name: String
        let startPoint: String?
        let checkout: Bool
        var repositorySetting: String?
        let upstream: String?

        var testDescription: String {
            "\(name) from \(startPoint ?? "HEAD")\(checkout ? "" : " without checkout")"
                + (repositorySetting.map { " with branch.autoSetupMerge=\($0)" } ?? "")
        }
    }

    /// A branch started from origin/main under another name must not track
    /// main, or it shows, pulls from, and pushes toward main until published.
    /// Taking the remote branch's own name tracks it, as checking it out does.
    @Test(arguments: [
        NewBranch(name: "feature", startPoint: "origin/main", checkout: true, upstream: nil),
        NewBranch(name: "feature", startPoint: "origin/main", checkout: false, upstream: nil),
        NewBranch(name: "feature", startPoint: nil, checkout: true, repositorySetting: "inherit", upstream: nil),
        NewBranch(name: "feature", startPoint: "main", checkout: false, repositorySetting: "always", upstream: nil),
        NewBranch(name: "topic", startPoint: "origin/topic", checkout: true, upstream: "origin/topic")
    ])
    func createBranchTracksOnlyARemoteBranchOfTheSameName(_ newBranch: NewBranch) async throws {
        let remote = try await makeBareRemote()
        try await git(["--git-dir", remote.path, "branch", "topic", "main"], in: nil)
        let fixture = try await makeClone(of: remote)
        defer { fixture.removeAll() }
        if let setting = newBranch.repositorySetting {
            try await fixture.repo.git("config", "branch.autoSetupMerge", setting)
        }
        let provider = CLIGitProvider(gitURL: gitURL)

        try await provider.createBranch(named: newBranch.name, startPoint: newBranch.startPoint, checkout: newBranch.checkout, in: fixture.repo.url)

        let created = try await provider.refs(in: fixture.repo.url).localBranches.first { $0.name == newBranch.name }
        #expect(created != nil)
        #expect(created?.upstream == newBranch.upstream)
    }

    /// `git switch -c feature origin/main` leaves feature tracking main. Its
    /// first push from the Push sheet creates origin/feature and tracks that,
    /// as the sheet says, and leaves main on the remote alone.
    @Test func pushingABranchThatTracksAnotherNameTracksThePushedBranch() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("config", "user.email", "test@example.com")
        try await fixture.repo.git("config", "user.name", "Avi Test")
        try await fixture.repo.git("config", "commit.gpgsign", "false")
        try await fixture.repo.git("switch", "-q", "--track", "-c", "feature", "origin/main")
        try fixture.repo.write("feature.txt", "feature\n")
        try await fixture.repo.git("add", "feature.txt")
        try await fixture.repo.git("commit", "-q", "-m", "feature work")
        let remoteMain = try await git(["--git-dir", fixture.remoteURL.path, "rev-parse", "main"], in: nil).stdoutString
        let provider = CLIGitProvider(gitURL: gitURL)

        _ = try await provider.push(branch: nil, remote: nil, force: false, pushTags: false, in: fixture.repo.url)

        let feature = try await provider.refs(in: fixture.repo.url).localBranches.first { $0.name == "feature" }
        #expect(feature?.upstream == "origin/feature")
        #expect(try await provider.status(in: fixture.repo.url).branch.upstream == "origin/feature")
        let remoteHeads = try await git(["--git-dir", fixture.remoteURL.path, "for-each-ref", "--format=%(refname)", "refs/heads"], in: nil)
            .stdoutString.split(separator: "\n").map(String.init)
        #expect(remoteHeads.sorted() == ["refs/heads/feature", "refs/heads/main"])
        #expect(try await git(["--git-dir", fixture.remoteURL.path, "rev-parse", "main"], in: nil).stdoutString == remoteMain)
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

    struct PullConfig: Sendable, CustomTestStringConvertible {
        let settings: [(String, String)]
        let decides: Bool

        var testDescription: String {
            settings.isEmpty ? "nothing set" : settings.map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
        }
    }

    /// Whether Avi has to ask how to join a diverged branch. A global
    /// pull.* setting would decide instead, so the local one is set either way.
    @Test(arguments: [
        PullConfig(settings: [("pull.ff", "only")], decides: false),
        PullConfig(settings: [("pull.ff", "false")], decides: true),
        PullConfig(settings: [("pull.ff", "only"), ("pull.rebase", "true")], decides: true),
        PullConfig(settings: [("pull.ff", "only"), ("branch.main.rebase", "false")], decides: true)
    ])
    func pullReconcileFollowsGitConfig(_ config: PullConfig) async throws {
        let fixture = try await makeDivergedClone()
        defer { fixture.removeAll() }
        for (key, value) in config.settings {
            try await fixture.repo.git("config", key, value)
        }

        let decides = try await CLIGitProvider(gitURL: gitURL).pullReconcileIsConfigured(branch: "main", in: fixture.repo.url)

        #expect(decides == config.decides)
    }

    /// The ansible repository's case: pull.ff=only refuses the pull, and
    /// choosing Rebase replays the local commit on top of the remote one.
    @Test func reconcileRebasesTheLocalCommitsOntoTheUpstream() async throws {
        let fixture = try await makeDivergedClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("config", "pull.ff", "only")
        let provider = CLIGitProvider(gitURL: gitURL)
        _ = try await provider.fetch(remote: nil, in: fixture.repo.url)

        let outcome = try await provider.reconcileWithUpstream(.rebase, in: fixture.repo.url)

        #expect(outcome == .completed)
        let log = try await fixture.repo.git("log", "--format=%s %P", "-2").stdoutString.split(separator: "\n")
        #expect(log.count == 2)
        #expect(log[0].hasPrefix("local work "))
        #expect(log[0].split(separator: " ").count == 3)
        #expect(log[1].hasPrefix("remote work "))
        let status = try await provider.status(in: fixture.repo.url)
        #expect(status.branch.ahead == 1)
        #expect(status.branch.behind == 0)
    }

    @Test func reconcileMergesTheUpstreamEvenWhenMergesMustFastForward() async throws {
        let fixture = try await makeDivergedClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("config", "pull.ff", "only")
        try await fixture.repo.git("config", "merge.ff", "only")
        let provider = CLIGitProvider(gitURL: gitURL)
        _ = try await provider.fetch(remote: nil, in: fixture.repo.url)

        let outcome = try await provider.reconcileWithUpstream(.merge, in: fixture.repo.url)

        #expect(outcome == .completed)
        let parents = try await fixture.repo.git("log", "-1", "--format=%P").stdoutString.split(separator: " ")
        #expect(parents.count == 2)
        #expect(try fixture.repo.read("remote.txt") == "remote\n")
        #expect(try fixture.repo.read("local.txt") == "local\n")
    }

    @Test func reconcileStopsOnAConflictInsteadOfFailing() async throws {
        let fixture = try await makeDivergedClone(conflicting: true)
        defer { fixture.removeAll() }
        let provider = CLIGitProvider(gitURL: gitURL)
        _ = try await provider.fetch(remote: nil, in: fixture.repo.url)

        let outcome = try await provider.reconcileWithUpstream(.rebase, in: fixture.repo.url)

        guard case .stopped = outcome else {
            Issue.record("Expected the rebase to stop on the conflict, got \(outcome)")
            return
        }
        #expect(try await provider.status(in: fixture.repo.url).entries.contains { $0.isConflicted && $0.path == "a.txt" })
    }

    /// The release case: a commit and its tag reach the remote in one push.
    @Test func pushSendsTheBranchAndItsTagsTogether() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await commitLocally(fixture.repo, file: "release.txt", message: "chore(release): prepare 1.0")
        try await fixture.repo.git("tag", "-a", "-m", "1.0", "v1.0")
        try await fixture.repo.git("tag", "local-label", "HEAD~1")
        let provider = CLIGitProvider(gitURL: gitURL)

        // Only tags on commits the remote lacks; local-label is on one it has.
        #expect(try await provider.unpushedTags(branch: "main", remote: "origin", in: fixture.repo.url) == [UnpushedTag(name: "v1.0", isAnnotated: true)])
        _ = try await provider.push(branch: nil, remote: nil, force: false, pushTags: false, tags: ["v1.0"], in: fixture.repo.url)

        let head = try await fixture.repo.git("rev-parse", "HEAD").stdoutString
        #expect(try await git(["--git-dir", fixture.remoteURL.path, "rev-parse", "main"], in: nil).stdoutString == head)
        #expect(try await git(["--git-dir", fixture.remoteURL.path, "rev-parse", "v1.0^{commit}"], in: nil).stdoutString == head)
        #expect(try await remoteTags(fixture) == ["v1.0"])
        #expect(try await provider.unpushedTags(branch: "main", remote: "origin", in: fixture.repo.url).isEmpty)
    }

    /// Git refuses the branch on the client: its tag must not land alone.
    @Test func aBranchThatCannotFastForwardKeepsItsTagsBack() async throws {
        let fixture = try await makeDivergedClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("tag", "v1.0")

        await #expect(throws: GitError.self) {
            _ = try await CLIGitProvider(gitURL: gitURL).push(branch: nil, remote: nil, force: false, pushTags: false, tags: ["v1.0"], in: fixture.repo.url)
        }
        #expect(try await remoteTags(fixture).isEmpty)
    }

    /// The server refuses the branch, as a protected branch does: the tag
    /// goes nowhere either, where a plain push would have published it.
    @Test func aBranchTheServerRefusesKeepsItsTagsBack() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try installUpdateHook(in: fixture.remoteURL, refusing: "refs/heads/main")
        try await git(["--git-dir", fixture.remoteURL.path, "config", "core.hooksPath", fixture.remoteURL.appendingPathComponent("hooks").path], in: nil)
        try await commitLocally(fixture.repo, file: "release.txt", message: "release")
        try await fixture.repo.git("tag", "v1.0")

        await #expect(throws: GitError.self) {
            _ = try await CLIGitProvider(gitURL: gitURL).push(branch: nil, remote: nil, force: false, pushTags: false, tags: ["v1.0"], in: fixture.repo.url)
        }
        #expect(try await remoteTags(fixture).isEmpty)
    }

    /// A server without atomic pushes gets the branch first and the tag after it.
    @Test func aServerWithoutAtomicPushesGetsTheBranchBeforeTheTag() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await git(["--git-dir", fixture.remoteURL.path, "config", "receive.advertiseAtomic", "false"], in: nil)
        try await commitLocally(fixture.repo, file: "release.txt", message: "release")
        try await fixture.repo.git("tag", "v1.0")

        let result = try await CLIGitProvider(gitURL: gitURL).push(branch: nil, remote: nil, force: false, pushTags: false, tags: ["v1.0"], in: fixture.repo.url)

        let head = try await fixture.repo.git("rev-parse", "HEAD").stdoutString
        #expect(try await git(["--git-dir", fixture.remoteURL.path, "rev-parse", "main"], in: nil).stdoutString == head)
        #expect(try await remoteTags(fixture) == ["v1.0"])
        // Two pushes, one per "To <remote>" line: the branch, then the tag.
        #expect(result.output.split(separator: "\n").filter { $0.hasPrefix("To ") }.count == 2)
    }

    /// Push all tags sends the other tags once the branch and its own are in.
    @Test func pushAllTagsSendsTheOtherTagsAfterTheBranch() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("tag", "old-label")
        try await commitLocally(fixture.repo, file: "release.txt", message: "release")
        try await fixture.repo.git("tag", "v1.0")

        _ = try await CLIGitProvider(gitURL: gitURL).push(branch: nil, remote: nil, force: false, pushTags: true, tags: ["v1.0"], in: fixture.repo.url)

        #expect(try await remoteTags(fixture) == ["old-label", "v1.0"])
    }

    @Test func remoteHasCommitKnowsWhatWasPushed() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        let provider = CLIGitProvider(gitURL: gitURL)
        let pushed = try await fixture.repo.git("rev-parse", "HEAD").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        try await commitLocally(fixture.repo, file: "local.txt", message: "local")
        let local = try await fixture.repo.git("rev-parse", "HEAD").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(try await provider.remoteHasCommit(pushed, remote: "origin", in: fixture.repo.url))
        #expect(try await !provider.remoteHasCommit(local, remote: "origin", in: fixture.repo.url))
        #expect(try await !provider.remoteHasCommit(pushed, remote: "upstream", in: fixture.repo.url))
    }

    @Test func resolveCommitNamesOnlyCommits() async throws {
        let fixture = try await makeClone()
        defer { fixture.removeAll() }
        try await fixture.repo.git("tag", "-a", "-m", "annotated", "v1.0")
        let provider = CLIGitProvider(gitURL: gitURL)
        let head = try await fixture.repo.git("rev-parse", "HEAD").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(try await provider.resolveCommit("HEAD", in: fixture.repo.url) == head)
        #expect(try await provider.resolveCommit("v1.0", in: fixture.repo.url) == head)
        #expect(try await provider.resolveCommit(String(head.prefix(8)), in: fixture.repo.url) == head)
        #expect(try await provider.resolveCommit("--all", in: fixture.repo.url) == nil)
        #expect(try await provider.resolveCommit("no-such-thing", in: fixture.repo.url) == nil)
    }

    private func commitLocally(_ repo: GitFixture, file: String, message: String) async throws {
        try await repo.git("config", "user.email", "test@example.com")
        try await repo.git("config", "user.name", "Avi Test")
        try await repo.git("config", "commit.gpgsign", "false")
        try repo.write(file, message + "\n")
        try await repo.git("add", file)
        try await repo.git("commit", "-q", "-m", message)
    }

    private func remoteTags(_ fixture: RemoteRepoFixture) async throws -> [String] {
        try await git(["--git-dir", fixture.remoteURL.path, "tag", "-l"], in: nil)
            .stdoutString.split(separator: "\n").map(String.init).sorted()
    }

    /// An `update` hook decides per ref, the way branch protection does.
    private func installUpdateHook(in remote: URL, refusing ref: String) throws {
        let hooks = remote.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("update")
        try "#!/bin/sh\nif [ \"$1\" = \"\(ref)\" ]; then echo 'protected' >&2; exit 1; fi\nexit 0\n"
            .write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    }

    /// A clone with a commit of its own while the remote got another one.
    /// With `conflicting`, both commits change the same line of a.txt.
    private func makeDivergedClone(conflicting: Bool = false) async throws -> RemoteRepoFixture {
        let remote = try await makeBareRemote()
        let other = try await makeClone(of: remote)
        try await other.repo.git("config", "user.email", "test@example.com")
        try await other.repo.git("config", "user.name", "Avi Test")
        try await other.repo.git("config", "commit.gpgsign", "false")
        try other.repo.write("remote.txt", "remote\n")
        if conflicting {
            try other.repo.write("a.txt", "remote line\n")
        }
        try await other.repo.git("add", ".")
        try await other.repo.git("commit", "-q", "-m", "remote work")
        try await other.repo.git("push", "-q", "origin", "main")
        other.repo.removeDirectory()

        let fixture = try await makeClone(of: remote)
        try await fixture.repo.git("config", "user.email", "test@example.com")
        try await fixture.repo.git("config", "user.name", "Avi Test")
        try await fixture.repo.git("config", "commit.gpgsign", "false")
        try await fixture.repo.git("reset", "-q", "--hard", "HEAD~1")
        try fixture.repo.write("local.txt", "local\n")
        if conflicting {
            try fixture.repo.write("a.txt", "local line\n")
        }
        try await fixture.repo.git("add", ".")
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
