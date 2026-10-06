import Foundation
import GitKit

/// Progress signal emitted while a clone is running.
public struct CloneProgress: Sendable, Equatable {
    public var phase: String // "Counting", "Receiving", "Resolving", "Checking out", etc.
    public var percent: Int? // 0..100 when parsable
    public var rawLine: String

    public init(phase: String, percent: Int? = nil, rawLine: String = "") {
        self.phase = phase
        self.percent = percent
        self.rawLine = rawLine
    }
}

/// Result of a clone attempt.
public struct CloneOutcome: Sendable {
    public var destination: URL
    public var exitCode: Int32
    public var stderrTail: String
    public var success: Bool
    /// Something that went wrong after the clone itself succeeded.
    public var warning: String?
}

/// How Git proves who you are while cloning over HTTPS.
public enum CloneCredential: Sendable, Equatable, CustomStringConvertible {
    /// What Git is set up with: the Keychain, your credential helpers, SSH.
    case gitDefault
    /// The credential helper of `gh` or `glab` at this path, for this clone.
    case cliHelper(executable: String)
    /// A token Avi hands to Git through the environment, never the arguments.
    case token(username: String, secret: String)

    public var description: String {
        switch self {
        case .gitDefault: return "git default"
        case .cliHelper(let executable): return "helper \(executable)"
        case .token(let username, _): return "token for \(username)"
        }
    }
}

/// Runs `git clone` and streams progress via a callback so the UI can update
/// a progress bar.
public enum CloneRunner {
    public struct Spec: Sendable {
        /// Exactly what is passed to `git clone`.
        public var url: String
        public var destination: URL
        public var credential: CloneCredential
        /// For a CLI helper: the host whose helper the clone keeps using, so
        /// fetches and pushes authenticate as the chosen account too.
        public var host: String?

        public init(url: String, destination: URL, credential: CloneCredential = .gitDefault, host: String? = nil) {
            self.url = url
            self.destination = destination
            self.credential = credential
            self.host = host
        }
    }

    /// A helper that answers Git's `get` from two environment variables, so
    /// the token never appears in the arguments or a config file.
    static let tokenHelper = #"!f() { test "$1" = get || exit 0; printf 'username=%s\npassword=%s\n' "$AVI_CLONE_USERNAME" "$AVI_CLONE_TOKEN"; }; f"#

    /// The `git` arguments and extra environment for `spec`. A helper chosen
    /// here replaces the ones in your Git config for this clone only, so they
    /// neither answer for the wrong account nor store the token. `--` keeps a
    /// URL that starts with a dash from being read as an option.
    static func gitCommand(for spec: Spec) -> (arguments: [String], environment: [String: String]) {
        var arguments: [String] = []
        var environment: [String: String] = [:]
        switch spec.credential {
        case .gitDefault:
            break
        case .cliHelper(let executable):
            arguments += ["-c", "credential.helper=", "-c", "credential.helper=" + cliHelperCommand(executable)]
        case .token(let username, let secret):
            arguments += ["-c", "credential.helper=", "-c", "credential.helper=" + tokenHelper]
            environment["AVI_CLONE_USERNAME"] = username
            environment["AVI_CLONE_TOKEN"] = secret
        }
        arguments += ["clone", "--progress", "--", spec.url, spec.destination.path]
        return (arguments, environment)
    }

    /// `gh auth git-credential` or `glab auth git-credential`, quoted for the
    /// shell Git runs `!` helpers in.
    static func cliHelperCommand(_ executable: String) -> String {
        "!'" + executable.replacingOccurrences(of: "'", with: #"'\''"#) + "' auth git-credential"
    }

    public static func clone(spec: Spec, progress: @escaping @Sendable (CloneProgress) -> Void) async throws -> CloneOutcome {
        if FileManager.default.fileExists(atPath: spec.destination.path) {
            // Refuse to overwrite an existing non-empty directory; caller should validate.
            let contents = (try? FileManager.default.contentsOfDirectory(at: spec.destination, includingPropertiesForKeys: nil)) ?? []
            if !contents.isEmpty {
                throw CloneError.destinationNotEmpty(path: spec.destination.path)
            }
        }
        guard !spec.url.isEmpty else { throw CloneError.noURL }
        try FileManager.default.createDirectory(at: spec.destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let command = gitCommand(for: spec)
        var outcome = try await runProcess(
            executable: "/usr/bin/env",
            arguments: ["git"] + command.arguments,
            extraEnvironment: command.environment,
            destination: spec.destination,
            progress: progress
        )
        if outcome.success, case .cliHelper(let executable) = spec.credential, let host = spec.host {
            outcome.warning = await keepHelper(executable, for: host, in: spec.destination)
        }
        return outcome
    }

    /// Sets the clone to authenticate `host` through the same CLI helper, the
    /// way `gh auth setup-git` does globally, so later fetches and pushes use
    /// the account named in the remote URL. Returns a warning on failure.
    private static func keepHelper(_ executable: String, for host: String, in repository: URL) async -> String? {
        let key = "credential.https://\(host).helper"
        for value in ["", cliHelperCommand(executable)] {
            let result = try? await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["git", "config", "--local", "--add", key, value],
                workingDirectory: repository,
                environment: ProviderCLISupport.environment()
            )
            if result?.exitCode != 0 {
                let detail = result?.stderrString.trimmingCharacters(in: .whitespacesAndNewlines) ?? "git did not start"
                return "Cloned, but fetch and push may ask for other credentials: setting \(key) failed (\(detail))."
            }
        }
        return nil
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        extraEnvironment: [String: String],
        destination: URL,
        progress: @escaping @Sendable (CloneProgress) -> Void
    ) async throws -> CloneOutcome {
        let env = ProviderCLISupport.environment().merging(extraEnvironment) { _, extra in extra }
        // Throttle progress updates to ~10/sec.
        let throttle = ProgressThrottle(onEmit: progress)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let stderrCollector = StderrCollector()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for line in CloneRunner.lines(in: data) {
                if let parsed = parseProgress(line) {
                    throttle.submit(parsed)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            stderrCollector.append(data)
            for line in CloneRunner.lines(in: data) {
                if let parsed = parseProgress(line) {
                    throttle.submit(parsed)
                }
            }
        }

        let exitCode: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        throttle.flush()

        return CloneOutcome(
            destination: destination,
            exitCode: exitCode,
            stderrTail: stderrCollector.tail(maxLines: 20),
            success: exitCode == 0,
            warning: nil
        )
    }

    private static func lines(in data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        // git --progress uses \r between updates within a phase; split on both.
        return text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
    }

    private static let progressRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"^([A-Za-z ]+):\s+(\d+)%"#)

    private static func parseProgress(_ line: String) -> CloneProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let regex = progressRegex else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range), match.numberOfRanges == 3,
              let phaseRange = Range(match.range(at: 1), in: trimmed),
              let percentRange = Range(match.range(at: 2), in: trimmed),
              let percent = Int(trimmed[percentRange])
        else {
            return CloneProgress(phase: trimmed, percent: nil, rawLine: trimmed)
        }
        return CloneProgress(phase: String(trimmed[phaseRange]).trimmingCharacters(in: .whitespaces), percent: percent, rawLine: trimmed)
    }
}

public enum CloneError: Error, LocalizedError, Sendable {
    case destinationNotEmpty(path: String)
    case noURL

    public var errorDescription: String? {
        switch self {
        case .destinationNotEmpty(let path): return "Destination is not empty: \(path)"
        case .noURL: return "No clone URL available for this repository."
        }
    }
}

/// A next step for the errors Git gives most often when a clone cannot
/// authenticate, or nil when there is nothing specific to suggest.
func cloneFailureHint(for message: String, host: String?) -> String? {
    let target = host.map { "git@\($0)" } ?? "git@<host>"
    if message.contains("Host key verification failed") {
        return "This Mac has not connected to the host over SSH before. Run `ssh -T \(target)` in Terminal once to check and trust its key, then try again."
    }
    if message.contains("Permission denied (publickey") {
        return "The server did not accept any of your SSH keys. Add your key to the agent with `ssh-add --apple-use-keychain ~/.ssh/id_ed25519` and its public half to your account, or clone over HTTPS."
    }
    if message.contains("could not read Username") || message.contains("Authentication failed") || message.contains("terminal prompts disabled") {
        return "Git had no credentials for this host. Pick an account under HTTPS, sign in with `gh auth login` or `glab auth login`, or clone over SSH."
    }
    return nil
}

/// Collects stderr in a ring buffer so failures can show the last few lines.
private final class StderrCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [String] = []
    private let maxLines = 64

    func append(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        lock.lock(); defer { lock.unlock() }
        buffer.append(contentsOf: lines)
        if buffer.count > maxLines {
            buffer.removeFirst(buffer.count - maxLines)
        }
    }

    func tail(maxLines: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        let slice = buffer.suffix(maxLines)
        return slice.joined(separator: "\n")
    }
}

/// Throttles progress callbacks to at most ~10/sec to keep the UI snappy.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let onEmit: @Sendable (CloneProgress) -> Void
    private var last: CloneProgress?
    private var lastEmitAt = Date.distantPast
    private let minInterval: TimeInterval = 0.1

    init(onEmit: @escaping @Sendable (CloneProgress) -> Void) {
        self.onEmit = onEmit
    }

    func submit(_ progress: CloneProgress) {
        lock.lock()
        last = progress
        let elapsed = Date().timeIntervalSince(lastEmitAt)
        lock.unlock()
        if elapsed >= minInterval {
            flush()
        }
    }

    func flush() {
        lock.lock()
        guard let value = last else { lock.unlock(); return }
        lastEmitAt = Date()
        lock.unlock()
        onEmit(value)
    }
}
