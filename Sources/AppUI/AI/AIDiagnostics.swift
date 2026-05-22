import Foundation

/// Carries the full execution trace of an AI generation attempt so the UI
/// can render it as a debug disclosure when something goes wrong.
public struct AIRunResult: Sendable, Equatable {
    public let provider: String              // "command" | "openai"
    public let resolvedExecutable: String
    public let argv: [String]
    public let model: String
    public let exitCode: Int32?              // nil = never terminated (timed out)
    public let stdout: String
    public let stderr: String
    public let durationMS: Int
    public let timedOut: Bool

    public init(
        provider: String,
        resolvedExecutable: String,
        argv: [String],
        model: String,
        exitCode: Int32?,
        stdout: String,
        stderr: String,
        durationMS: Int,
        timedOut: Bool
    ) {
        self.provider = provider
        self.resolvedExecutable = resolvedExecutable
        self.argv = argv
        self.model = model
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMS = durationMS
        self.timedOut = timedOut
    }

    public var commandLine: String {
        argv.joined(separator: " ")
    }
}

/// UI-facing error envelope. Either has a `runResult` (subprocess details
/// to show in a Debug disclosure) or just a short message.
public struct AIErrorDetail: Sendable, Equatable {
    public let title: String
    public let message: String
    public let runResult: AIRunResult?

    public init(title: String, message: String, runResult: AIRunResult? = nil) {
        self.title = title
        self.message = message
        self.runResult = runResult
    }
}

/// Result of generation that's been parsed into subject + body but not yet
/// applied to the commit form fields. The user must explicitly accept it.
public struct AIPendingPreview: Sendable, Equatable {
    public let subject: String
    public let body: String
    public let result: AIRunResult

    public init(subject: String, body: String, result: AIRunResult) {
        self.subject = subject
        self.body = body
        self.result = result
    }

    public var combined: String {
        body.isEmpty ? subject : subject + "\n\n" + body
    }
}
