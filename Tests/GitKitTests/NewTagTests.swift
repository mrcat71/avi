@testable import GitKit
import Testing

struct NewTagTests {
    @Test(arguments: ["v1.2.3", "release/2026-10", "INFRA-12345", "v1.0-rc.1", "äpfel", "@x", "a.b"])
    func gitTakesTheseNames(_ name: String) {
        #expect(NewTag.problem(with: name) == nil)
    }

    @Test(arguments: [
        "", "-delete", "@", "v 1", "v1~1", "v1^", "a:b", "what?", "v*", "[x]", "a\\b", "a..b", "a@{1}",
        "/v1", "v1/", "a//b", "v1.", ".hidden", "a/.b", "v1.lock", "a/b.lock", "tab\there"
    ])
    func gitRefusesTheseNames(_ name: String) {
        #expect(NewTag.problem(with: name) != nil)
    }

    @Test func aBlankMessageMakesALightweightTag() {
        #expect(!NewTag(name: "v1", message: "  \n").isAnnotated)
        #expect(NewTag(name: "v1", message: " Release 1 ").message == "Release 1")
    }
}
