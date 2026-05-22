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
}

/// Runs a `git clone` (or `gh repo clone` / `glab repo clone` when available)
/// and streams progress via a callback so the UI can update a progress bar.
public enum CloneRunner {
    public struct Spec: Sendable {
        public var repo: RemoteRepo
        public var destination: URL
        public var preferredProtocol: String // "https" | "ssh"
        public var preferredCLI: String // "auto" | "gh-glab" | "git"
        public var ghPath: String?
        public var glabPath: String?

        public init(
            repo: RemoteRepo,
            destination: URL,
            preferredProtocol: String,
            preferredCLI: String,
            ghPath: String?,
            glabPath: String?
        ) {
            self.repo = repo
            self.destination = destination
            self.preferredProtocol = preferredProtocol
            self.preferredCLI = preferredCLI
            self.ghPath = ghPath
            self.glabPath = glabPath
        }

        public var fallbackURL: String {
            preferredProtocol == "ssh" && !repo.sshURL.isEmpty ? repo.sshURL : repo.httpsURL
        }
    }

    public static func clone(spec: Spec, progress: @escaping @Sendable (CloneProgress) -> Void) async throws -> CloneOutcome {
        if FileManager.default.fileExists(atPath: spec.destination.path) {
            // Refuse to overwrite an existing non-empty directory; caller should validate.
            let contents = (try? FileManager.default.contentsOfDirectory(at: spec.destination, includingPropertiesForKeys: nil)) ?? []
            if !contents.isEmpty {
                throw CloneError.destinationNotEmpty(path: spec.destination.path)
            }
        }
        try FileManager.default.createDirectory(at: spec.destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let useCLI = spec.preferredCLI != "git"
        if useCLI, spec.repo.provider == .github, let path = spec.ghPath {
            return try await runProcess(
                executable: path,
                arguments: ["repo", "clone", spec.repo.nameWithOwner, spec.destination.path, "--", "--progress"],
                destination: spec.destination,
                progress: progress
            )
        }
        if useCLI, spec.repo.provider == .gitlab, let path = spec.glabPath {
            return try await runProcess(
                executable: path,
                arguments: ["repo", "clone", spec.repo.nameWithOwner, spec.destination.path],
                destination: spec.destination,
                progress: progress
            )
        }
        // Fall back to plain git.
        let url = spec.fallbackURL
        guard !url.isEmpty else { throw CloneError.noURL }
        return try await runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "clone", "--progress", url, spec.destination.path],
            destination: spec.destination,
            progress: progress
        )
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        destination: URL,
        progress: @escaping @Sendable (CloneProgress) -> Void
    ) async throws -> CloneOutcome {
        let env = ProviderCLISupport.environment()
        // Throttle progress updates to ~10/sec.
        let throttle = ProgressThrottle(onEmit: progress)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["env"] // placeholder; we replace below if needed
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
            success: exitCode == 0
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
        if buffer.count > maxLines { buffer.removeFirst(buffer.count - maxLines) }
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
