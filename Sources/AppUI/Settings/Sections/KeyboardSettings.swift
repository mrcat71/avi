import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

struct KeyboardSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup(
                "Shortcuts",
                footer: AviShortcuts.isAvailable ? "Click a shortcut and press new keys. The ⌫ on it clears yours and brings back the menu's own." : nil
            ) {
                if AviShortcuts.isAvailable {
                    shortcutList
                } else {
                    SettingsFormRow(
                        "Custom shortcuts",
                        description: "This build has no shortcut recorder. The menus' own shortcuts still work."
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }

    private var shortcutList: some View {
        #if canImport(KeyboardShortcuts)
        ForEach(Array(AviShortcuts.Action.allCases.enumerated()), id: \.element.id) { index, action in
            if index > 0 {
                SettingsDivider()
            }
            SettingsFormRow(action.label) {
                KeyboardShortcuts.Recorder(for: action.shortcutName) { _ in
                    ShortcutChanges.shared.changed()
                }
            }
        }
        #else
        EmptyView()
        #endif
    }
}
