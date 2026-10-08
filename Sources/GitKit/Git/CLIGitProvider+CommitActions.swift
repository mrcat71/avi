import Foundation

/// What History's commit menu does with one commit: copy it onto HEAD, undo
/// it, export it, check it out, or compare it with the working tree.
public extension CLIGitProvider {
    /// `git cherry-pick`. A merge commit is picked against its first parent.
    /// Conflicts stop it with CHERRY_PICK_HEAD in place.
    func cherryPick(commit oid: String, isMerge: Bool, in repository: URL) async throws -> IntegrationOutcome {
        let arguments = ["cherry-pick"] + (isMerge ? ["-m", "1"] : []) + [oid]
        let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
        return try await sequencerOutcome(arguments, result, in: repository)
    }

    /// `git revert` with Git's own message. A merge commit is reverted against
    /// its first parent. Conflicts stop it with REVERT_HEAD in place.
    func revert(commit oid: String, isMerge: Bool, in repository: URL) async throws -> IntegrationOutcome {
        let arguments = ["revert", "--no-edit"] + (isMerge ? ["-m", "1"] : []) + [oid]
        let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
        return try await sequencerOutcome(arguments, result, in: repository)
    }

    /// Continue the stopped rebase, cherry-pick, or revert. A merge finishes
    /// with a commit instead.
    func continueOperation(_ operation: GitOperationState, in repository: URL) async throws -> IntegrationOutcome {
        switch operation {
        case .rebase:
            return try await continueRebase(in: repository)
        case .cherryPick, .revert:
            let arguments = [operation == .cherryPick ? "cherry-pick" : "revert", "--continue"]
            let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
            return try await sequencerOutcome(arguments, result, in: repository)
        case .merge:
            throw GitError.invalidInput("A merge finishes with a commit.")
        }
    }

    /// Skip the commit the rebase, cherry-pick, or revert stopped at.
    func skipOperation(_ operation: GitOperationState, in repository: URL) async throws -> IntegrationOutcome {
        switch operation {
        case .rebase:
            return try await skipRebaseCommit(in: repository)
        case .cherryPick, .revert:
            let arguments = [operation == .cherryPick ? "cherry-pick" : "revert", "--skip"]
            let result = try await execute(arguments, in: repository, environment: nonInteractiveEnvironment())
            return try await sequencerOutcome(arguments, result, in: repository)
        case .merge:
            throw GitError.invalidInput("A merge has no commit to skip.")
        }
    }

    /// The commit as an mbox patch `git am` can apply.
    func formatPatch(commit oid: String, in repository: URL) async throws -> Data {
        try await run(["format-patch", "-1", "--stdout", "--no-color", oid], in: repository).stdout
    }

    /// Detaches HEAD at `oid`. Git refuses when local changes would be overwritten.
    func checkoutDetached(commit oid: String, in repository: URL) async throws {
        try await run(["switch", "--detach", "--", oid], in: repository)
    }

    /// Files that differ between `oid` and the working tree, tracked files only.
    func changedFilesAgainstWorkingTree(from oid: String, in repository: URL) async throws -> [CommitFileChange] {
        let result = try await run(["diff", "--name-status", "-z", "-M", "--no-ext-diff", oid, "--"], in: repository)
        return try CommitFileChangeParser.parse(result.stdout)
    }

    /// One file's diff from `oid` to the working tree.
    func diffAgainstWorkingTree(
        from oid: String,
        path: String,
        oldPath: String?,
        options: DiffOptions,
        in repository: URL
    ) async throws -> FileDiff {
        let paths = [oldPath, path].compactMap(\.self)
        let result = try await run(
            ["--literal-pathspecs", "diff", "--no-color", "--no-ext-diff", "-M"] + options.arguments + [oid, "--"] + paths,
            in: repository
        )
        return DiffParser.parse(result.stdoutString)
    }

    /// Done, stopped with the operation in place, or failed before it started.
    private func sequencerOutcome(_ arguments: [String], _ result: ProcessResult, in repository: URL) async throws -> IntegrationOutcome {
        if result.exitCode == 0 {
            return .completed
        }
        if try await operationState(in: repository) != nil {
            return .stopped([result.stdoutString, result.stderrString]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n"))
        }
        throw GitError.commandFailed(command: "git " + arguments.joined(separator: " "), exitCode: result.exitCode, stderr: result.stderrString)
    }
}
