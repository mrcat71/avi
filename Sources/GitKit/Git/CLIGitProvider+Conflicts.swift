import Foundation

/// How a pull joins a branch and an upstream that both have new commits.
public enum PullReconcile: String, Sendable, CaseIterable {
    /// Replays the branch's own commits on top of the upstream.
    case rebase
    /// Joins the two with a merge commit.
    case merge
}

/// A side of a conflict. `current` is HEAD, Git's "ours"; `incoming` is the
/// change being applied, Git's "theirs". In a rebase HEAD is the branch being
/// rebased onto, so incoming is your own commit being replayed.
public enum ConflictSide: String, Sendable {
    case current
    case incoming
}

/// The tool `git mergetool` runs: one Git knows by name, or a command of
/// ours registered under a name for this one run.
public struct MergeToolLaunch: Sendable, Equatable {
    /// `--tool=<name>`.
    public let name: String
    /// The executable of a tool Git knows (`mergetool.<name>.path`); nil
    /// lets Git look for it.
    public let path: String?
    /// A shell command for a tool Git does not know, using `$BASE`,
    /// `$LOCAL`, `$REMOTE`, and `$MERGED`.
    public let command: String?
    /// Whether the command's exit status says if the merge succeeded; if not,
    /// Git checks whether the file changed.
    public let trustExitCode: Bool

    public init(name: String, path: String? = nil, command: String? = nil, trustExitCode: Bool = false) {
        self.name = name
        self.path = path
        self.command = command
        self.trustExitCode = trustExitCode
    }
}

/// How a merge tool run ended.
public enum MergeToolOutcome: Sendable, Equatable {
    /// The tool merged the file and Git staged it.
    case resolved
    /// The tool closed without a merge; the file is still conflicted.
    case unresolved
}

public extension CLIGitProvider {
    // MARK: - Diverged pull

    func pullReconcileIsConfigured(branch: String?, in repository: URL) async throws -> Bool {
        let rebaseKeys = ["pull.rebase"] + [branch.map { "branch.\($0).rebase" }].compactMap(\.self)
        for key in rebaseKeys where try await execute(["config", "--get", key], in: repository).exitCode == 0 {
            return true
        }
        // pull.ff=only refuses a diverged branch, so it decides nothing here.
        let fastForward = try await execute(["config", "--get", "pull.ff"], in: repository)
        guard fastForward.exitCode == 0 else { return false }
        return fastForward.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "only"
    }

    func reconcileWithUpstream(_ how: PullReconcile, in repository: URL) async throws -> IntegrationOutcome {
        let upstream = try await execute(["rev-parse", "--symbolic-full-name", "@{upstream}"], in: repository)
            .stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard upstream.hasPrefix("refs/") else {
            throw GitError.invalidInput("The current branch has no upstream branch.")
        }
        switch how {
        case .rebase:
            let arguments = ["rebase", upstream]
            let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
            return try await integrationOutcome(arguments, result, in: repository)
        case .merge:
            // --ff overrides a merge.ff=only: you asked for the merge commit.
            let arguments = ["merge", "--no-edit", "--ff", upstream]
            let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
            return try await integrationOutcome(arguments, result, in: repository)
        }
    }

    // MARK: - Conflicts

    func resolveConflicts(paths: [String], taking side: ConflictSide, in repository: URL) async throws {
        for path in paths {
            // Stage 2 is HEAD's version, stage 3 the incoming one. A side
            // without a stage deleted the file, so taking it deletes it.
            let stages = try await run(["--literal-pathspecs", "ls-files", "--unmerged", "-z", "--", path], in: repository)
            let wanted = side == .current ? "2" : "3"
            let hasVersion = stages.stdoutString.split(separator: "\0").contains { entry in
                entry.split(separator: "\t").first?.split(separator: " ").last.map(String.init) == wanted
            }
            if hasVersion {
                try await run(["--literal-pathspecs", "checkout", side == .current ? "--ours" : "--theirs", "--", path], in: repository)
                try await run(["--literal-pathspecs", "add", "--", path], in: repository)
            } else {
                try await run(["--literal-pathspecs", "rm", "--quiet", "--force", "--", path], in: repository)
            }
        }
    }

    func markResolved(paths: [String], in repository: URL) async throws {
        guard !paths.isEmpty else { return }
        // --all also stages a conflicted file you deleted as its resolution.
        for chunk in paths.chunked(into: 256) {
            try await run(["--literal-pathspecs", "add", "--all", "--"] + chunk, in: repository)
        }
    }

    func launchMergeTool(path: String, tool: MergeToolLaunch?, in repository: URL) async throws -> MergeToolOutcome {
        // Git's base, local, and remote copies go to a temporary folder, and
        // no .orig backups are left next to the file.
        var arguments = ["--literal-pathspecs", "-c", "mergetool.keepBackup=false", "-c", "mergetool.writeToTemp=true"]
        if let tool {
            if let command = tool.command {
                arguments += ["-c", "mergetool.\(tool.name).cmd=\(command)", "-c", "mergetool.\(tool.name).trustExitCode=\(tool.trustExitCode)"]
            } else if let toolPath = tool.path {
                arguments += ["-c", "mergetool.\(tool.name).path=\(toolPath)"]
            }
        }
        arguments += ["mergetool", "--no-prompt"]
        if let tool {
            arguments.append("--tool=\(tool.name)")
        }
        arguments += ["--", path]
        // Not through the command queue: the tool stays open until you close
        // it, and Avi's other Git commands must not wait for that.
        let result = try await Self.launch(gitURL, arguments: arguments, in: repository, environment: nonInteractiveEnvironment())
        if result.exitCode == 0 {
            return .resolved
        }
        // Closing the tool without merging ends with Git's "merge of <path>
        // failed" alone. Anything else, such as an unknown tool or a command
        // that is not there, is a problem to show.
        let lines = result.stderrString.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let gaveUp = lines.contains { $0.hasPrefix("merge of ") && $0.hasSuffix(" failed") }
        if gaveUp, lines.allSatisfy({ $0.hasPrefix("merge of ") }) {
            return .unresolved
        }
        throw failure(arguments, result)
    }
}

extension CLIGitProvider {
    /// A merge or rebase that stopped waits for you; anything else failed.
    func integrationOutcome(_ arguments: [String], _ result: ProcessResult, in repository: URL) async throws -> IntegrationOutcome {
        if result.exitCode == 0 {
            return .completed
        }
        let state = try await operationState(in: repository)
        let unmerged = try await run(["ls-files", "--unmerged"], in: repository)
        if state != nil || !unmerged.stdout.isEmpty {
            return .stopped(combinedOutput(result))
        }
        throw failure(arguments, result)
    }
}
