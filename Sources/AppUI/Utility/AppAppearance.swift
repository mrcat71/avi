import AppKit

/// Settings > Appearance > Appearance: System follows macOS; Light and Dark
/// hold every window to one.
enum AppAppearance {
    @MainActor
    static func apply(_ theme: String) {
        switch theme {
        case "light": NSApp?.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp?.appearance = NSAppearance(named: .darkAqua)
        default: NSApp?.appearance = nil
        }
    }
}
