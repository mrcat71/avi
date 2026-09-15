@testable import GitKit
import Testing

@Test func versionIsSet() {
    #expect(GitKit.version == "0.2.2")
}
