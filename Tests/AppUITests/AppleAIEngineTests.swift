@testable import AppUI
import Foundation
import Testing

struct AppleAIEngineTests {
    @Test(arguments: [
        ("command", false, "gpt-6.1-luna", nil as Int?),
        ("openai", false, "gpt-6.1-luna", nil),
        ("apple", true, "on-device", AppleOnDeviceModel.diffCharacterLimit)
    ])
    func backendDecidesModelAndDiffLimit(backend: String, usesApple: Bool, displayModel: String, diffLimit: Int?) {
        let config = AIConfig(backend: backend)
        #expect(config.usesAppleModel == usesApple)
        #expect(config.displayModel == displayModel)
        #expect(config.promptDiffLimit == diffLimit)
    }

    @Test func configDecodesAppleBackend() throws {
        let decoded = try JSONDecoder().decode(AIConfig.self, from: Data(#"{"backend": "apple"}"#.utf8))
        #expect(decoded.backend == "apple")
        #expect(decoded.usesAppleModel)
    }

    @MainActor
    @Test func factoryMakesAppleEngine() {
        #expect(AIEngineFactory.make(config: AIConfig(backend: "apple")) is AppleAIEngine)
    }

    /// Whether the model runs depends on the Mac, so the check must agree
    /// with the availability it reports rather than with a fixed answer.
    @Test func validatorReportsModelAvailability() async {
        let report = await AICLIValidator.validate(AIConfig(backend: "apple"), executables: [:])
        let reason = AppleOnDeviceModel.unavailableReason()
        #expect(report.isValid == (reason == nil))
        #expect(report.messages == (reason.map { [$0] } ?? []))
    }

    @Test func unavailableModelFailsWithItsReason() async {
        guard let reason = AppleOnDeviceModel.unavailableReason() else {
            return // The model runs here; a real generation is too slow for a unit test.
        }
        let error = await #expect(throws: AIEngineError.self) {
            _ = try await AppleAIEngine(config: AIConfig(backend: "apple"))
                .generate(prompt: "hi", model: "", temperature: 0.2, maxTokens: 100, reasoningEffort: "")
        }
        #expect(error?.errorDescription == reason)
    }
}

struct PromptDiffLimitTests {
    private func context(diff: String) -> PromptContext {
        PromptContext(
            stagedDiff: diff, branch: "", files: [], repo: "", model: "",
            lowLimit: 50, highLimit: 72, guideLine: 72,
            commitDiff: diff
        )
    }

    @Test func diffsPastTheLimitAreCutAndMarked() {
        let rendered = PromptRenderer.render(
            template: "${target}|${staged_diff}|${commit_diff}",
            context: context(diff: "abcdefghij"),
            diffLimit: 4
        )
        let cut = "abcd\n[diff truncated]\n"
        #expect(rendered == "\(cut)|\(cut)|\(cut)")
    }

    @Test func diffsWithinTheLimitOrWithoutOneStayWhole() {
        let ctx = context(diff: "abcd")
        #expect(PromptRenderer.render(template: "${target}", context: ctx, diffLimit: 4) == "abcd")
        #expect(PromptRenderer.render(template: "${target}", context: ctx) == "abcd")
    }
}
