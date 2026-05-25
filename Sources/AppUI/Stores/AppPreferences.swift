import Foundation

/// Thin facade over `ConfigStore` for the small UI prefs that lived in
/// UserDefaults before iter 4. Density and friends now live in the TOML config;
/// these accessors are kept so existing call sites read the same names.
@MainActor
enum AppPreferences {
    static let defaultSidebarWidth: Double = 230
    static let minSidebarWidth: Double = 220
    static let maxSidebarWidth: Double = 380

    /// Last selected primary view persisted across launches.
    static var lastSelectedView: PersistedView? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "avi.lastSelectedView") else { return nil }
            return PersistedView(rawValue: raw)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value.rawValue, forKey: "avi.lastSelectedView")
            } else {
                UserDefaults.standard.removeObject(forKey: "avi.lastSelectedView")
            }
        }
    }

    static var sidebarWidth: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: "avi.sidebarWidth")
            guard stored > 0 else { return defaultSidebarWidth }
            return min(max(stored, minSidebarWidth), maxSidebarWidth)
        }
        set {
            let clamped = min(max(newValue, minSidebarWidth), maxSidebarWidth)
            UserDefaults.standard.set(clamped, forKey: "avi.sidebarWidth")
        }
    }

    static var density: Density {
        get {
            let raw = ConfigStore.shared.config.appearance.density
            return Density(rawValue: raw) ?? .comfortable
        }
        set {
            ConfigStore.shared.update { $0.appearance.density = newValue.rawValue }
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
