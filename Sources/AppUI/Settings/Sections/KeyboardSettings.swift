import SwiftUI

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts
#endif

struct KeyboardSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Shortcuts") {
                if AviShortcuts.isAvailable {
                    shortcutList
                } else {
                    SettingsFormRow("Custom shortcuts") {
                        Text("Customisable shortcuts require the KeyboardShortcuts library, which is only linked in full SwiftPM / Xcode builds. The default menu shortcuts in the menu bar still work.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }

            SettingsGroup("Tips") {
                SettingsFormRow("Resetting", description: "Click the small ⌫ on a recorder to clear a shortcut and fall back to the menu default.") {
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private var shortcutList: some View {
        #if canImport(KeyboardShortcuts)
        ForEach(Array(AviShortcuts.Action.allCases.enumerated()), id: \.element.id) { index, action in
            if index > 0 {
                Divider().padding(.vertical, 4)
            }
            SettingsFormRow(action.label) {
                KeyboardShortcuts.Recorder(for: action.shortcutName)
            }
        }
        #else
        EmptyView()
        #endif
    }
}
