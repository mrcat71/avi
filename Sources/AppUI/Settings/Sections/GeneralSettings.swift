import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var store = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Config File") {
                SettingsFormRow("Status") {
                    statusBadge
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Path") {
                    Text(ConfigPath.fileURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Actions") {
                    HStack(spacing: 8) {
                        Button("Open Config") { ConfigPath.openFile() }
                        Button("Open Folder") { ConfigPath.openFolder() }
                        Button("Reload") { store.reload() }
                        Button("Reset to defaults", role: .destructive) { store.reset() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch store.status {
        case .loaded:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Config loaded")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            }
        case .createdNew:
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                Text("Config created with defaults")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
            }
        case .invalid(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("Config invalid (using last valid copy)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .pathNotWritable(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("Config path not writable")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
