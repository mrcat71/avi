import Foundation

public enum AIEngineError: Error, CustomStringConvertible, LocalizedError {
    case noModelConfigured
    case missingAPIKey
    case subprocessFailed(exitCode: Int32, stderr: String)
    case invalidResponse(String)
    case cancelled

    public var description: String { errorDescription ?? "AI error" }

    public var errorDescription: String? {
        switch self {
        case .noModelConfigured:
            return "Set a model in Settings → AI Commit Messages."
        case .missingAPIKey:
            return "No API key stored. Save one in Settings → AI Commit Messages."
        case .subprocessFailed(let code, let stderr):
            return "AI command failed (exit \(code)): \(stderr.prefix(400))"
        case .invalidResponse(let msg):
            return "AI response invalid: \(msg)"
        case .cancelled:
            return "Generation cancelled."
        }
    }
}

protocol AIEngine: Sendable {
    func generate(prompt: String, model: String, temperature: Double, maxTokens: Int) async throws -> String
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

    init(config: AIConfig) {
        self.commandTemplate = config.commandTemplate
    }

    func generate(prompt: String, model: String, temperature: Double, maxTokens: Int) async throws -> String {
        let template = commandTemplate
            .replacingOccurrences(of: "${model}", with: model)

        // Write the prompt to a temp file so templates can reference ${prompt_file}.
        let tmpDir = FileManager.default.temporaryDirectory
        let promptURL = tmpDir.appendingPathComponent("avi-prompt-\(UUID().uuidString).txt")
        try Data(prompt.utf8).write(to: promptURL)
        defer { try? FileManager.default.removeItem(at: promptURL) }

        let rendered = template.replacingOccurrences(of: "${prompt_file}", with: promptURL.path)

        let argv = try shellSplit(rendered)
        guard let executable = argv.first else {
            throw AIEngineError.invalidResponse("Empty command")
        }

        // Resolve executable via PATH if it's a bare name.
        let resolved: String
        if executable.contains("/") {
            resolved = executable
        } else {
            resolved = resolveExecutable(executable) ?? executable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = Array(argv.dropFirst())
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    cont.resume()
                }
                do {
                    try process.run()
                    // Pipe prompt on stdin (in case the command doesn't use ${prompt_file}).
                    inPipe.fileHandleForWriting.write(Data(prompt.utf8))
                    try? inPipe.fileHandleForWriting.close()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        if process.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw AIEngineError.subprocessFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Minimal POSIX-ish shell split. Supports double-quoted strings and `\`-escapes
    /// inside them, plus plain whitespace splitting.
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

    private func resolveExecutable(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return str.isEmpty ? nil : str
        } catch {
            return nil
        }
    }
}

// MARK: - OpenAI-compatible backend

final class OpenAIAIEngine: AIEngine {
    let baseURL: String
    let token: String?

    @MainActor
    init(config: AIConfig) {
        self.baseURL = config.openAIBaseURL
        self.token = KeychainStore.getString(account: config.openAIKeychainItem)
    }

    func generate(prompt: String, model: String, temperature: Double, maxTokens: Int) async throws -> String {
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
        }
        let body = Body(
            model: model,
            messages: [Message(role: "user", content: prompt)],
            temperature: temperature,
            max_tokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
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
