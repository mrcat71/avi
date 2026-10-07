@testable import AppUI
import Foundation
import KeyboardShortcuts
import Testing

@MainActor
@Suite("Fetch keyboard shortcut")
struct ShortcutTests {
    enum Binding: CaseIterable {
        case legacy, custom, none
    }

    @Test(arguments: Binding.allCases)
    func removesOnlyTheConflictingBinding(binding: Binding) {
        let shortcut: KeyboardShortcuts.Shortcut? = switch binding {
        case .legacy: .init(.f, modifiers: [.command, .shift])
        case .custom: .init(.f, modifiers: [.command, .option])
        case .none: nil
        }
        let name = KeyboardShortcuts.Name("avi-fetch-test-\(UUID().uuidString)")
        defer { KeyboardShortcuts.setShortcut(nil, for: name) }
        KeyboardShortcuts.setShortcut(shortcut, for: name)

        AviShortcuts.removeLegacyFetchShortcut(for: name)

        let expected = shortcut == .init(.f, modifiers: [.command, .shift]) ? nil : shortcut
        #expect(KeyboardShortcuts.getShortcut(for: name) == expected)
        AviShortcuts.removeLegacyFetchShortcut(for: name)
        #expect(KeyboardShortcuts.getShortcut(for: name) == expected)
    }
}
