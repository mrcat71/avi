import Foundation
@testable import GitKit
import Testing

struct RefParserTests {
    @Test func parsesBranchesRemoteBranchesAndTags() throws {
        let raw = [
            record("refs/heads/main", "1111", "origin/main", "[ahead 2, behind 1]", "*", "main subject", "", ""),
            record("refs/heads/feature", "2222", "", "", "", "feature subject", "", ""),
            record("refs/remotes/origin/HEAD", "1111", "", "", "", "origin head", "", ""),
            record("refs/remotes/origin/main", "1111", "", "", "", "origin main", "", ""),
            record("refs/tags/v1.0.0", "3333", "", "", "", "release", "2024-01-01T12:00:00+00:00", "release notes"),
            ""
        ].joined(separator: "\u{0}")

        let refs = try RefParser.parse(Data(raw.utf8))

        #expect(refs.localBranches.map(\.name) == ["feature", "main"])
        let main = refs.localBranches.first { $0.name == "main" }
        #expect(main?.isCurrent == true)
        #expect(main?.upstream == "origin/main")
        #expect(main?.ahead == 2)
        #expect(main?.behind == 1)
        #expect(main?.isUpstreamGone == false)
        #expect(refs.remoteBranches.map(\.name) == ["origin/main"])
        #expect(refs.tags.map(\.name) == ["v1.0.0"])

        let tag = refs.tags.first
        #expect(tag?.annotatedMessage == "release notes")
        #expect(tag?.taggerDate != nil)
    }

    @Test func parsesGoneUpstream() throws {
        let raw = [
            record("refs/heads/feature", "2222", "origin/feature", "[gone]", "", "feature subject", "", ""),
            ""
        ].joined(separator: "\u{0}")

        let refs = try RefParser.parse(Data(raw.utf8))
        let feature = refs.localBranches.first
        #expect(feature?.isUpstreamGone == true)
        #expect(feature?.ahead == nil)
        #expect(feature?.behind == nil)
    }

    @Test func parsesAheadOnlyAndBehindOnly() throws {
        let raw = [
            record("refs/heads/a", "aaaa", "origin/a", "[ahead 5]", "", "a", "", ""),
            record("refs/heads/b", "bbbb", "origin/b", "[behind 3]", "", "b", "", ""),
            ""
        ].joined(separator: "\u{0}")

        let refs = try RefParser.parse(Data(raw.utf8))
        let a = refs.localBranches.first { $0.name == "a" }
        let b = refs.localBranches.first { $0.name == "b" }
        #expect(a?.ahead == 5)
        #expect(a?.behind == nil)
        #expect(b?.ahead == nil)
        #expect(b?.behind == 3)
    }

    @Test func lightweightTagHasNoAnnotation() throws {
        let raw = [
            record("refs/tags/v0.1", "1111", "", "", "", "lightweight", "", ""),
            ""
        ].joined(separator: "\u{0}")

        let refs = try RefParser.parse(Data(raw.utf8))
        let tag = refs.tags.first
        #expect(tag?.taggerDate == nil)
        #expect(tag?.annotatedMessage == nil)
    }

    @Test func parsesEmptyTracking() throws {
        let raw = [
            record("refs/heads/main", "1111", "", "", "*", "subject", "", ""),
            ""
        ].joined(separator: "\u{0}")

        let refs = try RefParser.parse(Data(raw.utf8))
        let main = refs.localBranches.first
        #expect(main?.ahead == nil)
        #expect(main?.behind == nil)
        #expect(main?.isUpstreamGone == false)
    }

    private func record(_ fields: String...) -> String {
        fields.joined(separator: "\u{1F}")
    }
}
