import AppKit
import SwiftUI

/// Loads brand assets shipped with the .app bundle. Returns nil in dev (raw
/// build.sh runs without copying resources), so callers degrade gracefully.
public enum Branding {
    /// The "Avi" wordmark PNG copied into Contents/Resources/Branding/ at
    /// package time. nil in unbundled dev runs.
    public static var wordmarkNSImage: NSImage? {
        guard let url = Bundle.main.url(
            forResource: "wordmark",
            withExtension: "png",
            subdirectory: "Branding"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// SwiftUI Image wrapper for the wordmark. nil when the resource is
    /// missing (dev builds) so callers can `if let` and skip the row.
    public static var wordmark: Image? {
        guard let ns = wordmarkNSImage else { return nil }
        return Image(nsImage: ns)
    }
}
