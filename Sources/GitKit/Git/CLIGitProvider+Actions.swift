import Foundation

/// Branch and file actions offered by the sidebar and Changes context menus.
public extension CLIGitProvider {
    // MARK: - Checkout

    func checkout(_ ref: GitReference, carryingLocalChanges: Bool, in repository: URL) async throws -> CheckoutOutcome {
        guard carryingLocalChanges else {
            try await checkout(ref, in: repository)
            return .switched
        }
        // Stash, switch, and apply as one unit, so no other Avi command can
        // push a stash in between and get applied in place of ours.
        return try await GitCommandQueue.shared.run(repository: repository) {
            var scoped = self
            scoped.ownsCommandSlot = true
            return try await scoped.checkoutCarryingChanges(ref, in: repository)
        }
    }

    func addWorktree(at path: URL, branch: String, in repository: URL) async throws {
        guard try await refs(in: repository).localBranches.contains(where: { $0.name == branch }) else {
            throw GitError.invalidInput("'\(branch)' is not a local branch.")
        }
        try await run(["worktree", "add", path.path, branch], in: repository)
    }

    // MARK: - Fast-forward, merge, rebase

    func fastForward(branch: String, in repository: URL) async throws {
        let upstream = try await run(["rev-parse", "--symbolic-full-name", "\(branch)@{upstream}"], in: repository)
            .stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard upstream.hasPrefix("refs/") else {
            throw GitError.invalidInput("'\(branch)' has no upstream to fast-forward to.")
        }
        let head = try await execute(["symbolic-ref", "--quiet", "HEAD"], in: repository)
        if head.exitCode == 0, head.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "refs/heads/\(branch)" {
            try await run(["merge", "--ff-only", upstream], in: repository, environment: nonInteractiveEnvironment())
        } else {
            // Moves the branch without checking it out, from the remote-tracking
            // ref already fetched. Git refuses anything but a fast-forward, and a
            // branch another worktree has checked out. No FETCH_HEAD, so the
            // "fetched" time keeps meaning a real fetch.
            try await run(["fetch", "--no-write-fetch-head", "--no-tags", ".", "\(upstream):refs/heads/\(branch)"], in: repository)
        }
    }

    func merge(branch: String, mode: MergeMode, in repository: URL) async throws -> IntegrationOutcome {
        var arguments = ["merge", "--no-edit"]
        if let flag = mode.argument {
            arguments.append(flag)
        }
        // Git names the merge commit after the name it is given ("Merge branch
        // 'x'"), so pass the short name unless a tag or other ref shares it.
        let resolved = try await execute(["rev-parse", "--symbolic-full-name", branch], in: repository)
        let isUnambiguous = resolved.exitCode == 0
            && resolved.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "refs/heads/\(branch)"
        arguments.append(isUnambiguous ? branch : "refs/heads/\(branch)")
        let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
        if result.exitCode == 0 {
            return .completed
        }
        // A conflicted merge waits in MERGE_HEAD; a conflicted squash has no
        // MERGE_HEAD but leaves unmerged files.
        let state = try await operationState(in: repository)
        let unmerged = try await run(["ls-files", "--unmerged"], in: repository)
        if state == .merge || !unmerged.stdout.isEmpty {
            return .stopped(combinedOutput(result))
        }
        throw failure(arguments, result)
    }

    func rebase(onto branch: String, autostash: Bool, in repository: URL) async throws -> IntegrationOutcome {
        let arguments = ["rebase", autostash ? "--autostash" : "--no-autostash", "refs/heads/\(branch)"]
        let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
        return try await rebaseOutcome(arguments, result, in: repository)
    }

    func rebaseCandidates(onto branch: String, in repository: URL) async throws -> [CommitSummary] {
        // The same selection Git makes for the todo list: commits on HEAD's side
        // of the symmetric range, merges dropped, commits whose patch is already
        // in `branch` skipped, in graph order oldest first.
        let result = try await run([
            "log", "--reverse", "--topo-order", "--no-merges", "--cherry-pick", "--right-only",
            "--pretty=format:%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%b%x00",
            "refs/heads/\(branch)...HEAD", "--"
        ], in: repository)
        return try LogParser.parse(result.stdout)
    }

    func interactiveRebase(onto branch: String, plan: InteractiveRebasePlan, autostash: Bool, in repository: URL) async throws -> IntegrationOutcome {
        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory.appendingPathComponent("avi-rebase-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
        // The sequence editor copies the messages into Git's own rebase state,
        // so nothing here is needed once `git rebase` returns.
        defer { try? fileManager.removeItem(at: workDir) }

        let expected = workDir.appendingPathComponent("expected")
        let todo = workDir.appendingPathComponent("todo")
        let messages = workDir.appendingPathComponent("messages", isDirectory: true)
        let script = workDir.appendingPathComponent("sequence-editor.sh")
        try plan.expectedListing.write(to: expected, atomically: true, encoding: .utf8)
        try plan.todo.write(to: todo, atomically: true, encoding: .utf8)
        try InteractiveRebasePlan.sequenceEditorScript.write(to: script, atomically: true, encoding: .utf8)
        if !plan.messages.isEmpty {
            try fileManager.createDirectory(at: messages, withIntermediateDirectories: true)
            for (oid, message) in plan.messages {
                try message.write(to: messages.appendingPathComponent(oid), atomically: true, encoding: .utf8)
            }
        }

        var environment = nonInteractiveEnvironment()
        environment["GIT_SEQUENCE_EDITOR"] = [script, expected, todo, messages]
            .map { shellQuote($0.path) }
            .reduce("/bin/sh") { $0 + " " + $1 }
        let arguments = [
            "-c", "core.abbrev=\(plan.original[0].count)",
            "-c", "rebase.abbreviateCommands=false",
            "-c", "core.commentChar=#",
            "rebase", "-i", "--no-autosquash", "--no-rebase-merges", "--no-update-refs",
            autostash ? "--autostash" : "--no-autostash",
            "refs/heads/\(branch)"
        ]
        let result = try await execute(arguments, in: repository, environment: environment)
        return try await rebaseOutcome(arguments, result, in: repository)
    }

    func continueRebase(in repository: URL) async throws -> IntegrationOutcome {
        let arguments = ["rebase", "--continue"]
        let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
        return try await rebaseOutcome(arguments, result, in: repository)
    }

    func skipRebaseCommit(in repository: URL) async throws -> IntegrationOutcome {
        let arguments = ["rebase", "--skip"]
        let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
        return try await rebaseOutcome(arguments, result, in: repository)
    }

    func abortOperation(_ operation: GitOperationState, in repository: URL) async throws {
        switch operation {
        case .merge:
            try await run(["merge", "--abort"], in: repository)
        case .rebase:
            try await run(["rebase", "--abort"], in: repository)
        }
    }

    func deleteRemoteBranch(named branch: String, remote: String, in repository: URL) async throws -> GitRemoteOperationResult {
        let result = try await run(["push", "--delete", "--", remote, "refs/heads/\(branch)"], in: repository)
        return remoteResult(result)
    }

    // MARK: - Detached HEAD and worktrees

    func unreferencedCommitCount(in repository: URL) async throws -> Int {
        let result = try await run(["rev-list", "--count", "HEAD", "--not", "--branches", "--tags", "--remotes"], in: repository)
        return Int(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func removeWorktree(at path: URL, force: Bool, in repository: URL) async throws {
        guard path.path.hasPrefix("/") else {
            throw GitError.invalidInput("A worktree path must be absolute.")
        }
        try await run(["worktree", "remove"] + (force ? ["--force"] : []) + [path.path], in: repository)
    }

    func pruneWorktrees(in repository: URL) async throws -> String {
        let result = try await run(["worktree", "prune", "--verbose"], in: repository)
        return combinedOutput(result)
    }

    // MARK: - File actions

    func stash(paths: [String], message: String?, includeUntracked: Bool, in repository: URL) async throws {
        guard !paths.isEmpty else {
            throw GitError.invalidInput("Choose the files to stash.")
        }
        var arguments = ["--literal-pathspecs", "stash", "push"]
        if includeUntracked {
            arguments.append("--include-untracked")
        }
        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            arguments += ["-m", message]
        }
        try await run(arguments + ["--"] + paths, in: repository)
    }

    func patch(for files: [FileStatus], staged: Bool, in repository: URL) async throws -> Data {
        // A staged rename needs both sides for the patch to show it as one.
        let tracked = files.filter { staged || !$0.isUntracked }
            .flatMap { [$0.path] + [$0.originalPath].compactMap(\.self) }
        let untracked = staged ? [] : files.filter(\.isUntracked).map(\.path)
        var output = Data()
        for chunk in tracked.chunked(into: 200) {
            var arguments = ["--literal-pathspecs", "diff"]
            if staged {
                arguments.append("--cached")
            }
            arguments += ["--binary", "--no-color", "--no-ext-diff", "--no-textconv", "--"] + chunk
            output += try await run(arguments, in: repository).stdout
        }
        for path in untracked {
            // --no-index exits 1 when the files differ, which a new file always does.
            let result = try await run(
                ["diff", "--no-index", "--binary", "--no-color", "--no-ext-diff", "--no-textconv", "--", "/dev/null", path],
                in: repository,
                allowedExitCodes: [0, 1]
            )
            output += result.stdout
        }
        return output
    }

    func fileHistory(path: String, limit: Int, in repository: URL) async throws -> [FileHistoryEntry] {
        let arguments = [
            "--literal-pathspecs", "log", "--follow", "-M", "--no-color", "-n", String(limit),
            "--format=\(FileHistoryParser.format)", "--name-status", "-z", "--", path
        ]
        let result = try await execute(arguments, in: repository)
        guard result.exitCode == 0 else {
            // A repository without commits has no history for anything.
            if result.stderrString.contains("does not have any commits yet") {
                return []
            }
            throw failure(arguments, result)
        }
        return try FileHistoryParser.parse(result.stdout, path: path)
    }

    func diff(commitOID: String, path: String, oldPath: String?, in repository: URL) async throws -> FileDiff {
        let paths = [oldPath].compactMap(\.self).filter { $0 != path } + [path]
        // A merge shows its change against the first parent, as a normal diff.
        let result = try await run(
            ["--literal-pathspecs", "show", "--format=", "--no-color", "--no-ext-diff", "-M", "--diff-merges=first-parent", commitOID, "--"] + paths,
            in: repository
        )
        return DiffParser.parse(result.stdoutString)
    }

    func blame(path: String, revision: String?, in repository: URL) async throws -> [BlameLine] {
        var arguments = ["blame", "--porcelain"]
        if let revision {
            // Only immutable IDs, never revision syntax or an option.
            guard LinearRebasePlan.isOID(revision) else {
                throw GitError.invalidInput("Blame needs a full commit ID.")
            }
            arguments.append(revision)
        }
        let result = try await run(arguments + ["--", path], in: repository)
        return try BlameParser.parse(result.stdout)
    }

    func launchDiffTool(path: String, staged: Bool, toolPath: String?, in repository: URL) async throws {
        var arguments = ["--literal-pathspecs", "difftool", "--no-prompt"]
        if staged {
            arguments.append("--cached")
        }
        if let toolPath = toolPath?.trimmingCharacters(in: .whitespacesAndNewlines), !toolPath.isEmpty {
            // Git runs the command through the shell with "$LOCAL" "$REMOTE" appended.
            arguments.append("--extcmd=\(shellQuote(toolPath))")
        }
        arguments += ["--", path]
        // Not through the command queue: the tool runs until you close it, and
        // Avi's other Git commands must not wait for that. It only reads.
        let result = try await ProcessRunner.run(
            executable: gitURL,
            arguments: arguments,
            workingDirectory: repository,
            environment: gitEnvironment()
        )
        guard result.exitCode == 0 else {
            throw failure(arguments, result)
        }
    }

    // MARK: - Helpers

    /// Where a repository's merge or rebase stands, read from its own git dir.
    func operationState(in repository: URL) async throws -> GitOperationState? {
        try await GitOperationState.detect(gitDir: location(of: repository).gitDir)
    }
}

extension CLIGitProvider {
    private func checkoutCarryingChanges(_ ref: GitReference, in repository: URL) async throws -> CheckoutOutcome {
        let before = try await stashTip(in: repository)
        try await run(["stash", "push", "--include-untracked", "-m", "Avi: local changes carried to \(ref.name)"], in: repository)
        guard let after = try await stashTip(in: repository), after != before else {
            // Nothing was left to stash.
            try await checkout(ref, in: repository)
            return .switched
        }
        do {
            try await checkout(ref, in: repository)
        } catch {
            let restored = try? await execute(["stash", "pop", "--index"], in: repository)
            guard restored?.exitCode == 0 else {
                throw GitError.invalidInput(error.localizedDescription
                    + "\n\nYour local changes are saved in the stash \"Avi: local changes carried to \(ref.name)\". Apply it from the Stashes section.")
            }
            throw error
        }
        var restored = try await execute(["stash", "pop", "--index"], in: repository)
        if restored.exitCode != 0, restored.stderrString.contains("--index") {
            // The staged part no longer applies on this branch; keep the changes unstaged.
            restored = try await execute(["stash", "pop"], in: repository)
        }
        return restored.exitCode == 0 ? .switched : .changesConflicted(combinedOutput(restored))
    }

    private func stashTip(in repository: URL) async throws -> String? {
        let result = try await execute(["rev-parse", "--quiet", "--verify", "refs/stash"], in: repository)
        let oid = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !oid.isEmpty ? oid : nil
    }

    /// A stopped rebase is not an error: it waits in the git dir for you.
    private func rebaseOutcome(_ arguments: [String], _ result: ProcessResult, in repository: URL) async throws -> IntegrationOutcome {
        if try await operationState(in: repository) == .rebase {
            return .stopped(combinedOutput(result))
        }
        guard result.exitCode == 0 else {
            throw failure(arguments, result)
        }
        return .completed
    }

    /// Commands that may want an editor must never wait for one.
    func nonInteractiveEnvironment() -> [String: String] {
        var environment = gitEnvironment()
        environment["GIT_EDITOR"] = "/usr/bin/true"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        return environment
    }

    private func combinedOutput(_ result: ProcessResult) -> String {
        [result.stdoutString, result.stderrString]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func failure(_ arguments: [String], _ result: ProcessResult) -> GitError {
        let stderr = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitError.commandFailed(
            command: (["git"] + arguments).joined(separator: " "),
            exitCode: result.exitCode,
            stderr: stderr.isEmpty ? combinedOutput(result) : stderr
        )
    }

    @discardableResult
    func run(_ arguments: [String], in repository: URL, environment: [String: String]) async throws -> ProcessResult {
        let result = try await execute(arguments, in: repository, environment: environment)
        guard result.exitCode == 0 else {
            throw failure(arguments, result)
        }
        return result
    }
}
