import AppKit
import Foundation

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

/// Centralised registry of user-customisable global keyboard shortcuts.
/// Each `Name` maps to one of the existing `.avi…` notifications that views
/// already listen for, so the customisable shortcut path and the menu-driven
/// shortcut path stay in sync.
///
/// When the `KeyboardShortcuts` library isn't linked (the bare-CLI
/// `./build.sh` fallback path), the module compiles but `register()` is a
/// no-op - the existing `CommandMenu` shortcuts in `AviApp.swift` still work
/// as the only key bindings.
public enum AviShortcuts {
    /// Logical action handled by a customisable shortcut.
    public enum Action: String, CaseIterable, Identifiable, Sendable {
        case openRepository
        case refresh
        case stageAll
        case unstageAll
        case commit
        case fetch
        case pull
        case push
        case commandPalette
        case goToLocalChanges
        case goToAllCommits
        case toggleHistoryScope

        public var id: String {
            rawValue
        }

        public var label: String {
            switch self {
            case .openRepository: return "Open Repository"
            case .refresh: return "Refresh"
            case .stageAll: return "Stage All"
            case .unstageAll: return "Unstage All"
            case .commit: return "Commit"
            case .fetch: return "Fetch"
            case .pull: return "Pull"
            case .push: return "Push"
            case .commandPalette: return "Command Palette"
            case .goToLocalChanges: return "Go to Local Changes"
            case .goToAllCommits: return "Go to All Commits"
            case .toggleHistoryScope: return "Toggle History Scope"
            }
        }

        public var notificationName: Notification.Name {
            switch self {
            case .openRepository: return .aviOpenRepository
            case .refresh: return .aviRefreshRepository
            case .stageAll: return .aviStageAll
            case .unstageAll: return .aviUnstageAll
            case .commit: return .aviCommit
            case .fetch: return .aviFetchRepository
            case .pull: return .aviPullRepository
            case .push: return .aviPushRepository
            case .commandPalette: return .aviOpenCommandPalette
            case .goToLocalChanges: return .aviGoToLocalChanges
            case .goToAllCommits: return .aviGoToAllCommits
            case .toggleHistoryScope: return .aviToggleHistoryScope
            }
        }
    }

    /// Whether the `KeyboardShortcuts` library is available in this build.
    public static var isAvailable: Bool {
        #if canImport(KeyboardShortcuts)
        return true
        #else
        return false
        #endif
    }

    /// Register notification-dispatch handlers for every named shortcut.
    /// Idempotent - safe to call from `applicationDidFinishLaunching` or
    /// `RootView.onAppear`. No-op when the library isn't linked.
    @MainActor
    public static func registerAll() {
        #if canImport(KeyboardShortcuts)
        for action in Action.allCases {
            let name = action.shortcutName
            KeyboardShortcuts.onKeyUp(for: name) {
                NotificationCenter.default.post(name: action.notificationName, object: nil)
            }
        }
        #endif
    }
}

#if canImport(KeyboardShortcuts)
extension KeyboardShortcuts.Name {
    static let openRepository = Self("avi.openRepository", default: .init(.o, modifiers: [.command]))
    static let refresh = Self("avi.refresh", default: .init(.r, modifiers: [.command]))
    static let stageAll = Self("avi.stageAll", default: .init(.s, modifiers: [.command, .shift]))
    static let unstageAll = Self("avi.unstageAll", default: .init(.u, modifiers: [.command, .shift]))
    static let commit = Self("avi.commit", default: .init(.return, modifiers: [.command]))
    static let fetch = Self("avi.fetch", default: .init(.f, modifiers: [.command, .shift]))
    static let pull = Self("avi.pull", default: .init(.l, modifiers: [.command, .shift]))
    static let push = Self("avi.push", default: .init(.p, modifiers: [.command, .option]))
    static let commandPalette = Self("avi.commandPalette", default: .init(.k, modifiers: [.command]))
    static let goToLocalChanges = Self("avi.goToLocalChanges", default: .init(.one, modifiers: [.command]))
    static let goToAllCommits = Self("avi.goToAllCommits", default: .init(.two, modifiers: [.command]))
    static let toggleHistoryScope = Self("avi.toggleHistoryScope", default: .init(.k, modifiers: [.command, .shift]))
}

extension AviShortcuts.Action {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .openRepository: return .openRepository
        case .refresh: return .refresh
        case .stageAll: return .stageAll
        case .unstageAll: return .unstageAll
        case .commit: return .commit
        case .fetch: return .fetch
        case .pull: return .pull
        case .push: return .push
        case .commandPalette: return .commandPalette
        case .goToLocalChanges: return .goToLocalChanges
        case .goToAllCommits: return .goToAllCommits
        case .toggleHistoryScope: return .toggleHistoryScope
        }
    }
}
#endif
