import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var store = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Privacy") {
                SettingsFormRow("Telemetry", description: "Send anonymized usage stats. Off by default.") {
                    Toggle("", isOn: telemetryBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Check for updates", description: "Periodically check for new releases.") {
                    Toggle("", isOn: checkForUpdatesBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("Config File") {
                SettingsFormRow("Path") {
                    HStack(spacing: 8) {
                        Text(ConfigPath.fileURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Actions") {
                    HStack(spacing: 8) {
                        Button("Open Config") { ConfigPath.openFile() }
                        Button("Open Folder") { ConfigPath.openFolder() }
                        Button("Reload") { store.reload() }
                    }
                }
                if let err = store.loadError {
                    Divider().padding(.vertical, 4)
                    SettingsFormRow("Status") {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var telemetryBinding: Binding<Bool> {
        Binding(
            get: { store.config.general.telemetryEnabled },
            set: { v in store.update { $0.general.telemetryEnabled = v } }
        )
    }

    private var checkForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { store.config.general.checkForUpdates },
            set: { v in store.update { $0.general.checkForUpdates = v } }
        )
    }
}
