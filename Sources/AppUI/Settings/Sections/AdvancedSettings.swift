import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var showingResetConfirm = false
    @State private var showingExporter = false
    @State private var showingImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Import / Export") {
                SettingsFormRow("Config", description: "Move non-secret settings between machines.") {
                    HStack(spacing: 8) {
                        Button("Export…") { showingExporter = true }
                        Button("Import…") { showingImporter = true }
                    }
                }
            }

            SettingsGroup("History") {
                SettingsFormRow("History limit", description: "Maximum commits loaded into the History view.") {
                    Stepper(value: bind(\.advanced.historyLimit), in: 50...2000, step: 50) {
                        Text("\(store.config.advanced.historyLimit) commits")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Verbose logging") {
                    Toggle("", isOn: bind(\.advanced.verboseLogging))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("Reset") {
                SettingsFormRow("Restore defaults", description: "Deletes config file + keychain entries.") {
                    Button("Reset all settings…", role: .destructive) {
                        showingResetConfirm = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores defaults and removes all stored credentials.")
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: TextDocument(text: (try? store.exportTOML()) ?? ""),
            contentType: .plainText,
            defaultFilename: "avi-config.toml"
        ) { _ in }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .data]
        ) { result in
            if case .success(let url) = result,
               let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8) {
                try? store.importTOML(text)
            }
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: kp] },
            set: { v in store.update { $0[keyPath: kp] = v } }
        )
    }
}

private struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
