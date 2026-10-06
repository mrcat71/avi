import Foundation

/// The Info.plist keys in-app updates depend on. Avi checks them before
/// starting Sparkle, so a development build or a misbuilt bundle says why
/// updates are off instead of failing on its first check, and `--self-test`
/// fails a packaged app that could not verify its next update.
public enum UpdateConfiguration {
    /// With both on, Sparkle checks the signatures of the appcast and of the
    /// download before it reads either.
    static let requiredFlags = ["SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"]

    /// Why `bundle` cannot update itself, or nil when it can.
    public static func problem(for bundle: Bundle) -> String? {
        problem(bundleURL: bundle.bundleURL, info: bundle.infoDictionary ?? [:])
    }

    static func problem(bundleURL: URL, info: [String: Any]) -> String? {
        guard bundleURL.pathExtension == "app" else {
            return "Updates work in the packaged Avi.app, not in a development build."
        }
        guard let feed = info["SUFeedURL"] as? String, URL(string: feed)?.scheme == "https" else {
            return "The app's Info.plist has no HTTPS SUFeedURL."
        }
        // Ad-hoc signatures change with every build, so this key is the only
        // thing that tells a genuine update from a forged one.
        guard let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else {
            return "The app's Info.plist has no valid SUPublicEDKey, so no update could be verified."
        }
        if let flag = requiredFlags.first(where: { info[$0] as? Bool != true }) {
            return "The app's Info.plist does not turn on \(flag)."
        }
        return nil
    }
}
