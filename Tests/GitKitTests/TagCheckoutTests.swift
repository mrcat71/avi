import Foundation
@testable import GitKit
import XCTest

/// A recording executable substitutes for Git; no working tree or HEAD is changed.
final class TagCheckoutTests: XCTestCase, @unchecked Sendable {
    func testAnnotatedTagUsesReviewedTarget() async throws {
        let fixture = try Fixture()
        let target = String(repeating: "b", count: 40)
        let ref = GitReference(name: "release", fullName: "refs/tags/release",
                               oid: String(repeating: "a", count: 40), kind: .tag, peeledOID: target)
        try await CLIGitProvider(gitURL: fixture.executable).checkout(ref, in: fixture.root)
        XCTAssertEqual(try fixture.arguments(), ["switch", "--detach", "--", target])
    }

    func testLightweightTagDoesNotPassNameAsAnOptionOrAmbiguousRef() async throws {
        let fixture = try Fixture()
        let target = String(repeating: "c", count: 40)
        let ref = GitReference(name: "--discard-changes", fullName: "refs/tags/--discard-changes",
                               oid: target, kind: .tag)
        try await CLIGitProvider(gitURL: fixture.executable).checkout(ref, in: fixture.root)
        XCTAssertEqual(try fixture.arguments(), ["switch", "--detach", "--", target])
    }

    func testRefusalIsPropagatedWithoutRetryStashOrForce() async throws {
        let fixture = try Fixture(refuse: true)
        let target = String(repeating: "d", count: 40)
        let ref = GitReference(name: "v1", fullName: "refs/tags/v1", oid: target, kind: .tag)
        do {
            try await CLIGitProvider(gitURL: fixture.executable).checkout(ref, in: fixture.root)
            XCTFail("Checkout must propagate Git's refusal")
        } catch let error as GitError {
            guard case let .commandFailed(_, code, stderr) = error else {
                return XCTFail("Expected the original command failure")
            }
            XCTAssertEqual(code, 1)
            XCTAssertTrue(stderr.contains("would be overwritten by checkout"))
        }
        XCTAssertEqual(try fixture.arguments(), ["switch", "--detach", "--", target])
    }

    private struct Fixture {
        let root: URL
        let executable: URL

        init(refuse: Bool = false) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("avi-tag-checkout-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            executable = root.appendingPathComponent("recording-git")
            let script = """
            #!/bin/sh
            printf '%s\\n' "$@" >> arguments
            if [ \(refuse ? "1" : "0") = 1 ]; then
                printf 'error: Your local changes would be overwritten by checkout\\n' >&2
                exit 1
            fi
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func arguments() throws -> [String] {
            try String(contentsOf: root.appendingPathComponent("arguments"), encoding: .utf8)
                .split(separator: "\n").map(String.init)
        }
    }
}
