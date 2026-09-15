import Foundation
@testable import GitKit
import XCTest

/// The recording executable never invokes Git or changes a repository.
final class RewordExecutionTests: XCTestCase, @unchecked Sendable {
    func testHEADRewordUsesMessageOnlyAmendForBothObjectFormats() async throws {
        for length in [40, 64] {
            let head = String(repeating: "a", count: length)
            let fixture = try Fixture(head: head)
            let message = "fix: revised subject\n\nKeep the staged work separate."
            try await fixture.provider.rebaseSingle(commit: head, action: .reword(newMessage: message), in: fixture.root)
            XCTAssertEqual(try fixture.commands(), [
                ["rev-parse", "--verify", "HEAD^{commit}"],
                ["commit", "--amend", "--only", "--allow-empty", "-m", message]
            ])
        }
    }

    func testHistoricalCommitUsesSelectedOIDNotCurrentHEAD() async throws {
        let fixture = try Fixture()
        try fixture.setListing("\(oldest) \(parent)\n\(middle) \(oldest)\n\(head) \(middle)\n")
        try await fixture.provider.rebaseSingle(commit: oldest, action: .reword(newMessage: "Reword oldest"), in: fixture.root)
        let commands = try fixture.commands()
        XCTAssertEqual(commands.count, 3)
        XCTAssertEqual(commands[1], ["rev-list", "--reverse", "--topo-order", "--parents", "\(oldest)^..HEAD"])
        XCTAssertEqual(commands[2], rebaseCommand(for: oldest))
        XCTAssertFalse(commands.contains { $0.first == "commit" })
    }

    func testForeignBranchCommitNeverAmendsHEAD() async throws {
        let fixture = try Fixture()
        try fixture.setListing("\(head) \(parent)\n")
        do {
            try await fixture.provider.rebaseSingle(commit: oldest, action: .reword(newMessage: "Foreign commit"), in: fixture.root)
            XCTFail("A commit outside the HEAD replay range must be rejected")
        } catch let error as GitError {
            guard case .invalidInput = error else { return XCTFail("Expected a rejected replay plan") }
        }
        XCTAssertEqual(try fixture.commands().map { $0[0] }, ["rev-parse", "rev-list"])
    }

    func testHEADReadFailureStopsWithoutFallingBackToAmend() async throws {
        let fixture = try Fixture()
        try fixture.setFlag("head-read-failed")
        do {
            try await fixture.provider.rebaseSingle(commit: head, action: .reword(newMessage: "Updated"), in: fixture.root)
            XCTFail("The HEAD read failure must propagate")
        } catch let error as GitError {
            guard case let .commandFailed(_, exitCode, _) = error else { return XCTFail("Expected a command error") }
            XCTAssertEqual(exitCode, 128)
        }
        XCTAssertEqual(try fixture.commands().count, 1)
    }

    func testMalformedHEADStopsBeforeMutation() async throws {
        for output in ["", "HEAD", "abcd", "\(head)\n\(oldest)"] {
            let fixture = try Fixture(head: output)
            do {
                try await fixture.provider.rebaseSingle(commit: head, action: .reword(newMessage: "Updated"), in: fixture.root)
                XCTFail("Malformed HEAD output must be rejected")
            } catch let error as GitError {
                guard case .parseFailed = error else { return XCTFail("Expected a parse error") }
            }
            XCTAssertEqual(try fixture.commands().count, 1)
        }
    }

    func testMutableRefsAndEmptyMessagesAreRejectedBeforeAnyCommand() async throws {
        let fixture = try Fixture()
        for target in ["HEAD", "main", "--all", "abcd", "\(head)\npick \(oldest)"] {
            do {
                try await fixture.provider.rebaseSingle(commit: target, action: .reword(newMessage: "Updated"), in: fixture.root)
                XCTFail("Reword must require an immutable full commit ID")
            } catch let error as GitError {
                guard case .invalidInput = error else { return XCTFail("Expected invalid input") }
            }
        }
        do {
            try await fixture.provider.rebaseSingle(commit: head, action: .reword(newMessage: " \n"), in: fixture.root)
            XCTFail("An empty message must be rejected")
        } catch let error as GitError {
            guard case .invalidInput = error else { return XCTFail("Expected invalid input") }
        }
        XCTAssertEqual(try fixture.commands(), [])
    }

    func testHEADCheckAndRewriteShareOneQueueSlot() async throws {
        let fixture = try Fixture()
        try fixture.setFlag("delay-head-read")
        let reword = Task {
            try await fixture.provider.rebaseSingle(commit: head, action: .reword(newMessage: "Updated"), in: fixture.root)
        }
        defer { reword.cancel() }
        for _ in 0 ..< 200 {
            if FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("reading-head").path) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("reading-head").path))
        let otherProvider = CLIGitProvider(gitURL: fixture.executable)
        let status = Task { try await otherProvider.status(in: fixture.root) }
        defer { status.cancel() }
        try await reword.value
        _ = try await status.value
        XCTAssertEqual(try fixture.commands().map { $0[0] }, ["rev-parse", "commit", "status"])
    }

    func testFailedAmendIsNotRetriedAndReleasesQueue() async throws {
        let fixture = try Fixture()
        try fixture.setFlag("amend-failed")
        do {
            try await fixture.provider.rebaseSingle(commit: head, action: .reword(newMessage: "Updated"), in: fixture.root)
            XCTFail("The amend failure must propagate")
        } catch let error as GitError {
            guard case let .commandFailed(_, exitCode, _) = error else { return XCTFail("Expected a command error") }
            XCTAssertEqual(exitCode, 1)
        }
        _ = try await fixture.provider.status(in: fixture.root)
        XCTAssertEqual(try fixture.commands().map { $0[0] }, ["rev-parse", "commit", "status"])
    }

    func testEditStillUsesInteractiveRebase() async throws {
        let fixture = try Fixture()
        try fixture.setListing("\(head) \(parent)\n")
        try await fixture.provider.rebaseSingle(commit: head, action: .edit, in: fixture.root)
        XCTAssertEqual(try fixture.commands(), [
            ["rev-list", "--reverse", "--topo-order", "--parents", "\(head)^..HEAD"],
            rebaseCommand(for: head)
        ])
    }

    private struct Fixture: Sendable {
        let root: URL
        let executable: URL
        var provider: CLIGitProvider {
            CLIGitProvider(gitURL: executable)
        }

        init(head: String = String(repeating: "a", count: 40)) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-reword-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            executable = root.appendingPathComponent("recording-git")
            try head.write(to: root.appendingPathComponent("head"), atomically: true, encoding: .utf8)
            try "".write(to: root.appendingPathComponent("arguments"), atomically: true, encoding: .utf8)
            let script = """
            #!/bin/sh
            set -eu
            printf '%s\\000' "$@" >> arguments
            printf '\\000' >> arguments
            case "$1" in
              rev-parse)
                if [ -e head-read-failed ]; then printf 'HEAD unavailable' >&2; exit 128; fi
                if [ -e delay-head-read ]; then touch reading-head; sleep 0.2; fi
                cat head
                ;;
              rev-list) cat listing ;;
              commit)
                if [ -e amend-failed ]; then printf "Unable to create '.git/index.lock': File exists" >&2; exit 1; fi
                ;;
              -c) ;;
              status) printf '# branch.oid %s\\000# branch.head main\\000' "$(cat head)" ;;
              *) printf 'unexpected fake command' >&2; exit 99 ;;
            esac
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func setListing(_ listing: String) throws {
            try listing.write(to: root.appendingPathComponent("listing"), atomically: true, encoding: .utf8)
        }

        func setFlag(_ name: String) throws {
            try "".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        func commands() throws -> [[String]] {
            try String(contentsOf: root.appendingPathComponent("arguments"), encoding: .utf8)
                .components(separatedBy: "\0\0").filter { !$0.isEmpty }
                .map { $0.components(separatedBy: "\0") }
        }
    }
}

private let head = String(repeating: "a", count: 40)
private let oldest = String(repeating: "b", count: 40)
private let middle = String(repeating: "c", count: 40)
private let parent = String(repeating: "d", count: 40)

private func rebaseCommand(for oid: String) -> [String] {
    ["-c", "core.abbrev=\(oid.count)", "-c", "rebase.abbreviateCommands=false", "rebase", "-i",
     "--no-autosquash", "--no-rebase-merges", "--autostash", "\(oid)^"]
}
