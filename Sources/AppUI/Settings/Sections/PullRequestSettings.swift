import SwiftUI

/// How pull request titles are made from branch names, with a branch to try
/// the rules on. Lives under Settings > Git > Advanced.
struct PullRequestTitleSettings: View {
    @Bindable var store = ConfigStore.shared
    /// Edited as typed, so a trailing comma or an empty line can be typed;
    /// the config gets the entries only.
    @State private var prefixesText = ""
    @State private var keepText = ""
    @State private var sampleBranch = "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress"
    @FocusState private var isEditingKeep: Bool

    var body: some View {
        SettingsGroup("Pull Request Titles", footer: "Titles come from the branch name: folders are dropped and every - and _ becomes a space, except in ticket keys and the names below.") {
            SettingsFormRow(
                "Ticket prefixes",
                description: "Separated by commas, matched in any case and written in capitals: infra-123 becomes "
                    + "INFRA-123. Keys already in capitals need no entry."
            ) {
                SettingsTextField("Ticket prefixes", text: $prefixesText, prompt: "INFRA, OPS")
                    .onChange(of: prefixesText) { _, text in
                        store.update { $0.pullRequests.ticketPrefixes = PullRequestSettingsText.entries(commaSeparated: text) }
                    }
            }
            SettingsDivider()
            SettingsFormRow(
                "Keep hyphens in",
                description: "One per line: a name, a pattern where * is one word (k8s-*-*-ams1), or a /regular expression/."
            ) {
                TextEditor(text: $keepText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .focused($isEditingKeep)
                    .padding(4)
                    .frame(maxWidth: 320, minHeight: 64, maxHeight: 64)
                    .modifier(AviFieldWell(isFocused: isEditingKeep))
                    .accessibilityLabel("Keep hyphens in")
                    .onChange(of: keepText) { _, text in
                        store.update { $0.pullRequests.keepHyphenated = PullRequestSettingsText.entries(lines: text) }
                    }
            }
            SettingsDivider()
            SettingsFormRow(
                "Learn names from the repository",
                description: "Keeps the hyphens of file and folder names the repository has, such as environments/k8s-infra-ah-ams1/."
            ) {
                Toggle("Learn names from the repository", isOn: bind(\.pullRequests.learnNamesFromRepository))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsFormRow(
                "Try a branch",
                description: "Names learned from a repository apply in the Push sheet, not here."
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsTextField("Branch name", text: $sampleBranch, prompt: "Branch name")
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .accessibilityLabel("Title: \(preview)")
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
        .onAppear {
            prefixesText = store.config.pullRequests.ticketPrefixes.joined(separator: ", ")
            keepText = store.config.pullRequests.keepHyphenated.joined(separator: "\n")
        }
    }

    private var preview: String {
        let branch = sampleBranch.trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty else { return "" }
        return PullRequestTitle.make(branch: branch, rules: PullRequestTitle.Rules(store.config.pullRequests))
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The lists the Pull Request Titles settings edit as text.
enum PullRequestSettingsText {
    /// "INFRA, ops," -> ["INFRA", "ops"].
    static func entries(commaSeparated text: String) -> [String] {
        text.split(separator: ",").compactMap(trimmed)
    }

    /// One entry per line, so a regular expression can hold commas.
    static func entries(lines text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap(trimmed)
    }

    private static func trimmed(_ entry: Substring) -> String? {
        let value = entry.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
