import SwiftUI

struct GitSettingsView: View {
    @Bindable var store = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Author") {
                SettingsFormRow("Name", description: "Empty = use git's local config.") {
                    TextField("", text: bind(\.git.defaultAuthorName))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Email") {
                    TextField("", text: bind(\.git.defaultAuthorEmail))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Sign commits", description: "Adds -S to git commit if your gpg/ssh signing is configured.") {
                    Toggle("", isOn: bind(\.git.signCommits))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("Fetch") {
                SettingsFormRow("Auto-fetch interval", description: "Minutes. 0 disables auto-fetch.") {
                    Stepper(value: bind(\.git.fetchInterval), in: 0 ... 120, step: 5) {
                        Text("\(store.config.git.fetchInterval) min")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Prune on fetch") {
                    Toggle("", isOn: bind(\.git.pruneOnFetch))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Auto-refresh", description: "Pick up filesystem changes automatically.") {
                    Toggle("", isOn: bind(\.git.autoRefresh))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup("External Apps") {
                SettingsFormRow("Editor", description: "Path to the editor used for 'Open in Editor'.") {
                    TextField("/usr/local/bin/code", text: bind(\.git.externalEditor))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Terminal") {
                    TextField("/Applications/iTerm.app", text: bind(\.git.terminalApp))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
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
}
