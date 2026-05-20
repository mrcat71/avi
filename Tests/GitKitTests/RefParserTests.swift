import Foundation
import Testing
@testable import GitKit

@Suite struct RefParserTests {
    @Test func parsesBranchesRemoteBranchesAndTags() throws {
        let raw = [
            record("refs/heads/main", "1111", "origin/main", "*", "main subject"),
            record("refs/heads/feature", "2222", "", "", "feature subject"),
            record("refs/remotes/origin/HEAD", "1111", "", "", "origin head"),
            record("refs/remotes/origin/main", "1111", "", "", "origin main"),
            record("refs/tags/v1.0.0", "3333", "", "", "release"),
            "",
        ].joined(separator: "\u{0}")

        let refs = try RefParser.parse(Data(raw.utf8))

        #expect(refs.localBranches.map(\.name) == ["feature", "main"])
        #expect(refs.localBranches.first { $0.name == "main" }?.isCurrent == true)
        #expect(refs.localBranches.first { $0.name == "main" }?.upstream == "origin/main")
        #expect(refs.remoteBranches.map(\.name) == ["origin/main"])
        #expect(refs.tags.map(\.name) == ["v1.0.0"])
    }

    private func record(_ fields: String...) -> String {
        fields.joined(separator: "\u{1F}")
    }
}
