import Foundation

public enum AIEngineError: Error, CustomStringConvertible, LocalizedError {
    case noModelConfigured(String)
    case missingAPIKey
    case binaryNotFound(String)
    case binaryNotExecutable(String)
    case subprocessFailed(AIRunResult)
    case timedOut(AIRunResult)
    case invalidResponse(String)
    case cancelled

    public var description: String {
        errorDescription ?? "AI error"
    }

    public var errorDescription: String? {
        switch self {
        case .noModelConfigured(let reason):
            return reason.isEmpty ? "Set a model in Settings → AI Commit Messages." : reason
        case .missingAPIKey:
            return "No API key stored. Save one in Settings → AI Commit Messages."
        case .binaryNotFound(let name):
            return "Binary not found: \(name). Check Settings → External Tools."
        case .binaryNotExecutable(let path):
            return "Binary is not executable: \(path)."
        case .subprocessFailed(let r):
            return "AI command failed (exit \(r.exitCode.map(String.init) ?? "?")). See debug details."
        case .timedOut(let r):
            return "AI generation timed out after \(r.durationMS / 1000)s."
        case .invalidResponse(let msg):
            return "AI response invalid: \(msg)"
        case .cancelled:
            return "Generation cancelled."
        }
    }

    public var runResult: AIRunResult? {
        switch self {
        case .subprocessFailed(let r), .timedOut(let r): return r
        default: return nil
        }
    }
}

protocol AIEngine: Sendable {
    func generate(
        prompt: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        reasoningEffort: String
    ) async throws -> String
}

enum AIEngineFactory {
    @MainActor
    static func make(config: AIConfig) -> AIEngine {
        switch config.backend {
        case "openai":
            return OpenAIAIEngine(config: config)
        default:
            return CommandAIEngine(config: config)
        }
    }
}

// MARK: - Custom command backend

final class CommandAIEngine: AIEngine {
    let commandTemplate: String
    let timeoutSeconds: Int

    init(config: AIConfig) {
        commandTemplate = config.commandTemplate
        timeoutSeconds = max(5, config.timeoutSeconds)
    }

    func generate(
        prompt: String,
        model: String,
        temperature _: Double,
        maxTokens _: Int,
        reasoningEffort: String
    ) async throws -> String {
        // Write prompt to a temp file. Templates can reference it via ${prompt_file};
        // we ALSO pipe the prompt on stdin as a fallback for CLIs that read stdin.
        let tmpDir = FileManager.default.temporaryDirectory
        let promptURL = tmpDir.appendingPathComponent("avi-prompt-\(UUID().uuidString).txt")
        try Data(prompt.utf8).write(to: promptURL)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        // Substitute ${model}, ${prompt_file} and ${effort} in the command template.
        let rendered = commandTemplate
            .replacingOccurrences(of: "${model}", with: model)
            .replacingOccurrences(of: "${prompt_file}", with: promptURL.path)
            .replacingOccurrences(of: "${effort}", with: reasoningEffort)

        let argv = try shellSplit(rendered)
        guard let firstToken = argv.first, !firstToken.isEmpty else {
            throw AIEngineError.invalidResponse("Empty command template")
        }

        // Resolve binary.
        let resolved: String
        if firstToken.contains("/") {
            resolved = firstToken
        } else {
            guard let found = resolveExecutable(firstToken) else {
                throw AIEngineError.binaryNotFound(firstToken)
            }
            resolved = found
        }

        guard FileManager.default.isExecutableFile(atPath: resolved) else {
            throw AIEngineError.binaryNotExecutable(resolved)
        }

        // Build process.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = Array(argv.dropFirst())

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let startedAt = Date()

        try process.run()

        // Drain stdout/stderr concurrently so the pipes never fill (the old code
        // read these *after* termination, which deadlocked when output exceeded 64KB).
        async let stdoutData: Data = readAll(outPipe.fileHandleForReading)
        async let stderrData: Data = readAll(errPipe.fileHandleForReading)

        // Async stdin write. Must not block the calling thread (prompt can be large).
        Task.detached {
            let handle = inPipe.fileHandleForWriting
            handle.write(Data(prompt.utf8))
            try? handle.close()
        }

        // Wait for either termination or timeout, whichever comes first.
        // Also respect Task cancellation.
        let outcome = await waitForTerminationOrTimeout(process: process, timeoutSeconds: timeoutSeconds)

        // Now that the process is done (or being killed), gather buffered output.
        let stdout = await String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = await String(data: stderrData, encoding: .utf8) ?? ""
        let durationMS = Int(Date().timeIntervalSince(startedAt) * 1000)

        let result = AIRunResult(
            provider: "command",
            resolvedExecutable: resolved,
            argv: argv,
            model: model,
            exitCode: outcome == .timedOut ? nil : process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            durationMS: durationMS,
            timedOut: outcome == .timedOut
        )

        switch outcome {
        case .cancelled:
            throw AIEngineError.cancelled
        case .timedOut:
            throw AIEngineError.timedOut(result)
        case .terminated:
            if process.terminationStatus != 0 {
                throw AIEngineError.subprocessFailed(result)
            }
            return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Subprocess helpers

    private enum WaitOutcome: Equatable {
        case terminated
        case timedOut
        case cancelled
    }

    /// Spawns a task group: one task waits on process termination via the termination handler,
    /// another sleeps the timeout. The first to complete wins; the other is cancelled.
    private func waitForTerminationOrTimeout(process: Process, timeoutSeconds: Int) async -> WaitOutcome {
        await withTaskGroup(of: WaitOutcome.self) { group in
            // Termination listener.
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in
                        cont.resume()
                    }
                    if !process.isRunning {
                        // Already exited before we attached. Resume immediately.
                        process.terminationHandler = nil
                        cont.resume()
                    }
                }
                return .terminated
            }

            // Timeout.
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }

            let first = await group.next() ?? .timedOut
            group.cancelAll()

            if first == .timedOut || first == .cancelled {
                if process.isRunning {
                    process.terminate()
                    // Give it a moment to flush stderr / produce exit status.
                    try? await Task.sleep(for: .milliseconds(300))
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }

            return first
        }
    }

    /// Read all bytes from a pipe to EOF on a detached executor so concurrent
    /// awaits never share the same dispatch context.
    private func readAll(_ handle: FileHandle) async -> Data {
        await Task.detached(priority: .userInitiated) {
            handle.readDataToEndOfFile()
        }.value
    }

    private func resolveExecutable(_ name: String) -> String? {
        // Try `/usr/bin/which` first.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        if let _ = try? which.run() {
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to common bin dirs.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/.cargo/bin/\(name)",
            "\(home)/.nix-profile/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Minimal POSIX shell split. Supports double-quoted strings (with `\` escapes)
    /// and whitespace separation. No globbing, no variable expansion.
    private func shellSplit(_ input: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var inDoubleQuote = false
        var i = input.startIndex
        while i < input.endIndex {
            let ch = input[i]
            if inDoubleQuote {
                if ch == "\\" {
                    let next = input.index(after: i)
                    if next < input.endIndex {
                        current.append(input[next])
                        i = input.index(after: next)
                        continue
                    }
                } else if ch == "\"" {
                    inDoubleQuote = false
                    i = input.index(after: i)
                    continue
                }
                current.append(ch)
            } else {
                if ch == "\"" {
                    inDoubleQuote = true
                } else if ch.isWhitespace {
                    if !current.isEmpty {
                        result.append(current)
                        current = ""
                    }
                } else {
                    current.append(ch)
                }
            }
            i = input.index(after: i)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - OpenAI-compatible backend

final class OpenAIAIEngine: AIEngine {
    let baseURL: String
    let token: String?

    @MainActor
    init(config: AIConfig) {
        baseURL = config.openAIBaseURL
        token = KeychainStore.getString(account: config.openAIKeychainItem)
    }

    func generate(
        prompt: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        reasoningEffort: String
    ) async throws -> String {
        guard let token, !token.isEmpty else {
            throw AIEngineError.missingAPIKey
        }

        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Message: Encodable { let role: String; let content: String }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int
            let reasoning_effort: String?

            enum CodingKeys: String, CodingKey {
                case model, messages, temperature, max_tokens, reasoning_effort
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(model, forKey: .model)
                try c.encode(messages, forKey: .messages)
                try c.encode(temperature, forKey: .temperature)
                try c.encode(max_tokens, forKey: .max_tokens)
                // Drop the key entirely when nil so providers that don't understand
                // `reasoning_effort` aren't confused by an explicit null.
                try c.encodeIfPresent(reasoning_effort, forKey: .reasoning_effort)
            }
        }
        let trimmedEffort = reasoningEffort.trimmingCharacters(in: .whitespaces)
        let body = Body(
            model: model,
            messages: [Message(role: "user", content: prompt)],
            temperature: temperature,
            max_tokens: maxTokens,
            reasoning_effort: trimmedEffort.isEmpty ? nil : trimmedEffort
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AIEngineError.invalidResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(text.prefix(400))")
        }

        struct Choice: Decodable { let message: ChoiceMessage }
        struct ChoiceMessage: Decodable { let content: String }
        struct Response: Decodable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw AIEngineError.invalidResponse("No content in choices")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
