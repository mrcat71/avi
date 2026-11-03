import GitKit
import SwiftUI

#if canImport(LaunchAtLogin)
import LaunchAtLogin
#endif

struct GeneralSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @Bindable var updater = AppUpdater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                SettingsHeroRow("Avi") {
                    SettingsAppIcon()
                } subtitle: {
                    updateStatus
                } trailing: {
                    if updater.state == .running {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                }
                if updater.state == .running {
                    SettingsDivider(underHero: true)
                    SettingsFormRow("Check automatically", description: "Look for a new version once a day.") {
                        Toggle("Check automatically", isOn: $updater.automaticallyChecksForUpdates)
                            .labelsHidden()
                    }
                    .settingsHeroIndent()
                    SettingsDivider(underHero: true)
                    SettingsFormRow(
                        "Install automatically",
                        description: "Download new versions in the background and install them when you quit Avi."
                    ) {
                        Toggle("Install automatically", isOn: $updater.automaticallyDownloadsUpdates)
                            .labelsHidden()
                            .disabled(!updater.automaticallyChecksForUpdates)
                    }
                    .settingsHeroIndent()
                }
            }

            SettingsGroup("Startup") {
                SettingsFormRow("Launch at login", description: "Open Avi automatically when you log in.") {
                    launchAtLoginToggle
                }
            }

            SettingsGroup("Config File") {
                SettingsHeroRow(ConfigPath.fileName) {
                    SettingsIcon(symbol: "doc.text", tint: .gray, size: SettingsMetrics.heroIcon)
                } subtitle: {
                    VStack(alignment: .leading, spacing: 3) {
                        statusBadge
                        Text(ConfigPath.fileURL.path)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } trailing: {
                    Button("Open Config") { ConfigPath.openFile() }
                }
                SettingsDivider(underHero: true)
                HStack(spacing: 8) {
                    Button("Open Folder") { ConfigPath.openFolder() }
                    Button("Reload") { store.reload() }
                    Spacer()
                    Button("Reset to defaults", role: .destructive) { store.reset() }
                }
                .padding(.vertical, 10)
                .settingsHeroIndent()
            }
        }
    }

    /// The version, and why updates are off when they are.
    private var updateStatus: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Version \(GitKit.version)")
                .textSelection(.enabled)
            switch updater.state {
            case .running:
                EmptyView()
            case .notStarted:
                Text("Starting…")
            case .unavailable(let reason):
                Text(reason)
                    .textSelection(.enabled)
            }
        }
    }

    private var launchAtLoginToggle: some View {
        #if canImport(LaunchAtLogin)
        LaunchAtLogin.Toggle()
            .labelsHidden()
        #else
        HStack(spacing: 6) {
            Toggle("Launch at login", isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
            Text("Unavailable in this build")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        #endif
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
