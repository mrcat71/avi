import Foundation
@testable import GitKit
import XCTest

final class GitFixtureTests: XCTestCase {
    func testFixtureDisablesGlobalMessageHooks() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.removeDirectory() }

        let hooks = fixture.url.appendingPathComponent(".git/test-global-hooks")
        let hook = hooks.appendingPathComponent("prepare-commit-msg")
        let message = fixture.url.appendingPathComponent(".git/test-message")
        let globalConfig = fixture.url.appendingPathComponent(".git/test-global-config")
        try fixture.write(".git/test-global-hooks/prepare-commit-msg", """
        #!/bin/sh
        printf '\\nSigned-off-by: Test Hook <hook@example.com>\\n' >> "$1"
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try fixture.write(".git/test-global-config", "[core]\n\thooksPath = \(hooks.path)\n")

        // Prove the controlled hook changes messages without making a commit.
        try fixture.write(".git/test-message", "original\n")
        try await fixture.git("-c", "core.hooksPath=\(hooks.path)", "hook", "run", "prepare-commit-msg", "--", message.path, "message")
        XCTAssertTrue(try String(contentsOf: message, encoding: .utf8).contains("Signed-off-by:"))

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = globalConfig.path
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        try fixture.write(".git/test-message", "original\n")
        let result = try await ProcessRunner.run(
            executable: fixture.gitURL,
            arguments: ["hook", "run", "--ignore-missing", "prepare-commit-msg", "--", message.path, "message"],
            workingDirectory: fixture.url,
            environment: environment
        )

        XCTAssertEqual(result.exitCode, 0, result.stderrString)
        XCTAssertEqual(try String(contentsOf: message, encoding: .utf8), "original\n")
    }
}
