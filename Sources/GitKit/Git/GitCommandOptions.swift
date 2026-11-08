import Foundation
import os

/// What Settings asks of every git command Avi runs: which git, the name and
/// email for repositories where Git has none, whether commits are signed,
/// whether fetches prune, and whether each command goes to the system log.
public struct GitCommandOptions: Sendable, Equatable {
    public static let defaultExecutable = URL(fileURLWithPath: "/usr/bin/git")

    /// The git to run; nil runs `/usr/bin/git`.
    public var executable: URL?
    /// Used only where Git has no `user.name` or `user.email` for the
    /// repository, so a repository's own identity and `includeIf` ones win.
    public var fallbackName: String
    public var fallbackEmail: String
    /// Sign every commit, as Git's `commit.gpgSign` does.
    public var signCommits: Bool
    /// Fetches remove remote-tracking branches whose branch is gone.
    public var pruneOnFetch: Bool
    /// Log every command with its time and exit status.
    public var logCommands: Bool

    public init(
        executable: URL? = nil,
        fallbackName: String = "",
        fallbackEmail: String = "",
        signCommits: Bool = false,
        pruneOnFetch: Bool = true,
        logCommands: Bool = false
    ) {
        self.executable = executable
        self.fallbackName = fallbackName
        self.fallbackEmail = fallbackEmail
        self.signCommits = signCommits
        self.pruneOnFetch = pruneOnFetch
        self.logCommands = logCommands
    }

    /// The options of every `CLIGitProvider` made without its own. Avi sets
    /// them from Settings at launch and whenever they change; tests leave
    /// them alone.
    public static var current: GitCommandOptions {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    private static let storage = OSAllocatedUnfairLock(initialState: GitCommandOptions())

    var hasFallbackIdentity: Bool {
        !fallbackName.isEmpty || !fallbackEmail.isEmpty
    }

    /// `-c` pairs that go before every command.
    var configArguments: [String] {
        signCommits ? ["-c", "commit.gpgSign=true"] : []
    }

    /// `-c` pairs for the fallback name and email the repository's config
    /// lacks. `configured` is what `git config --get-regexp` printed.
    func fallbackIdentityArguments(configured output: String) -> [String] {
        let keys = Set(output.split(separator: "\n").compactMap { line in
            line.split(separator: " ", maxSplits: 1).first.map { $0.lowercased() }
        })
        var arguments: [String] = []
        if !fallbackName.isEmpty, !keys.contains("user.name") {
            arguments += ["-c", "user.name=\(fallbackName)"]
        }
        if !fallbackEmail.isEmpty, !keys.contains("user.email") {
            arguments += ["-c", "user.email=\(fallbackEmail)"]
        }
        return arguments
    }

    /// The words from the subcommand on, past global options such as
    /// `--literal-pathspecs` and `-c key=value`.
    static func commandWords(_ arguments: [String]) -> ArraySlice<String> {
        var index = arguments.startIndex
        while index < arguments.endIndex, arguments[index].hasPrefix("-") {
            index += ["-c", "-C"].contains(arguments[index]) ? 2 : 1
        }
        return arguments[min(index, arguments.endIndex)...]
    }

    /// Whether the command can write a commit or an annotated tag, which
    /// needs a name and email.
    static func needsIdentity(_ arguments: [String]) -> Bool {
        let words = commandWords(arguments)
        guard let command = words.first else { return false }
        switch command {
        case "commit", "merge", "pull", "rebase", "cherry-pick", "revert", "am":
            return true
        case "stash":
            let action = words.dropFirst().first
            return action == nil || action == "push" || action == "save"
        case "tag":
            return words.contains { ["-a", "--annotate", "-m", "-F", "-s", "--sign"].contains($0) || $0.hasPrefix("--message") }
        default:
            return false
        }
    }
}
