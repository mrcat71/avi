import Foundation
@testable import GitKit
import Testing

struct GitCommandOptionsTests {
    struct WordsCase: Sendable {
        let arguments: [String]
        let words: [String]
    }

    @Test(arguments: [
        WordsCase(arguments: ["status", "--porcelain=v2"], words: ["status", "--porcelain=v2"]),
        WordsCase(arguments: ["--literal-pathspecs", "add", "--", "a"], words: ["add", "--", "a"]),
        WordsCase(arguments: ["-c", "core.abbrev=40", "-c", "rebase.abbreviateCommands=false", "rebase", "-i"], words: ["rebase", "-i"]),
        WordsCase(arguments: ["-C", "/tmp/repo", "log"], words: ["log"]),
        WordsCase(arguments: ["-c"], words: []),
        WordsCase(arguments: [], words: [])
    ])
    func commandWordsSkipGlobalOptions(_ test: WordsCase) {
        #expect(Array(GitCommandOptions.commandWords(test.arguments)) == test.words)
    }

    struct IdentityCase: Sendable {
        let arguments: [String]
        let needsIdentity: Bool
    }

    @Test(arguments: [
        IdentityCase(arguments: ["commit", "-m", "x"], needsIdentity: true),
        IdentityCase(arguments: ["--literal-pathspecs", "commit", "--only", "-m", "x"], needsIdentity: true),
        IdentityCase(arguments: ["-c", "core.abbrev=40", "rebase", "-i"], needsIdentity: true),
        IdentityCase(arguments: ["merge", "--no-edit", "origin/main"], needsIdentity: true),
        IdentityCase(arguments: ["cherry-pick", "abc"], needsIdentity: true),
        IdentityCase(arguments: ["revert", "--no-edit", "abc"], needsIdentity: true),
        IdentityCase(arguments: ["pull"], needsIdentity: true),
        IdentityCase(arguments: ["stash"], needsIdentity: true),
        IdentityCase(arguments: ["stash", "push", "-m", "x"], needsIdentity: true),
        IdentityCase(arguments: ["stash", "list"], needsIdentity: false),
        IdentityCase(arguments: ["stash", "pop"], needsIdentity: false),
        IdentityCase(arguments: ["tag", "-a", "v1", "-m", "release"], needsIdentity: true),
        IdentityCase(arguments: ["tag", "v1"], needsIdentity: false),
        IdentityCase(arguments: ["tag", "-d", "--", "v1"], needsIdentity: false),
        IdentityCase(arguments: ["status"], needsIdentity: false),
        IdentityCase(arguments: ["config", "--get-regexp", "^user"], needsIdentity: false)
    ])
    func onlyCommandsThatWriteCommitsNeedAnIdentity(_ test: IdentityCase) {
        #expect(GitCommandOptions.needsIdentity(test.arguments) == test.needsIdentity, "\(test.arguments)")
    }

    struct FallbackCase: Sendable {
        let name: String
        let configured: String
        let fallbackName: String
        let fallbackEmail: String
        let expected: [String]
    }

    @Test(arguments: [
        FallbackCase(
            name: "Git has both, so nothing is added",
            configured: "user.name Andrey\nuser.email a@example.com\n",
            fallbackName: "Avi", fallbackEmail: "avi@example.com",
            expected: []
        ),
        FallbackCase(
            name: "Git has neither",
            configured: "",
            fallbackName: "Avi", fallbackEmail: "avi@example.com",
            expected: ["-c", "user.name=Avi", "-c", "user.email=avi@example.com"]
        ),
        FallbackCase(
            name: "Git has the name only",
            configured: "user.name Andrey\n",
            fallbackName: "Avi", fallbackEmail: "avi@example.com",
            expected: ["-c", "user.email=avi@example.com"]
        ),
        FallbackCase(
            name: "keys match in any case",
            configured: "User.Email a@example.com\n",
            fallbackName: "", fallbackEmail: "avi@example.com",
            expected: []
        ),
        FallbackCase(
            name: "an empty fallback adds nothing",
            configured: "",
            fallbackName: "Avi Svinarenko", fallbackEmail: "",
            expected: ["-c", "user.name=Avi Svinarenko"]
        )
    ])
    func fallbackFillsOnlyWhatGitLacks(_ test: FallbackCase) {
        let options = GitCommandOptions(fallbackName: test.fallbackName, fallbackEmail: test.fallbackEmail)
        #expect(options.fallbackIdentityArguments(configured: test.configured) == test.expected, "\(test.name)")
    }

    @Test func signingAddsGitsOwnSetting() {
        #expect(GitCommandOptions(signCommits: true).configArguments == ["-c", "commit.gpgSign=true"])
        #expect(GitCommandOptions().configArguments.isEmpty)
    }

    @Test func anExplicitGitWinsOverTheOptions() {
        let chosen = URL(fileURLWithPath: "/opt/homebrew/bin/git")
        #expect(CLIGitProvider(options: GitCommandOptions(executable: chosen)).gitURL == chosen)
        #expect(CLIGitProvider(gitURL: GitCommandOptions.defaultExecutable, options: GitCommandOptions(executable: chosen)).gitURL
            == GitCommandOptions.defaultExecutable)
        #expect(CLIGitProvider(options: GitCommandOptions()).gitURL == GitCommandOptions.defaultExecutable)
    }
}

/// The options against real repositories, with the machine's global and
/// system Git config hidden so only the repository's own counts.
struct GitCommandOptionsIntegrationTests {
    private static let isolated = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]

    private func provider(_ options: GitCommandOptions) -> CLIGitProvider {
        var provider = CLIGitProvider(gitURL: GitCommandOptions.defaultExecutable, options: options)
        provider.environmentOverrides = Self.isolated
        return provider
    }

    private func author(_ fixture: GitFixture) async throws -> String {
        try await fixture.git("log", "-1", "--format=%an <%ae>").stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func aRepositorysOwnIdentityWinsOverTheFallback() async throws {
        try await withTempRepo { fixture in
            try fixture.write("a.txt", "one\n")
            try await fixture.git("add", "a.txt")
            try await provider(GitCommandOptions(fallbackName: "Fallback", fallbackEmail: "fallback@example.com"))
                .commit(message: "first", in: fixture.url)
            #expect(try await author(fixture) == "Avi Test <test@example.com>")
        }
    }

    @Test func theFallbackSignsCommitsWhereGitHasNoIdentity() async throws {
        try await withTempRepo { fixture in
            try await fixture.git("config", "--unset", "user.name")
            try await fixture.git("config", "--unset", "user.email")
            try fixture.write("a.txt", "one\n")
            try await fixture.git("add", "a.txt")
            try await provider(GitCommandOptions(fallbackName: "Fallback", fallbackEmail: "fallback@example.com"))
                .commit(message: "first", in: fixture.url)
            #expect(try await author(fixture) == "Fallback <fallback@example.com>")
        }
    }

    @Test func theFallbackFillsInOnlyTheMissingEmail() async throws {
        try await withTempRepo { fixture in
            try await fixture.git("config", "--unset", "user.email")
            try fixture.write("a.txt", "one\n")
            try await fixture.git("add", "a.txt")
            try await provider(GitCommandOptions(fallbackName: "Fallback", fallbackEmail: "fallback@example.com"))
                .commit(message: "first", in: fixture.url)
            #expect(try await author(fixture) == "Avi Test <fallback@example.com>")
        }
    }

    @Test func signingSignsCommitsTheRepositoryWouldNot() async throws {
        try await withTempRepo { fixture in
            // A stand-in for gpg that answers the way Git expects.
            let signer = fixture.url.appendingPathComponent(".fake-gpg")
            try """
            #!/bin/sh
            cat >/dev/null
            echo '[GNUPG:] SIG_CREATED ' >&2
            printf '%s\\n' '-----BEGIN PGP SIGNATURE-----' 'fake' '-----END PGP SIGNATURE-----'
            """.write(to: signer, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: signer.path)
            try await fixture.git("config", "gpg.program", signer.path)
            try await fixture.git("config", "user.signingkey", "fake")

            try fixture.write("a.txt", "one\n")
            try await fixture.git("add", "a.txt")
            try await provider(GitCommandOptions()).commit(message: "unsigned", in: fixture.url)
            #expect(try await !fixture.git("cat-file", "commit", "HEAD").stdoutString.contains("gpgsig"))

            try fixture.write("a.txt", "two\n")
            try await fixture.git("add", "a.txt")
            try await provider(GitCommandOptions(signCommits: true)).commit(message: "signed", in: fixture.url)
            #expect(try await fixture.git("cat-file", "commit", "HEAD").stdoutString.contains("gpgsig"))
        }
    }

    @Test func pruningFollowsTheSetting() async throws {
        let remote = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-prune-remote-\(UUID().uuidString).git")
        let clone = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-prune-clone-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: remote)
            try? FileManager.default.removeItem(at: clone)
        }
        try await withTempRepo { seed in
            try seed.write("a.txt", "one\n")
            try await seed.git("add", "a.txt")
            try await seed.git("commit", "-q", "-m", "initial")
            try await seed.git("branch", "-M", "main")
            try await seed.git("branch", "feature")
            try await seed.git("clone", "-q", "--bare", seed.url.path, remote.path)
        }
        try await GitFixture(url: URL(fileURLWithPath: "/tmp")).git("clone", "-q", remote.path, clone.path)
        let repo = GitFixture(url: clone)
        try await GitFixture(url: remote).git("branch", "-D", "feature")

        _ = try await provider(GitCommandOptions(pruneOnFetch: false)).fetch(remote: "origin", in: clone)
        #expect(try await repo.gitConfigured("remote.origin.url"))
        #expect(try await repo.git("branch", "-r").stdoutString.contains("origin/feature"))

        _ = try await provider(GitCommandOptions(pruneOnFetch: true)).fetch(remote: "origin", in: clone)
        #expect(try await !repo.git("branch", "-r").stdoutString.contains("origin/feature"))
    }
}
