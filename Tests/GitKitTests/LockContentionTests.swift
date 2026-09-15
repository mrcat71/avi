import Foundation
@testable import GitKit
import Testing

/// Counts how many times the retried operation was invoked.
private actor CallCounter {
    private(set) var count = 0
    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}

private func lockFailure() -> ProcessResult {
    ProcessResult(
        stdout: Data(),
        stderr: Data("fatal: Unable to create '/repo/.git/index.lock': File exists.".utf8),
        exitCode: 128
    )
}

private func success() -> ProcessResult {
    ProcessResult(stdout: Data("ok".utf8), stderr: Data(), exitCode: 0)
}

struct LockContentionTests {
    // MARK: - Detection

    @Test func detectsIndexLockFileExists() {
        #expect(GitError.indicatesLockContention(
            "fatal: Unable to create '/repo/.git/index.lock': File exists."
        ))
    }

    @Test func detectsAnotherGitProcessRunning() {
        #expect(GitError.indicatesLockContention(
            "Another git process seems to be running in this repository, e.g."
        ))
    }

    @Test func detectsRefLockContention() {
        #expect(GitError.indicatesLockContention(
            "error: cannot lock ref 'refs/heads/main': Unable to create "
                + "'/repo/.git/refs/heads/main.lock': File exists."
        ))
    }

    @Test func ignoresUnrelatedFailures() {
        #expect(!GitError.indicatesLockContention("fatal: not a git repository"))
        #expect(!GitError.indicatesLockContention(""))
    }

    // MARK: - Friendly message

    @Test func lockErrorHasFriendlyDescription() {
        let error = GitError.commandFailed(
            command: "git switch -- main",
            exitCode: 128,
            stderr: "fatal: Unable to create '/repo/.git/index.lock': File exists."
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("index.lock"))
        // The raw "exit 128" form is replaced by the guidance message.
        #expect(!description.contains("exit 128"))
    }

    @Test func nonLockErrorKeepsRawDetail() {
        let error = GitError.commandFailed(
            command: "git status",
            exitCode: 128,
            stderr: "fatal: not a git repository"
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("exit 128"))
        #expect(description.contains("not a git repository"))
    }

    // MARK: - Retry

    @Test func retriesOnLockContentionThenSucceeds() async throws {
        let counter = CallCounter()
        let result = try await CLIGitProvider.runWithLockRetry(backoff: [.zero, .zero, .zero]) {
            let attempt = await counter.increment()
            return attempt < 3 ? lockFailure() : success()
        }
        #expect(result.exitCode == 0)
        #expect(await counter.count == 3)
    }

    @Test func givesUpAfterExhaustingBackoff() async throws {
        let counter = CallCounter()
        let result = try await CLIGitProvider.runWithLockRetry(backoff: [.zero, .zero]) {
            await counter.increment()
            return lockFailure()
        }
        // Returns the final failing result so normal exit-code handling still runs.
        #expect(result.exitCode == 128)
        // Initial attempt + 2 retries.
        #expect(await counter.count == 3)
    }

    @Test func doesNotRetryNonLockFailures() async throws {
        let counter = CallCounter()
        let result = try await CLIGitProvider.runWithLockRetry(backoff: [.zero, .zero, .zero]) {
            await counter.increment()
            return ProcessResult(
                stdout: Data(),
                stderr: Data("fatal: not a git repository".utf8),
                exitCode: 128
            )
        }
        #expect(result.exitCode == 128)
        #expect(await counter.count == 1)
    }

    @Test func doesNotRetrySuccess() async throws {
        let counter = CallCounter()
        let result = try await CLIGitProvider.runWithLockRetry(backoff: [.zero, .zero, .zero]) {
            await counter.increment()
            return success()
        }
        #expect(result.exitCode == 0)
        #expect(await counter.count == 1)
    }

    @Test func cancellationDoesNotRetry() async throws {
        let counter = CallCounter()
        let task = Task {
            try await CLIGitProvider.runWithLockRetry(backoff: [.seconds(60)]) {
                await counter.increment()
                return lockFailure()
            }
        }
        while await counter.count == 0 {
            await Task.yield()
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled retry must throw CancellationError")
        } catch is CancellationError {
            #expect(await counter.count == 1)
        }
    }
}
