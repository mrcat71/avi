import Foundation
@testable import GitKit
import XCTest

/// Uses a recording executable, not Git. No repository or commit is created.
final class StagedSplitExecutionTests: XCTestCase, @unchecked Sendable {
    func testSplitReservesQueueAcrossEveryStep() async throws {
        let fixture = try Fixture()
        let provider = CLIGitProvider(gitURL: fixture.executable)
        let split = Task { try await provider.splitStagedChanges(fixture.plan, in: fixture.root) }
        for _ in 0 ..< 200 {
            if FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("started").path) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let otherProvider = CLIGitProvider(gitURL: fixture.executable)
        let read = Task { try await otherProvider.status(in: fixture.root) }
        try await split.value
        _ = try await read.value
        let commands = try fixture.commands()
        XCTAssertEqual(commands.filter { $0.hasPrefix("commit ") }.count, 2)
        XCTAssertTrue(commands.contains("--literal-pathspecs add -- [draft]*.swift"))
        XCTAssertTrue(commands.last?.hasPrefix("status ") == true)
        XCTAssertEqual(commands.filter { $0.hasPrefix("status ") }.count, 2)
    }

    func testStalePreviewNeverMutates() async throws {
        let fixture = try Fixture()
        let provider = CLIGitProvider(gitURL: fixture.executable)
        let stale = StagedCommitPlan(groups: fixture.plan.groups, expectedDiff: "old")
        do {
            try await provider.splitStagedChanges(stale, in: fixture.root)
            XCTFail("A stale preview must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Generate a new split preview"))
        }
        XCTAssertEqual(try fixture.commands().count, 2)
    }

    func testFailureStopsWithoutRetryAndReleasesQueue() async throws {
        let fixture = try Fixture(failSecondCommit: true)
        let provider = CLIGitProvider(gitURL: fixture.executable)
        do {
            try await provider.splitStagedChanges(fixture.plan, in: fixture.root)
            XCTFail("The simulated second commit must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("1 completed commit(s)"))
        }
        _ = try await provider.status(in: fixture.root)
        let commands = try fixture.commands()
        XCTAssertEqual(commands.filter { $0.hasPrefix("commit ") }.count, 2)
        XCTAssertEqual(commands.filter { $0.hasPrefix("restore ") }.count, 1)
        XCTAssertTrue(commands.last?.hasPrefix("status ") == true)
    }

    func testUnfinishedRebaseNeverMutates() async throws {
        let fixture = try Fixture()
        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent(".git/rebase-merge"),
            withIntermediateDirectories: true
        )
        let provider = CLIGitProvider(gitURL: fixture.executable)
        do {
            try await provider.splitStagedChanges(fixture.plan, in: fixture.root)
            XCTFail("An unfinished operation must block splitting")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Finish or abort"))
        }
        XCTAssertFalse(try fixture.commands().contains { $0.hasPrefix("restore ") || $0.hasPrefix("commit ") })
    }

    private struct Fixture: Sendable {
        let root: URL
        let executable: URL
        let plan = StagedCommitPlan(groups: [
            .init(files: ["[draft]*.swift"], message: "first"),
            .init(files: ["b.swift"], message: "second")
        ], expectedDiff: "reviewed")

        init(failSecondCommit: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-staged-split-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            executable = root.appendingPathComponent("recording-git")
            let script = """
            #!/bin/sh
            printf '%s\\n' "$*" >> commands
            case "$1" in
              status)
                if [ ! -e started ]; then touch started; sleep 0.2; fi
                printf '1 M. N... 100644 100644 100644 aaaaaaa bbbbbbb [draft]*.swift\\0001 M. N... 100644 100644 100644 aaaaaaa bbbbbbb b.swift\\000'
                ;;
              diff) printf reviewed ;;
              rev-parse)
                if [ "$2" = --verify ]; then exit 1; fi
                printf '.git/%s\\n' "$3"
                ;;
              commit)
                if [ "$3" = second ] && [ \(failSecondCommit ? "1" : "0") = 1 ]; then
                  printf 'simulated hook failure' >&2
                  exit 1
                fi
                ;;
              restore|--literal-pathspecs) ;;
              *) printf 'unexpected fake command' >&2; exit 99 ;;
            esac
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func commands() throws -> [String] {
            try String(contentsOf: root.appendingPathComponent("commands"), encoding: .utf8)
                .split(separator: "\n").map(String.init)
        }
    }
}
