import Foundation

/// Serializes git subprocess execution per repository working tree.
///
/// Git takes `.git/index.lock` (and other locks) for many operations and refuses
/// to start when another git process already holds one, failing with
/// `Unable to create '.../index.lock': File exists` / "another git process seems
/// to be running". Avi can otherwise fire several git commands at once against the
/// same repo - a filesystem-watch auto-refresh landing while the user stages files,
/// two menu shortcuts, a multi-step AI commit apply, or a manual action during a
/// fetch - so every command for a given repository is funnelled through a serial
/// chain here. Commands for different repositories still run concurrently.
///
/// A process-wide singleton on purpose: locks are per on-disk repository, so the
/// serialization must hold across every `CLIGitProvider`/store that points at the
/// same path.
public actor GitCommandQueue {
    public static let shared = GitCommandQueue()

    /// Per-repository tail of the chain. Each value completes only after the most
    /// recently enqueued operation for that repo has fully settled, so the next
    /// caller can chain strictly behind it.
    private struct Pending {
        let id: UUID
        let completion: Task<Void, Never>
    }

    private var tails: [String: Pending] = [:]

    public init() {}

    /// Sibling worktrees have different working trees but one shared common dir
    /// holding the refs, so they must queue against each other. Resolved from the
    /// filesystem rather than `git rev-parse`: computing the key must never
    /// enqueue a command on the queue it is computing the key for.
    ///
    /// A linked worktree's `.git` is a file reading `gitdir: <main>/.git/worktrees/<name>`.
    /// Anything unexpected falls back to the working tree path, which is the
    /// behaviour of an ordinary single-worktree repository.
    static func queueKey(for repository: URL) -> String {
        let root = repository.resolvingSymlinksInPath().standardizedFileURL
        guard let commonDir = linkedWorktreeCommonDir(for: root) else { return root.path }
        // Key on the main repository's root, which is the key an ordinary
        // repository already produces, so both sides of the pair agree.
        let main = commonDir.lastPathComponent == ".git"
            ? commonDir.deletingLastPathComponent()
            : commonDir
        return main.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Common dir of the repository `root` is linked to, or nil when `root` is an
    /// ordinary working tree whose `.git` is a directory.
    private static func linkedWorktreeCommonDir(for root: URL) -> URL? {
        let dotGit = root.appendingPathComponent(".git")
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              let gitDirLine = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }

        let rawPath = gitDirLine.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty else { return nil }
        let gitDir = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: rawPath)
            : root.appendingPathComponent(rawPath)
        let standardized = gitDir.standardizedFileURL
        // <common dir>/worktrees/<name>
        guard standardized.deletingLastPathComponent().lastPathComponent == "worktrees" else {
            return nil
        }
        return standardized.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Runs `operation` once all previously enqueued operations for `repository`
    /// have finished. The operation's result (or thrown error) is delivered to its
    /// own caller; a failure does not stall later operations in the chain.
    public func run<T: Sendable>(
        repository: URL,
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let key = Self.queueKey(for: repository)
        let previous = tails[key]?.completion
        let id = UUID()

        let task = Task<T, Error> {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        // The tail resolves only after `task` settles, regardless of outcome.
        tails[key] = Pending(id: id, completion: Task { _ = await task.result })

        defer {
            if tails[key]?.id == id {
                tails.removeValue(forKey: key)
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
