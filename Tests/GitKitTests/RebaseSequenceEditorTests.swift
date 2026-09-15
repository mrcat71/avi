import Foundation
@testable import GitKit
import Testing

struct RebaseSequenceEditorTests {
    @Test func refusesChangedLiveSequenceWithoutOverwritingIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("avi-todo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("editor.sh")
        let expected = directory.appendingPathComponent("expected")
        let live = directory.appendingPathComponent("live")
        let oid = String(repeating: "a", count: 40)
        let extra = String(repeating: "b", count: 40)
        try LinearRebasePlan.sequenceEditorScript.write(to: script, atomically: true, encoding: .utf8)
        try "reword \(oid)\n".write(to: expected, atomically: true, encoding: .utf8)
        let unexpected = "pick \(oid) subject\npick \(extra) new descendant\n"
        try unexpected.write(to: live, atomically: true, encoding: .utf8)
        let result = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [script.path, expected.path, live.path])
        #expect(result.exitCode != 0)
        #expect(try String(contentsOf: live, encoding: .utf8) == unexpected)

        try "pick \(oid) subject\n# comment\n".write(to: live, atomically: true, encoding: .utf8)
        let accepted = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [script.path, expected.path, live.path])
        #expect(accepted.exitCode == 0)
        #expect(try String(contentsOf: live, encoding: .utf8) == "reword \(oid)\n")
    }
}
