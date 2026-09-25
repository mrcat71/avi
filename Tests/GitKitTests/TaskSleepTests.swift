import Foundation
import GitKit
import Testing

struct TaskSleepTests {
    @Test func waitsForTheDuration() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        try await Task.safeSleep(for: .milliseconds(50))
        #expect(clock.now - start >= .milliseconds(50))
    }

    @Test func throwsWhenCancelled() async {
        let sleeper = Task { try await Task.safeSleep(for: .seconds(30)) }
        sleeper.cancel()
        await #expect(throws: CancellationError.self) {
            try await sleeper.value
        }
    }

    /// `Task.sleep(for:)` and `Clock.sleep(for:)` crash release builds made with
    /// Swift 6.2 and 6.3 once two modules call them; see `Task.safeSleep(for:)`.
    @Test func sourcesUseSafeSleep() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // GitKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !$0.path.hasSuffix("Concurrency/TaskSleep.swift") } ?? []
        #expect(!files.isEmpty, "No Swift sources under \(sources.path)")

        let genericSleep = try Regex(#"\.sleep\(\s*for:"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: genericSleep) {
                let line = text[..<match.range.lowerBound].count { $0 == "\n" } + 1
                Issue.record("\(file.path):\(line) calls sleep(for:). Use Task.safeSleep(for:) instead.")
            }
        }
    }
}
