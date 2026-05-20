import Foundation
@testable import GitKit

/// A throwaway git repository under /tmp for tests. All git invocations and
/// file writes are confined to a unique temp directory.
struct GitFixture: Sendable {
    let url: URL
    let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    static func make() async throws -> GitFixture {
        let base = URL(fileURLWithPath: "/tmp").appendingPathComponent("avi-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let fixture = GitFixture(url: base)
        try await fixture.git("init", "-q")
        try await fixture.git("config", "user.email", "test@example.com")
        try await fixture.git("config", "user.name", "Avi Test")
        try await fixture.git("config", "commit.gpgsign", "false")
        return fixture
    }

    @discardableResult
    func git(_ arguments: String...) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: gitURL,
            arguments: Array(arguments),
            workingDirectory: url
        )
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(
                command: "git " + arguments.joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderrString
            )
        }
        return result
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Creates a fixture repo, runs the test body against it, and cleans up after.
func withTempRepo(_ body: (GitFixture) async throws -> Void) async throws {
    let fixture = try await GitFixture.make()
    defer { fixture.removeDirectory() }
    try await body(fixture)
}
