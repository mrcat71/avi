import Foundation

public struct AIValidationReport: Equatable, Sendable {
    public let isValid: Bool
    public let messages: [String]
    public let resolvedExecutable: String?
    public let detectedVersion: String?
}

/// Pre-flight checks for AI generation. Run from Settings ("Re-check") and
/// from `RepositoryStore.generateCommitMessage` before launching a subprocess.
public enum AICLIValidator {
    public static func validate(_ config: AIConfig) async -> AIValidationReport {
        switch config.backend {
        case "openai":
            return validateOpenAI(config)
        default:
            return await validateCommand(config)
        }
    }

    // MARK: - Command backend

    private static func validateCommand(_ config: AIConfig) async -> AIValidationReport {
        var messages: [String] = []
        var resolvedPath: String?
        var detectedVersion: String?

        if config.model.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append("Set a model in Settings → AI Commit Messages.")
        }

        let template = config.commandTemplate.trimmingCharacters(in: .whitespaces)
        if template.isEmpty {
            messages.append("Command template is empty.")
            return AIValidationReport(isValid: false, messages: messages, resolvedExecutable: nil, detectedVersion: nil)
        }

        // Pull the binary name out of the template. We only inspect the first token.
        let withoutPlaceholders = template
            .replacingOccurrences(of: "${model}", with: "MODEL")
            .replacingOccurrences(of: "${prompt_file}", with: "PROMPT")
        let parts = withoutPlaceholders.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let firstRaw = parts.first else {
            messages.append("Command template has no executable.")
            return AIValidationReport(isValid: false, messages: messages, resolvedExecutable: nil, detectedVersion: nil)
        }
        let first = String(firstRaw)

        if first.contains("/") {
            if FileManager.default.fileExists(atPath: first) {
                resolvedPath = first
                if !FileManager.default.isExecutableFile(atPath: first) {
                    messages.append("Binary is not executable: \(first)")
                }
            } else {
                messages.append("Binary not found at \(first).")
            }
        } else if let found = resolveExecutable(first) {
            resolvedPath = found
        } else {
            messages.append("Binary not found in PATH: \(first). Install it or override the path in Settings → External Tools.")
        }

        // If we resolved a binary, probe for a version banner (best-effort, 5s budget).
        if let path = resolvedPath {
            detectedVersion = await probeVersion(executable: path)
        }

        return AIValidationReport(
            isValid: messages.isEmpty,
            messages: messages,
            resolvedExecutable: resolvedPath,
            detectedVersion: detectedVersion
        )
    }

    private static func validateOpenAI(_ config: AIConfig) -> AIValidationReport {
        var messages: [String] = []
        if URL(string: config.openAIBaseURL) == nil {
            messages.append("Base URL is invalid: \(config.openAIBaseURL).")
        }
        if config.model.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append("Set a model in Settings → AI Commit Messages.")
        }
        let token = KeychainStore.getString(account: config.openAIKeychainItem) ?? ""
        if token.isEmpty {
            messages.append("No API key stored. Save one in Settings → AI Commit Messages.")
        }
        return AIValidationReport(
            isValid: messages.isEmpty,
            messages: messages,
            resolvedExecutable: nil,
            detectedVersion: nil
        )
    }

    // MARK: - Tool test

    public struct TestResult: Sendable, Equatable {
        public let exitCode: Int32?
        public let stdoutFirstLine: String
        public let stderrFirstLine: String
        public let durationMS: Int
        public let timedOut: Bool
    }

    /// Run `<executable> --version` (or fallbacks) with a 5s budget. Used by the
    /// External Tools "Test" button to surface why a CLI isn't responding.
    public static func runTest(executable: String) async -> TestResult {
        let candidates = [["--version"], ["version"], ["-V"], ["-v"]]
        let start = Date()
        for args in candidates {
            let result = await runOnce(executable: executable, arguments: args, timeoutSeconds: 5)
            if result.exitCode == 0, !result.stdoutFirstLine.isEmpty {
                return TestResult(
                    exitCode: 0,
                    stdoutFirstLine: result.stdoutFirstLine,
                    stderrFirstLine: result.stderrFirstLine,
                    durationMS: Int(Date().timeIntervalSince(start) * 1000),
                    timedOut: false
                )
            }
            if result.timedOut {
                return TestResult(
                    exitCode: nil,
                    stdoutFirstLine: result.stdoutFirstLine,
                    stderrFirstLine: result.stderrFirstLine,
                    durationMS: Int(Date().timeIntervalSince(start) * 1000),
                    timedOut: true
                )
            }
        }
        // None of the variants produced exit 0. Return the last one we tried.
        let final = await runOnce(executable: executable, arguments: ["--version"], timeoutSeconds: 5)
        return TestResult(
            exitCode: final.exitCode,
            stdoutFirstLine: final.stdoutFirstLine,
            stderrFirstLine: final.stderrFirstLine,
            durationMS: Int(Date().timeIntervalSince(start) * 1000),
            timedOut: final.timedOut
        )
    }

    // MARK: - Internal subprocess helpers

    private static func probeVersion(executable: String) async -> String? {
        let r = await runTest(executable: executable)
        if r.exitCode == 0, !r.stdoutFirstLine.isEmpty { return r.stdoutFirstLine }
        return nil
    }

    private struct OneRun {
        let exitCode: Int32?
        let stdoutFirstLine: String
        let stderrFirstLine: String
        let timedOut: Bool
    }

    private static func runOnce(executable: String, arguments: [String], timeoutSeconds: Int) async -> OneRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        guard (try? process.run()) != nil else {
            return OneRun(exitCode: nil, stdoutFirstLine: "", stderrFirstLine: "could not launch", timedOut: false)
        }

        let outcome = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in cont.resume() }
                    if !process.isRunning {
                        process.terminationHandler = nil
                        cont.resume()
                    }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if process.isRunning {
            process.terminate()
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let outLine = String(data: outData, encoding: .utf8)?
            .split(separator: "\n").first.map(String.init) ?? ""
        let errLine = String(data: errData, encoding: .utf8)?
            .split(separator: "\n").first.map(String.init) ?? ""

        return OneRun(
            exitCode: outcome ? process.terminationStatus : nil,
            stdoutFirstLine: outLine,
            stderrFirstLine: errLine,
            timedOut: !outcome
        )
    }

    private static func resolveExecutable(_ name: String) -> String? {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [name]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        if (try? which.run()) != nil {
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/.cargo/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
