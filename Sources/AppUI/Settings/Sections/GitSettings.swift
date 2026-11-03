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
                SettingsDivider()
                SettingsFormRow("Email") {
                    TextField("", text: bind(\.git.defaultAuthorEmail))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                SettingsDivider()
                SettingsFormRow("Sign commits", description: "Adds -S to git commit if your gpg/ssh signing is configured.") {
                    Toggle("Sign commits", isOn: bind(\.git.signCommits))
                        .labelsHidden()
                }
            }

            SettingsGroup("Fetch") {
                SettingsFormRow(
                    "Auto-fetch interval",
                    description: "Minutes. Once the last fetch is older than this, Avi fetches when you come back to it or switch tabs, and again while it stays in front. 0 turns it off."
                ) {
                    Stepper(value: bind(\.git.fetchInterval), in: 0 ... 120, step: 5) {
                        Text("\(store.config.git.fetchInterval) min")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                SettingsDivider()
                SettingsFormRow("Prune on fetch") {
                    Toggle("Prune on fetch", isOn: bind(\.git.pruneOnFetch))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsFormRow("Auto-refresh", description: "Pick up filesystem changes automatically.") {
                    Toggle("Auto-refresh", isOn: bind(\.git.autoRefresh))
                        .labelsHidden()
                }
            }

            PullRequestSettingsGroup(store: store)

            SettingsGroup("External Apps") {
                SettingsFormRow("Editor", description: "Path to the editor used for 'Open in Editor'.") {
                    TextField("/usr/local/bin/code", text: bind(\.git.externalEditor))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                }
                SettingsDivider()
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
