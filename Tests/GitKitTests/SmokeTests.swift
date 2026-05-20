import Testing
@testable import GitKit

@Test func versionIsSet() {
    #expect(GitKit.version == "0.0.1")
}
