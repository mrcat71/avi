import Foundation

/// Lightweight UserDefaults wrapper for cross-session UI state. Only persists
/// preferences that survive a relaunch (selected primary view, sidebar width).
/// Branch/tag/remote selections reset to the default landing view on launch.
enum AppPreferences {
    private enum Key {
        static let lastSelectedView = "avi.lastSelectedView"
        static let sidebarWidth = "avi.sidebarWidth"
        static let density = "avi.density"
    }

    static let defaultSidebarWidth: Double = 286
    static let minSidebarWidth: Double = 220
    static let maxSidebarWidth: Double = 380

    static var lastSelectedView: PersistedView? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.lastSelectedView) else { return nil }
            return PersistedView(rawValue: raw)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value.rawValue, forKey: Key.lastSelectedView)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.lastSelectedView)
            }
        }
    }

    static var sidebarWidth: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.sidebarWidth)
            guard stored > 0 else { return defaultSidebarWidth }
            return min(max(stored, minSidebarWidth), maxSidebarWidth)
        }
        set {
            let clamped = min(max(newValue, minSidebarWidth), maxSidebarWidth)
            UserDefaults.standard.set(clamped, forKey: Key.sidebarWidth)
        }
    }

    static var density: Density {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.density) else { return .comfortable }
            return Density(rawValue: raw) ?? .comfortable
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.density)
        }
    }
}

enum Density: String {
    case compact
    case comfortable
}

/// Persistable subset of `RepositorySelection`. Ref-specific selections are
/// not persisted; on relaunch they fall back to `.allCommits`.
enum PersistedView: String {
    case localChanges
    case allCommits
}
