import SwiftUI

/// How pull request titles are made from branch names, with a branch to try
/// the rules on. Lives in Settings > Git.
struct PullRequestSettingsGroup: View {
    @Bindable var store = ConfigStore.shared
    /// Edited as typed, so a trailing comma or an empty line can be typed;
    /// the config gets the entries only.
    @State private var prefixesText = ""
    @State private var keepText = ""
    @State private var sampleBranch = "feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress"

    var body: some View {
        SettingsGroup("Pull Requests") {
            SettingsFormRow(
                "Ticket prefixes",
                description: "Separated by commas, matched in any case and written in capitals: infra-123 becomes INFRA-123. Keys already in capitals need no entry."
            ) {
                TextField("", text: $prefixesText, prompt: Text("INFRA, OPS"))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: prefixesText) { _, text in
                        store.update { $0.pullRequests.ticketPrefixes = PullRequestSettingsText.entries(commaSeparated: text) }
                    }
            }
            Divider().padding(.vertical, 4)
            SettingsFormRow(
                "Keep hyphens in",
                description: "One per line: a name, a pattern where * is one word (k8s-*-*-ams1), or a /regular expression/."
            ) {
                TextEditor(text: $keepText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(maxWidth: 320, minHeight: 64, maxHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityLabel("Keep hyphens in")
                    .onChange(of: keepText) { _, text in
                        store.update { $0.pullRequests.keepHyphenated = PullRequestSettingsText.entries(lines: text) }
                    }
            }
            Divider().padding(.vertical, 4)
            SettingsFormRow(
                "Learn names from the repository",
                description: "Keeps the hyphens of file and folder names the repository has, such as environments/k8s-infra-ah-ams1/."
            ) {
                Toggle("", isOn: bind(\.pullRequests.learnNamesFromRepository))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider().padding(.vertical, 4)
            SettingsFormRow("Capitalize the first word") {
                Toggle("", isOn: bind(\.pullRequests.capitalize))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider().padding(.vertical, 4)
            SettingsFormRow("Create as drafts") {
                Toggle("", isOn: bind(\.pullRequests.draft))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Divider().padding(.vertical, 4)
            SettingsFormRow(
                "Try a branch",
                description: "Names learned from a repository apply in the Push sheet, not here."
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: $sampleBranch, prompt: Text("Branch name"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .accessibilityLabel("Title: \(preview)")
                }
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

    private func bind<T>(_ kp: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: kp] },
            set: { v in store.update { $0[keyPath: kp] = v } }
        )
    }
}

/// The lists the Pull Requests settings edit as text.
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
