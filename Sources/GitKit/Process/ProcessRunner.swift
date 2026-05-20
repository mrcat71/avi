import Foundation

/// Result of running an external process.
public struct ProcessResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// Runs external processes with arguments passed as an argv array (never a shell
/// string), so untrusted values like repo paths or branch names cannot inject commands.
///
/// Fully event-driven: pipes are drained via `readabilityHandler` and completion is
/// signalled by `terminationHandler`. Nothing blocks a thread, so running many
/// processes in sequence cannot exhaust the dispatch thread pool.
public enum ProcessRunner {
    public static func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let environment { process.environment = environment }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let state = RunState()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
            state.attach(continuation)

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.markStdoutDone()
                } else {
                    state.appendStdout(data)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.markStderrDone()
                } else {
                    state.appendStderr(data)
                }
            }
            process.terminationHandler = { process in
                state.markTerminated(exitCode: process.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                state.fail(error)
            }
        }
    }
}

/// Collects stdout/stderr and resumes the continuation exactly once, when the
/// process has terminated and both pipes have reported EOF. Lock-guarded because
/// the readability and termination handlers fire on background dispatch queues.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutDone = false
    private var stderrDone = false
    private var terminated = false
    private var exitCode: Int32 = 0
    private var continuation: CheckedContinuation<ProcessResult, Error>?
    private var resumed = false

    func attach(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        finishIfReady()
    }

    func appendStdout(_ data: Data) {
        lock.lock(); stdout.append(data); lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock(); stderr.append(data); lock.unlock()
    }

    func markStdoutDone() {
        lock.lock(); stdoutDone = true; lock.unlock()
        finishIfReady()
    }

    func markStderrDone() {
        lock.lock(); stderrDone = true; lock.unlock()
        finishIfReady()
    }

    func markTerminated(exitCode: Int32) {
        lock.lock(); terminated = true; self.exitCode = exitCode; lock.unlock()
        finishIfReady()
    }

    func fail(_ error: Error) {
        lock.lock()
        guard !resumed, let continuation else { lock.unlock(); return }
        resumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }

    private func finishIfReady() {
        lock.lock()
        guard !resumed, stdoutDone, stderrDone, terminated, let continuation else {
            lock.unlock()
            return
        }
        resumed = true
        self.continuation = nil
        let result = ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
        lock.unlock()
        continuation.resume(returning: result)
    }
}
