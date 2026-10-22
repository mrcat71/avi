import Foundation

/// Tests that put a window on screen and click or press keys in it take over
/// the screen while they run. They run in CI, and on your own Mac only with
/// `AVI_UI_TESTS=1 swift test`.
enum OnScreenTests {
    static var enabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return isOn(environment["AVI_UI_TESTS"]) || isOn(environment["CI"])
    }

    static let skipMessage = "Puts a window on screen: runs in CI, or locally with AVI_UI_TESTS=1."

    private static func isOn(_ value: String?) -> Bool {
        guard let value = value?.lowercased(), !value.isEmpty else { return false }
        return value != "0" && value != "false"
    }
}
