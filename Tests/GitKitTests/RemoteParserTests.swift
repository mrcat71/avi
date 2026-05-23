@testable import GitKit
import Testing

struct RemoteParserTests {
    @Test func parsesRemoteVerboseOutput() {
        let remotes = RemoteParser.parse("""
        origin  git@example.com:org/repo.git (fetch)
        origin  git@example.com:org/repo.git (push)
        backup  https://example.com/repo.git (fetch)
        backup  https://example.com/repo.git (push)
        """)

        #expect(remotes == [
            GitRemote(name: "backup", fetchURL: "https://example.com/repo.git", pushURL: "https://example.com/repo.git"),
            GitRemote(name: "origin", fetchURL: "git@example.com:org/repo.git", pushURL: "git@example.com:org/repo.git")
        ])
    }

    @Test func emptyOutputYieldsNoRemotes() {
        #expect(RemoteParser.parse("").isEmpty)
    }
}
