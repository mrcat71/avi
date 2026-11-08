import GitKit
import SwiftUI
import UniformTypeIdentifiers

#if canImport(LaunchAtLogin)
import LaunchAtLogin
#endif

struct GeneralSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @Bindable var updater = AppUpdater.shared
    @State private var showingResetConfirm = false
    @State private var exportDocument: TextDocument?
    @State private var showingImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.status.isError {
                configProblem
            }

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

            SettingsAdvancedSection(.general) {
                configFile
                logging
                reset
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Reset All Settings", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Avi goes back to its defaults and deletes the GitHub and GitLab tokens and the API key it keeps in your Keychain.")
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: {
                if !$0 {
                    exportDocument = nil
                }
            }),
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "avi-config.toml"
        ) { result in
            if case let .failure(error) = result {
                SettingsNotices.error("Could not export the settings: \(error.localizedDescription)")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.plainText, .data]) { result in
            importConfig(result)
        }
    }

    // MARK: Advanced

    private var configFile: some View {
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
                Button("Export…", action: exportConfig)
                Button("Import…") { showingImporter = true }
            }
            .padding(.vertical, 10)
            .settingsHeroIndent()
        }
    }

    private var logging: some View {
        SettingsGroup("Logging") {
            SettingsFormRow(
                "Log Git commands",
                description: "Writes every Git command Avi runs, with its time and exit status, to the system log. "
                    + "See it in Console under com.svinarenko.avi. Commands can hold file paths and commit messages."
            ) {
                Toggle("Log Git commands", isOn: bind(\.advanced.verboseLogging))
                    .labelsHidden()
            }
        }
    }

    private var reset: some View {
        SettingsGroup("Reset") {
            SettingsFormRow(
                "Reset all settings",
                description: "Restores every default and deletes the tokens and API key Avi keeps in your Keychain."
            ) {
                Button("Reset All Settings…", role: .destructive) {
                    showingResetConfirm = true
                }
            }
        }
    }

    // MARK: Parts

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

    /// A broken config file shows first, wherever Advanced is.
    private var configProblem: some View {
        SettingsGroup {
            SettingsFormRow("Config file problem", description: store.loadError) {
                Button("Open Config") { ConfigPath.openFile() }
            } detail: {
                statusBadge
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch store.status {
        case .loaded:
            SettingsStatus("Loaded", tone: .success)
        case .createdNew:
            SettingsStatus("Created with defaults", tone: .success, symbol: "plus.circle.fill")
        case .invalid:
            SettingsStatus("Invalid; Avi keeps the last good copy", tone: .error, symbol: "exclamationmark.triangle.fill")
        case .pathNotWritable:
            SettingsStatus("Cannot be written; Avi keeps settings in memory", tone: .error, symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Actions

    private func exportConfig() {
        do {
            exportDocument = try TextDocument(text: store.exportTOML())
        } catch {
            SettingsNotices.error("Could not export the settings: \(error.localizedDescription)")
        }
    }

    private func importConfig(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            try store.importTOML(text)
            SettingsNotices.success("Settings imported from \(url.lastPathComponent)")
        } catch {
            SettingsNotices.error("Could not import the settings: \(error.localizedDescription)")
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// A config file to export, as plain text.
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// What Settings tells you about an action it ran, as a notice at the top
/// of the window.
@MainActor
enum SettingsNotices {
    private static let id = "settings"

    static func error(_ text: String) {
        AviNoticeCenter.shared.show(.error(id: id, text: text) {
            AviNoticeCenter.shared.dismiss(id: id)
        })
    }

    static func success(_ title: String) {
        AviNoticeCenter.shared.show(AviNotice(
            id: id,
            tone: .success,
            symbol: "checkmark.circle.fill",
            title: title,
            onDismiss: { AviNoticeCenter.shared.dismiss(id: id) },
            autoDismiss: .seconds(4)
        ))
    }
}
