@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Clone")
struct CloneTests {
    // MARK: URLs

    struct Rewrite: Sendable, CustomTestStringConvertible {
        let input: String
        let host: String
        let name: String
        let transport: CloneURL.Transport
        let https: String
        let ssh: String

        var testDescription: String {
            input
        }
    }

    @Test(arguments: [
        Rewrite(
            input: "https://github.com/mrcat71/avi.git", host: "github.com", name: "avi", transport: .https,
            https: "https://github.com/mrcat71/avi.git", ssh: "git@github.com:mrcat71/avi.git"
        ),
        Rewrite(
            input: "https://github.com/mrcat71/avi", host: "github.com", name: "avi", transport: .https,
            https: "https://github.com/mrcat71/avi", ssh: "git@github.com:mrcat71/avi.git"
        ),
        Rewrite(
            input: "  git@gitlab.com:group/sub/tool.git\n", host: "gitlab.com", name: "tool", transport: .ssh,
            https: "https://gitlab.com/group/sub/tool.git", ssh: "git@gitlab.com:group/sub/tool.git"
        ),
        Rewrite(
            input: "ssh://git@git.example.com:2222/team/app.git", host: "git.example.com", name: "app", transport: .ssh,
            https: "https://git.example.com/team/app.git", ssh: "ssh://git@git.example.com:2222/team/app.git"
        ),
        Rewrite(
            input: "https://me@git.example.com:8443/team/app.git", host: "git.example.com", name: "app", transport: .https,
            https: "https://me@git.example.com:8443/team/app.git", ssh: "git@git.example.com:team/app.git"
        )
    ])
    func remoteSwitchesBetweenHTTPSAndSSH(_ rewrite: Rewrite) throws {
        let url = try #require(CloneURL(rewrite.input))
        #expect(url.host == rewrite.host)
        #expect(url.repositoryName == rewrite.name)
        #expect(url.transport == rewrite.transport)
        #expect(url.string(for: .https) == rewrite.https)
        #expect(url.string(for: .ssh) == rewrite.ssh)
    }

    @Test func accountNameGoesInFrontOfTheHost() throws {
        let url = try #require(CloneURL("git@github.com:mrcat71/avi.git"))
        #expect(url.string(for: .https, user: "mrcat71") == "https://mrcat71@github.com/mrcat71/avi.git")
        #expect(url.string(for: .ssh, user: "mrcat71") == "git@github.com:mrcat71/avi.git")
    }

    /// Local paths, `git://`, absolute scp paths, and URLs with a password are
    /// cloned exactly as typed instead of being rewritten.
    @Test(arguments: [
        "", "   ", "/Users/me/src/app", "git://example.com/app.git", "file:///tmp/app.git",
        "git@host:/srv/app.git", "https://user:secret@github.com/a/b.git", "https://github.com", "two words:x"
    ])
    func formsAviDoesNotRewrite(_ input: String) {
        #expect(CloneURL(input) == nil)
    }

    // MARK: Accounts

    @Test func ghListsEveryAccountAndWhyABrokenOneFails() {
        let json = #"""
        {"hosts":{"github.com":[
          {"state":"success","active":true,"host":"github.com","login":"mrcat71","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"},
          {"state":"error","error":"HTTP 401: Bad credentials (https://api.github.com/)","active":false,"host":"github.com","login":"old-account","tokenSource":"default","gitProtocol":"https"}
        ]}}
        """#
        let accounts = CloneAccounts.ghAccounts(fromJSON: Data(json.utf8))
        #expect(accounts.map(\.login) == ["mrcat71", "old-account"])
        #expect(accounts[0].isUsable && accounts[0].canBrowse)
        #expect(accounts[0].title == "mrcat71")
        #expect(accounts[1].isUsable == false)
        #expect(accounts[1].problem?.contains("Bad credentials") == true)
        #expect(accounts[1].problem?.contains("gh auth login -h github.com") == true)
        #expect(CloneAccounts.ghAccounts(fromJSON: Data("unknown flag: --json".utf8)).isEmpty)
    }

    @Test func glabListsEachInstanceEvenWhenOneFails() {
        let status = """
        gitlab.com
          x gitlab.com: API call failed: GET https://gitlab.com/api/v4/user: 401 {message: 401 Unauthorized}
          \u{2713} Git operations for gitlab.com configured to use ssh protocol.
          ! No token found (checked config file, keyring, and environment variables).
        git.example.com
          \u{1B}[32m\u{2713}\u{1B}[0m Logged in to git.example.com as a.person (keyring)
          \u{2713} Git operations for git.example.com configured to use https protocol.
          \u{2713} Token found in operating system keyring: **************************

           ERROR

          X could not authenticate to one or more of the configured GitLab instances.
        """
        let accounts = CloneAccounts.glabAccounts(fromStatus: status)
        #expect(accounts.map(\.host) == ["gitlab.com", "git.example.com"])
        #expect(accounts[0].isUsable == false)
        #expect(accounts[0].problem?.contains("glab auth login --hostname gitlab.com") == true)
        #expect(accounts[0].gitProtocol == "ssh")
        #expect(accounts[1].login == "a.person")
        #expect(accounts[1].isUsable)
        #expect(accounts[1].title == "a.person on git.example.com")
        #expect(accounts[1].gitProtocol == "https")
    }

    @Test func tokenAccountsCloneByURLOnTheirInstance() {
        let saved = [
            ProviderAccount(id: "1", kind: "github", username: "mrcat71", keychainItem: "avi.account.1", status: "ok"),
            ProviderAccount(id: "2", kind: "gitlab", instanceURL: "https://git.example.com", username: "me", keychainItem: "avi.account.2", status: "invalid"),
            ProviderAccount(id: "3", kind: "bitbucket", username: "x", keychainItem: "avi.account.3")
        ]
        let accounts = CloneAccounts.tokenAccounts(saved)
        #expect(accounts.map(\.host) == ["github.com", "git.example.com"])
        #expect(accounts[0].isUsable && !accounts[0].canBrowse)
        #expect(accounts[1].isUsable == false)
        #expect(CloneAccounts.usable(accounts, on: "GitHub.com").map(\.login) == ["mrcat71"])
        #expect(CloneAccounts.usable(accounts, on: "git.example.com").isEmpty)
    }

    // MARK: Running git

    @Test func cliAccountReplacesGitsHelpersForTheClone() {
        let spec = CloneRunner.Spec(
            url: "https://mrcat71@github.com/mrcat71/avi.git",
            destination: URL(fileURLWithPath: "/tmp/avi"),
            credential: .cliHelper(executable: "/opt/home brew/bin/g'h")
        )
        let command = CloneRunner.gitCommand(for: spec)
        #expect(command.arguments == [
            "-c", "credential.helper=",
            "-c", #"credential.helper=!'/opt/home brew/bin/g'\''h' auth git-credential"#,
            "clone", "--progress", "--", "https://mrcat71@github.com/mrcat71/avi.git", "/tmp/avi"
        ])
        #expect(command.environment.isEmpty)
    }

    @Test func tokenTravelsInTheEnvironmentOnly() {
        let spec = CloneRunner.Spec(
            url: "https://me@git.example.com/team/app.git",
            destination: URL(fileURLWithPath: "/tmp/app"),
            credential: .token(username: "me", secret: "glpat-SECRET")
        )
        let command = CloneRunner.gitCommand(for: spec)
        #expect(!command.arguments.joined(separator: " ").contains("glpat-SECRET"))
        #expect(command.arguments.contains("credential.helper=" + CloneRunner.tokenHelper))
        #expect(command.environment == ["AVI_CLONE_USERNAME": "me", "AVI_CLONE_TOKEN": "glpat-SECRET"])
        #expect(!String(describing: spec.credential).contains("glpat-SECRET"))
    }

    @Test func sshAndSavedCredentialsLeaveGitAlone() {
        let spec = CloneRunner.Spec(url: "--upload-pack=touch /tmp/pwned", destination: URL(fileURLWithPath: "/tmp/x"))
        let command = CloneRunner.gitCommand(for: spec)
        #expect(command.arguments == ["clone", "--progress", "--", "--upload-pack=touch /tmp/pwned", "/tmp/x"])
    }

    @Test(arguments: [
        ("Host key verification failed.\nfatal: Could not read from remote repository.", "ssh -T git@gitlab.com"),
        ("git@gitlab.com: Permission denied (publickey).", "ssh-add"),
        ("fatal: could not read Username for 'https://gitlab.com': terminal prompts disabled", "Pick an account"),
        ("fatal: destination path exists", "")
    ])
    func failuresSuggestTheNextStep(message: String, expected: String) {
        let hint = cloneFailureHint(for: message, host: "gitlab.com")
        if expected.isEmpty {
            #expect(hint == nil)
        } else {
            #expect(hint?.contains(expected) == true)
        }
    }

    /// A real clone of a local repository: the runner passes the URL after
    /// `--`, and a CLI account's helper stays in the clone for its host.
    @Test func cloneKeepsTheAccountsHelperForItsHost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appendingPathComponent("origin.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let initBare = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "init", "--bare", "--quiet", origin.path]
        )
        #expect(initBare.exitCode == 0)

        let destination = root.appendingPathComponent("clone")
        let outcome = try await CloneRunner.clone(spec: CloneRunner.Spec(
            url: origin.path,
            destination: destination,
            credential: .cliHelper(executable: "/usr/bin/true"),
            host: "git.example.com"
        )) { _ in }
        #expect(outcome.success, "\(outcome.stderrTail)")
        #expect(outcome.warning == nil)

        let helpers = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "config", "--local", "--get-all", "credential.https://git.example.com.helper"],
            workingDirectory: destination
        )
        #expect(helpers.stdoutString == "\n!'/usr/bin/true' auth git-credential\n")
    }
}
