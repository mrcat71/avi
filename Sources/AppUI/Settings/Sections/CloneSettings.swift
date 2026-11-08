import AppKit
import SwiftUI

struct CloneSettingsView: View {
    @Bindable var store = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Clone") {
                SettingsFormRow("Clone directory", description: "New clones go here unless you pick another folder.") {
                    HStack(spacing: 6) {
                        SettingsTextField("Clone directory", text: bind(\.clone.defaultDirectory), prompt: "~/Developer", monospaced: true, maxWidth: 260)
                        Button("Choose…", action: chooseDirectory)
                    }
                }
                SettingsDivider()
                SettingsFormRow(
                    "Protocol",
                    description: "What a repository from GitHub or GitLab is cloned over. Each clone can switch."
                ) {
                    Picker("Protocol", selection: bind(\.clone.preferredProtocol)) {
                        Text("HTTPS").tag("https")
                        Text("SSH").tag("ssh")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    .labelsHidden()
                }
                SettingsDivider()
                SettingsFormRow("Open after cloning", description: "Opens the new repository in a tab.") {
                    Toggle("Open after cloning", isOn: bind(\.clone.openAfterClone))
                        .labelsHidden()
                }
            }

            SettingsAdvancedSection(.clone) {
                SettingsGroup("Destination") {
                    SettingsFormRow(
                        "Remember the folder per host",
                        description: "A clone from a host you cloned from before goes to the same folder as the last one, "
                            + "such as work repositories from your GitLab. Off always starts in the clone directory."
                    ) {
                        Toggle("Remember the folder per host", isOn: bind(\.clone.rememberDestinationPerProvider))
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.update { $0.clone.defaultDirectory = url.path }
        }
    }
}
