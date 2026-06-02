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
    private var tails: [String: Task<Void, Never>] = [:]

    public init() {}

    /// Runs `operation` once all previously enqueued operations for `repository`
    /// have finished. The operation's result (or thrown error) is delivered to its
    /// own caller; a failure does not stall later operations in the chain.
    public func run<T: Sendable>(
        repository: URL,
        _ operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let key = repository.standardizedFileURL.path
        let previous = tails[key]

        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        // The tail resolves only after `task` settles, regardless of outcome.
        tails[key] = Task { _ = try? await task.value }

        return try await task.value
    }
}
