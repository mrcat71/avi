@testable import AppUI
import Foundation
import Testing

struct UpdateConfigurationTests {
    enum PlistValue: Sendable {
        case string(String)
        case bool(Bool)
        case missing
    }

    struct Breakage: Sendable, CustomTestStringConvertible {
        let key: String
        let value: PlistValue
        /// Text the reported problem must contain.
        let mentions: String

        var testDescription: String {
            "\(key) = \(value)"
        }
    }

    static let packagedApp = URL(fileURLWithPath: "/Applications/Avi.app")

    static var valid: [String: Any] {
        [
            "SUFeedURL": "https://github.com/mrcat71/avi/releases/latest/download/appcast.xml",
            "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true
        ]
    }

    @Test func packagedAppWithKeyAndSignedFeedCanUpdate() {
        #expect(UpdateConfiguration.problem(bundleURL: Self.packagedApp, info: Self.valid) == nil)
    }

    @Test(arguments: ["/Users/me/avi/.build/debug", "/Users/me/avi/.build/manual/AviApp"])
    func developmentBuildsDoNotUpdate(path: String) {
        let problem = UpdateConfiguration.problem(bundleURL: URL(fileURLWithPath: path), info: Self.valid)
        #expect(problem?.contains("packaged Avi.app") == true)
    }

    @Test(arguments: [
        Breakage(key: "SUFeedURL", value: .missing, mentions: "SUFeedURL"),
        Breakage(key: "SUFeedURL", value: .string("http://github.com/mrcat71/avi/appcast.xml"), mentions: "SUFeedURL"),
        Breakage(key: "SUPublicEDKey", value: .missing, mentions: "SUPublicEDKey"),
        // The template placeholder must never ship.
        Breakage(key: "SUPublicEDKey", value: .string("__SPARKLE_PUBLIC_ED_KEY__"), mentions: "SUPublicEDKey"),
        Breakage(
            key: "SUPublicEDKey",
            value: .string(Data(repeating: 7, count: 16).base64EncodedString()),
            mentions: "SUPublicEDKey"
        ),
        Breakage(key: "SUVerifyUpdateBeforeExtraction", value: .missing, mentions: "SUVerifyUpdateBeforeExtraction"),
        Breakage(key: "SURequireSignedFeed", value: .bool(false), mentions: "SURequireSignedFeed"),
        Breakage(key: "SURequireSignedFeed", value: .string("YES"), mentions: "SURequireSignedFeed")
    ])
    func brokenBundleSaysWhatIsMissing(_ breakage: Breakage) {
        var info = Self.valid
        switch breakage.value {
        case .string(let text): info[breakage.key] = text
        case .bool(let flag): info[breakage.key] = flag
        case .missing: info[breakage.key] = nil
        }
        let problem = UpdateConfiguration.problem(bundleURL: Self.packagedApp, info: info)
        #expect(problem?.contains(breakage.mentions) == true)
    }
}
