import AppKit
import SwiftUI

struct CloneSettingsView: View {
    @Bindable var store = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Default location") {
                SettingsFormRow(
                    "Clone directory",
                    description: "New clones land here unless you pick a different folder"
                ) {
                    HStack(spacing: 6) {
                        TextField("~/Developer", text: bind(\.clone.defaultDirectory))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Button("Choose…") { chooseDirectory() }
                    }
                }
            }

            SettingsGroup("Behavior") {
                SettingsFormRow(
                    "After clone",
                    description: "Open the cloned repository automatically"
                ) {
                    Toggle("Open repository after clone", isOn: bind(\.clone.openAfterClone))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow(
                    "Protocol",
                    description: "What a repository from GitHub or GitLab is cloned over; each clone can switch"
                ) {
                    Picker("", selection: bind(\.clone.preferredProtocol)) {
                        Text("HTTPS").tag("https")
                        Text("SSH").tag("ssh")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow(
                    "Remember destination",
                    description: "Reuse the last destination folder per provider"
                ) {
                    Toggle("Remember destination per provider", isOn: bind(\.clone.rememberDestinationPerProvider))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
            }
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: kp] },
            set: { v in store.update { $0[keyPath: kp] = v } }
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
