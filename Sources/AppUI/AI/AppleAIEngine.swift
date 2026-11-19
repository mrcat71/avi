import Foundation
import GitKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (Apple Intelligence) through the FoundationModels
/// framework, on macOS 26 and later. The prompt never leaves the Mac.
enum AppleOnDeviceModel {
    /// `AIConfig.backend` value that selects this model.
    static let backendID = "apple"

    /// Shown where other backends show their model name.
    static let displayName = "on-device"

    /// The model's context window is a few thousand tokens shared by the
    /// prompt and the answer, so each diff it gets is cut to this many
    /// characters. That leaves room for the prompt text and a JSON plan.
    static let diffCharacterLimit = 6000

    /// Nil when the model can run here, otherwise why not, worded for Settings.
    static func unavailableReason() -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            if case .available = availability {
                return nil
            }
            guard case .unavailable(let reason) = availability else {
                return "Apple's on-device model is unavailable."
            }
            switch reason {
            case .deviceNotEligible:
                return "This Mac cannot run Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri."
            case .modelNotReady:
                return "Apple's on-device model is still downloading. Try again once it finishes."
            @unknown default:
                return "Apple's on-device model is unavailable."
            }
        }
        return "Apple's on-device model needs macOS 26 or later."
        #else
        return "This build of Avi was made without Apple's on-device model."
        #endif
    }
}

final class AppleAIEngine: AIEngine {
    let timeoutSeconds: Int

    init(config: AIConfig) {
        timeoutSeconds = max(5, config.timeoutSeconds)
    }

    func generate(
        prompt: String,
        model _: String,
        temperature: Double,
        maxTokens: Int,
        reasoningEffort _: String
    ) async throws -> String {
        if let reason = AppleOnDeviceModel.unavailableReason() {
            throw AIEngineError.noModelConfigured(reason)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await respond(to: prompt, temperature: temperature, maxTokens: maxTokens)
        }
        #endif
        // unavailableReason() already answered for older systems and builds.
        throw AIEngineError.noModelConfigured("Apple's on-device model is unavailable.")
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func respond(to prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        let startedAt = Date()
        let timeoutSeconds = timeoutSeconds
        let answer: String?
        do {
            answer = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    // A new session per request: Avi's prompts carry all their context.
                    let session = LanguageModelSession(
                        instructions: "Answer exactly as the prompt asks, with no preamble or commentary."
                    )
                    let options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)
                    return try await session.respond(to: prompt, options: options).content
                }
                group.addTask {
                    try await Task.safeSleep(for: .seconds(timeoutSeconds))
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
        } catch is CancellationError {
            throw AIEngineError.cancelled
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                throw AIEngineError.generationFailed(
                    "The changes are too large for Apple's on-device model. Stage fewer files, or use another backend."
                )
            }
            throw AIEngineError.generationFailed(error.localizedDescription)
        }

        guard let answer else {
            throw AIEngineError.timedOut(AIRunResult(
                provider: AppleOnDeviceModel.backendID,
                resolvedExecutable: "",
                argv: [],
                model: AppleOnDeviceModel.displayName,
                exitCode: nil,
                stdout: "",
                stderr: "",
                durationMS: Int(Date().timeIntervalSince(startedAt) * 1000),
                timedOut: true
            ))
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}
