import Foundation

/// `GitProviding` implementation that shells out to the `git` CLI.
public struct CLIGitProvider: GitProviding {
    public let gitURL: URL

    public init(gitURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.gitURL = gitURL
    }

    public func repositoryRoot(for url: URL) async throws -> URL {
        let result = try await run(["rev-parse", "--show-toplevel"], in: url)
        let path = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public func status(in repository: URL) async throws -> WorkingCopyStatus {
        let result = try await run(["status", "--porcelain=v2", "--branch", "-z"], in: repository)
        return try StatusParser.parse(result.stdout)
    }

    public func diff(path: String, source: DiffSource, in repository: URL) async throws -> FileDiff {
        let arguments: [String]
        let allowedExitCodes: Set<Int32>
        switch source {
        case .unstaged:
            arguments = ["diff", "--no-color", "--no-ext-diff", "--", path]
            allowedExitCodes = [0]
        case .staged:
            arguments = ["diff", "--cached", "--no-color", "--no-ext-diff", "--", path]
            allowedExitCodes = [0]
        case .untracked:
            // --no-index renders the whole new file as additions and exits 1 when files differ.
            arguments = ["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "/dev/null", path]
            allowedExitCodes = [0, 1]
        }
        let result = try await run(arguments, in: repository, allowedExitCodes: allowedExitCodes)
        return DiffParser.parse(result.stdoutString)
    }

    public func history(in repository: URL, limit: Int, filter: HistoryFilter) async throws -> [CommitSummary] {
        let prettyFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%b%x00"
        var arguments: [String] = [
            "log",
            "--topo-order",
            "--date=iso-strict",
            "--pretty=format:\(prettyFormat)",
            "-n",
            String(limit)
        ]
        if filter.hideMerges {
            arguments.append("--no-merges")
        }
        switch filter.scope {
        case .currentBranch:
            break
        case .allBranches:
            arguments.append("--all")
        case .ref(let name):
            arguments.append(name)
        }

        let result = try await ProcessRunner.run(
            executable: gitURL,
            arguments: arguments,
            workingDirectory: repository,
            environment: gitEnvironment()
        )

        if result.exitCode != 0 {
            let stderr = result.stderrString
            if stderr.contains("does not have any commits yet")
                || stderr.contains("your current branch")
                || stderr.contains("unknown revision") {
                return []
            }
            throw GitError.commandFailed(
                command: (["git"] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                stderr: stderr
            )
        }

        return try LogParser.parse(result.stdout)
    }

    public func refs(in repository: URL) async throws -> RepositoryRefs {
        let format = "%(refname)%1f%(objectname)%1f%(upstream:short)%1f%(upstream:track)%1f%(HEAD)%1f%(subject)%1f%(taggerdate:iso-strict)%1f%(contents:subject)%00"
        let result = try await run([
            "for-each-ref",
            "--format=\(format)",
            "refs/heads",
            "refs/remotes",
            "refs/tags"
        ], in: repository)
        return try RefParser.parse(result.stdout)
    }

    public func remotes(in repository: URL) async throws -> [GitRemote] {
        let result = try await run(["remote", "-v"], in: repository)
        return RemoteParser.parse(result.stdoutString)
    }

    public func changedFiles(in commitOID: String, in repository: URL) async throws -> [CommitFileChange] {
        let result = try await run([
            "diff-tree",
            "--root",
            "--no-commit-id",
            "--name-status",
            "-r",
            "-z",
            "-M",
            "-C",
            commitOID
        ], in: repository)
        return try CommitFileChangeParser.parse(result.stdout)
    }

    public func diff(commitOID: String, path: String, in repository: URL) async throws -> FileDiff {
        let result = try await run([
            "show",
            "--format=",
            "--no-color",
            "--no-ext-diff",
            commitOID,
            "--",
            path
        ], in: repository)
        return DiffParser.parse(result.stdoutString)
    }

    public func checkout(_ ref: GitReference, in repository: URL) async throws {
        switch ref.kind {
        case .localBranch:
            try await run(["switch", "--", ref.name], in: repository)
        case .remoteBranch:
            try await run(["switch", "--track", ref.name], in: repository)
        case .tag:
            try await run(["switch", "--detach", ref.name], in: repository)
        }
    }

    public func createBranch(named name: String, startPoint: String?, checkout: Bool, in repository: URL) async throws {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            throw GitError.invalidInput("Branch name cannot be empty.")
        }
        try await run(["check-ref-format", "--branch", cleanedName], in: repository)

        var arguments = checkout ? ["switch", "-c", cleanedName] : ["branch", cleanedName]
        if let startPoint, !startPoint.isEmpty {
            arguments.append(startPoint)
        }
        try await run(arguments, in: repository)
    }

    public func renameBranch(from oldName: String, to newName: String, in repository: URL) async throws {
        let cleanedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedNew.isEmpty else {
            throw GitError.invalidInput("Branch name cannot be empty.")
        }
        try await run(["check-ref-format", "--branch", cleanedNew], in: repository)
        try await run(["branch", "-m", oldName, cleanedNew], in: repository)
    }

    public func setUpstream(branch: String, upstream: String, in repository: URL) async throws {
        try await run(["branch", "--set-upstream-to=\(upstream)", branch], in: repository)
    }

    public func unsetUpstream(branch: String, in repository: URL) async throws {
        try await run(["branch", "--unset-upstream", branch], in: repository)
    }

    public func deleteBranch(named name: String, in repository: URL) async throws {
        try await run(["branch", "-d", "--", name], in: repository)
    }

    public func fetch(remote: String?, in repository: URL) async throws -> GitRemoteOperationResult {
        let arguments: [String]
        if let remote, !remote.isEmpty {
            arguments = ["fetch", "--prune", "--progress", remote]
        } else {
            arguments = ["fetch", "--all", "--prune", "--progress"]
        }
        let result = try await run(arguments, in: repository)
        return remoteResult(result)
    }

    public func pull(in repository: URL) async throws -> GitRemoteOperationResult {
        try await pull(branch: nil, in: repository)
    }

    public func pull(branch: String?, in repository: URL) async throws -> GitRemoteOperationResult {
        let currentStatus = try await status(in: repository)
        let targetBranch = branch ?? currentStatus.branch.name

        if let targetBranch, targetBranch != currentStatus.branch.name {
            // Pull a non-current branch by fast-forwarding it from its upstream.
            let refs = try await refs(in: repository)
            guard let ref = refs.localBranches.first(where: { $0.name == targetBranch }) else {
                throw GitError.invalidInput("Branch '\(targetBranch)' not found.")
            }
            guard let upstream = ref.upstream else {
                throw GitError.invalidInput("Branch '\(targetBranch)' has no upstream configured.")
            }
            let parts = upstream.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else {
                throw GitError.invalidInput("Could not parse upstream '\(upstream)'.")
            }
            let remoteName = String(parts[0])
            let remoteBranch = String(parts[1])
            // git fetch <remote> <remote-branch>:<local-branch> performs a fast-forward into the local ref.
            let result = try await run(["fetch", remoteName, "\(remoteBranch):\(targetBranch)"], in: repository)
            return remoteResult(result)
        }

        let result = try await run(["pull", "--ff-only"], in: repository)
        return remoteResult(result)
    }

    public func push(in repository: URL) async throws -> GitRemoteOperationResult {
        try await push(branch: nil, in: repository)
    }

    public func push(branch: String?, in repository: URL) async throws -> GitRemoteOperationResult {
        let currentStatus = try await status(in: repository)

        if let branch, branch != currentStatus.branch.name {
            // Push a non-current branch using its configured upstream.
            let refs = try await refs(in: repository)
            guard let ref = refs.localBranches.first(where: { $0.name == branch }) else {
                throw GitError.invalidInput("Branch '\(branch)' not found.")
            }
            guard let upstream = ref.upstream else {
                throw GitError.invalidInput("Branch '\(branch)' has no upstream. Set upstream first.")
            }
            let parts = upstream.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else {
                throw GitError.invalidInput("Could not parse upstream '\(upstream)'.")
            }
            let remoteName = String(parts[0])
            let remoteBranch = String(parts[1])
            let result = try await run(["push", remoteName, "\(branch):\(remoteBranch)"], in: repository)
            return remoteResult(result)
        }

        // Push the current branch (legacy behavior with auto-upstream).
        guard let branchName = currentStatus.branch.name else {
            throw GitError.invalidInput("Cannot push from detached HEAD.")
        }

        let result: ProcessResult
        if currentStatus.branch.upstream == nil {
            let hasOrigin = try await remotes(in: repository).contains { $0.name == "origin" }
            guard hasOrigin else {
                throw GitError.invalidInput("No upstream configured and no origin remote found.")
            }
            result = try await run(["push", "-u", "origin", branchName], in: repository)
        } else {
            result = try await run(["push"], in: repository)
        }

        return remoteResult(result)
    }

    public func stage(path: String, in repository: URL) async throws {
        try await run(["add", "--", path], in: repository)
    }

    public func stageAll(in repository: URL) async throws {
        try await run(["add", "--all"], in: repository)
    }

    public func unstage(path: String, in repository: URL) async throws {
        try await run(["restore", "--staged", "--", path], in: repository)
    }

    public func unstageAll(in repository: URL) async throws {
        try await run(["restore", "--staged", "--", "."], in: repository)
    }

    public func discard(_ file: FileStatus, in repository: URL) async throws {
        if file.isUntracked {
            // Untracked files are unknown to git; discarding means deleting them.
            try FileManager.default.removeItem(at: repository.appendingPathComponent(file.path))
        } else {
            try await run(["restore", "--", file.path], in: repository)
        }
    }

    public func commit(message: String, in repository: URL) async throws {
        try await run(["commit", "-m", message], in: repository)
    }

    public func amend(message: String?, in repository: URL) async throws {
        if let message {
            try await run(["commit", "--amend", "-m", message], in: repository)
        } else {
            try await run(["commit", "--amend", "--no-edit"], in: repository)
        }
    }

    public func lastCommitMessage(in repository: URL) async throws -> String? {
        // Tolerates the unborn-branch case (no commits): git log exits non-zero.
        let result = try await ProcessRunner.run(
            executable: gitURL,
            arguments: ["log", "-1", "--pretty=%B"],
            workingDirectory: repository,
            environment: gitEnvironment()
        )
        guard result.exitCode == 0 else { return nil }
        let message = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    public func stagedDiff(in repository: URL) async throws -> String {
        let result = try await run(["diff", "--cached", "--no-color", "--no-ext-diff"], in: repository)
        return result.stdoutString
    }

    @discardableResult
    private func run(
        _ arguments: [String],
        in repository: URL,
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: gitURL,
            arguments: arguments,
            workingDirectory: repository,
            environment: gitEnvironment()
        )
        guard allowedExitCodes.contains(result.exitCode) else {
            throw GitError.commandFailed(
                command: (["git"] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result
    }

    private func gitEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Never block waiting on an interactive credential prompt; surface the failure instead.
        env["GIT_TERMINAL_PROMPT"] = "0"
        // Keep read-only commands like status from refreshing the index and triggering file watchers.
        env["GIT_OPTIONAL_LOCKS"] = "0"
        return env
    }

    private func remoteResult(_ result: ProcessResult) -> GitRemoteOperationResult {
        let output = [result.stdoutString, result.stderrString]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return GitRemoteOperationResult(output: output)
    }
}
