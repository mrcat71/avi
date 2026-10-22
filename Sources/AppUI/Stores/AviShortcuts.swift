import AppKit
import Foundation
import Observation
import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

/// The keyboard shortcuts you can change in Settings > Keyboard. Each one is
/// the key equivalent of its menu item, which posts the `.avi…` notification
/// the views listen for, so it works while Avi is in front and never reaches
/// into other apps: registering them as global hot keys made Avi swallow
/// Cmd-R, Cmd-O or Cmd-Return everywhere while it was running.
///
/// When the `KeyboardShortcuts` library isn't linked (the bare-CLI
/// `./build.sh` fallback path), the menus use the defaults.
public enum AviShortcuts {
    /// Logical action handled by a customisable shortcut.
    public enum Action: String, CaseIterable, Identifiable, Sendable {
        case openRepository
        case refresh
        case stageAll
        case unstageAll
        case discardSelection
        case commit
        case fetch
        case pull
        case push
        case pushAndCreatePullRequest
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
            case .discardSelection: return "Discard Selected Changes"
            case .commit: return "Commit"
            case .fetch: return "Fetch"
            case .pull: return "Pull"
            case .push: return "Push"
            case .pushAndCreatePullRequest: return "Push and Create Pull Request"
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
            case .discardSelection: return .aviDiscardSelection
            case .commit: return .aviCommit
            case .fetch: return .aviFetchRepository
            case .pull: return .aviPullRepository
            case .push: return .aviPushRepository
            case .pushAndCreatePullRequest: return .aviPushAndCreatePullRequest
            case .commandPalette: return .aviOpenCommandPalette
            case .goToLocalChanges: return .aviGoToLocalChanges
            case .goToAllCommits: return .aviGoToAllCommits
            case .toggleHistoryScope: return .aviToggleHistoryScope
            }
        }

        /// The shortcut a fresh install has.
        var defaultShortcut: KeyboardShortcut? {
            switch self {
            case .openRepository: return KeyboardShortcut("o", modifiers: .command)
            case .refresh: return KeyboardShortcut("r", modifiers: .command)
            case .stageAll: return KeyboardShortcut("s", modifiers: [.command, .shift])
            case .unstageAll: return KeyboardShortcut("u", modifiers: [.command, .shift])
            case .discardSelection: return KeyboardShortcut("d", modifiers: [.command, .shift])
            case .commit: return KeyboardShortcut(.return, modifiers: .command)
            case .fetch: return nil
            case .pull: return KeyboardShortcut("l", modifiers: [.command, .shift])
            case .push: return KeyboardShortcut("p", modifiers: [.command, .option])
            case .pushAndCreatePullRequest: return nil
            case .commandPalette: return KeyboardShortcut("k", modifiers: .command)
            case .goToLocalChanges: return KeyboardShortcut("1", modifiers: .command)
            case .goToAllCommits: return KeyboardShortcut("2", modifiers: .command)
            case .toggleHistoryScope: return KeyboardShortcut("k", modifiers: [.command, .shift])
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

    /// The shortcut `action`'s menu item uses: yours, else the default.
    @MainActor
    public static func shortcut(for action: Action) -> KeyboardShortcut? {
        // Read so the menus update when Settings changes a shortcut.
        _ = ShortcutChanges.shared.version
        #if canImport(KeyboardShortcuts)
        return KeyboardShortcuts.getShortcut(for: action.shortcutName)?.toSwiftUI
        #else
        return action.defaultShortcut
        #endif
    }

    /// Sets up the shortcuts at launch. Idempotent.
    @MainActor
    public static func prepare() {
        #if canImport(KeyboardShortcuts)
        removeLegacyFetchShortcut()
        #endif
    }

    #if canImport(KeyboardShortcuts)
    @MainActor
    static func removeLegacyFetchShortcut(for name: KeyboardShortcuts.Name = .fetch) {
        // The library persists defaults, so removing the initial binding alone
        // would leave existing installs intercepting GoLand's Find in Files.
        if KeyboardShortcuts.getShortcut(for: name) == .init(.f, modifiers: [.command, .shift]) {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
    }
    #endif
}

/// Bumped when you record a shortcut in Settings, so the menus pick it up.
@MainActor
@Observable
final class ShortcutChanges {
    static let shared = ShortcutChanges()
    private(set) var version = 0

    func changed() {
        version += 1
    }
}

#if canImport(KeyboardShortcuts)
extension KeyboardShortcuts.Name {
    static let openRepository = Self("avi.openRepository", initial: .init(.o, modifiers: [.command]))
    static let refresh = Self("avi.refresh", initial: .init(.r, modifiers: [.command]))
    static let stageAll = Self("avi.stageAll", initial: .init(.s, modifiers: [.command, .shift]))
    static let unstageAll = Self("avi.unstageAll", initial: .init(.u, modifiers: [.command, .shift]))
    static let discardSelection = Self("avi.discardSelection", initial: .init(.d, modifiers: [.command, .shift]))
    static let commit = Self("avi.commit", initial: .init(.return, modifiers: [.command]))
    static let fetch = Self("avi.fetch")
    static let pull = Self("avi.pull", initial: .init(.l, modifiers: [.command, .shift]))
    static let push = Self("avi.push", initial: .init(.p, modifiers: [.command, .option]))
    static let pushAndCreatePullRequest = Self("aviPushAndCreatePullRequest")
    static let commandPalette = Self("avi.commandPalette", initial: .init(.k, modifiers: [.command]))
    static let goToLocalChanges = Self("avi.goToLocalChanges", initial: .init(.one, modifiers: [.command]))
    static let goToAllCommits = Self("avi.goToAllCommits", initial: .init(.two, modifiers: [.command]))
    static let toggleHistoryScope = Self("avi.toggleHistoryScope", initial: .init(.k, modifiers: [.command, .shift]))
}

extension AviShortcuts.Action {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .openRepository: return .openRepository
        case .refresh: return .refresh
        case .stageAll: return .stageAll
        case .unstageAll: return .unstageAll
        case .discardSelection: return .discardSelection
        case .commit: return .commit
        case .fetch: return .fetch
        case .pull: return .pull
        case .push: return .push
        case .pushAndCreatePullRequest: return .pushAndCreatePullRequest
        case .commandPalette: return .commandPalette
        case .goToLocalChanges: return .goToLocalChanges
        case .goToAllCommits: return .goToAllCommits
        case .toggleHistoryScope: return .toggleHistoryScope
        }
    }
}
#endif
