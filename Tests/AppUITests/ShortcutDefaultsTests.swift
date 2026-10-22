@testable import AppUI
import Foundation
import KeyboardShortcuts
import SwiftUI
import Testing

@MainActor
struct ShortcutDefaultsTests {
    /// The menus fall back to `defaultShortcut` when the library is missing,
    /// so both places have to agree.
    @Test(arguments: AviShortcuts.Action.allCases)
    func defaultsMatchTheRecorder(action: AviShortcuts.Action) {
        let recorded = action.shortcutName.initialShortcut?.toSwiftUI
        #expect(recorded?.key == action.defaultShortcut?.key)
        #expect(recorded?.modifiers == action.defaultShortcut?.modifiers)
    }

    @Test func noTwoActionsShareADefault() {
        let shortcuts = AviShortcuts.Action.allCases.compactMap(\.defaultShortcut)
        #expect(Set(shortcuts).count == shortcuts.count)
    }
}
