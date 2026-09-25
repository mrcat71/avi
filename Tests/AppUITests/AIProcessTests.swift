@testable import AppUI
import Foundation
import Testing

/// The AI preflight and the command backend wait for a subprocess next to a
/// timeout that sleeps; the sleep is cancelled when the process exits first.
struct AIProcessTests {
    @Test func runTestReadsTheVersionBanner() async throws {
        let tool = try makeScript("#!/bin/sh\necho \"tool 1.2.3\"\n")
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }

        let result = await AICLIValidator.runTest(executable: tool.path)

        #expect(result.exitCode == 0)
        #expect(result.stdoutFirstLine == "tool 1.2.3")
        #expect(!result.timedOut)
    }

    @Test(.timeLimit(.minutes(1)))
    func runTestGivesUpOnAHungTool() async throws {
        let tool = try makeScript("#!/bin/sh\nexec sleep 60\n")
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }

        let result = await AICLIValidator.runTest(executable: tool.path)

        #expect(result.timedOut)
        #expect(result.exitCode == nil)
    }

    @Test func commandBackendReturnsTheCommandOutput() async throws {
        let engine = CommandAIEngine(config: AIConfig(commandTemplate: "/bin/cat"))

        let output = try await engine.generate(
            prompt: "feat: add x\n",
            model: "m",
            temperature: 0,
            maxTokens: 10,
            reasoningEffort: ""
        )

        #expect(output == "feat: add x")
    }

    @Test func waitForExitReturnsForAProcessThatAlreadyExited() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()

        await process.waitForExit()

        #expect(process.terminationStatus == 0)
    }

    private func makeScript(_ text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("avi-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tool")
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
