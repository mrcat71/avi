import GitKit
import SwiftUI

struct GitSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var global = GitGlobalSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Fetch") {
                SettingsFormRow(
                    "Fetch automatically",
                    description: "While Avi is in front, once the last fetch is older than this. "
                        + "Coming back to Avi or switching tabs checks too."
                ) {
                    SettingsPopupMenu(
                        "Fetch automatically",
                        selection: bind(\.git.fetchInterval),
                        items: Self.fetchItems,
                        fallbackTitle: "Every \(store.config.git.fetchInterval) minutes"
                    )
                }
            }

            SettingsGroup("Pull Requests") {
                SettingsFormRow(
                    "Create as drafts",
                    description: "New pull and merge requests start as drafts. The Push sheet can change it for each one."
                ) {
                    Toggle("Create as drafts", isOn: bind(\.pullRequests.draft))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsFormRow(
                    "Capitalize the first word",
                    description: "Of titles made from branch names, unless it is a ticket key or a kept name."
                ) {
                    Toggle("Capitalize the first word", isOn: bind(\.pullRequests.capitalize))
                        .labelsHidden()
                }
            }

            SettingsAdvancedSection(.git) {
                author
                commits
                PullRequestTitleSettings(store: store)
            }
        }
        .task {
            global = await GitGlobalSettings.load()
        }
    }

    // MARK: Advanced

    private var author: some View {
        SettingsGroup("Author", footer: authorFooter) {
            SettingsFormRow("Name") {
                SettingsTextField("Name", text: bind(\.git.defaultAuthorName), prompt: global.name ?? "Your Name")
            }
            SettingsDivider()
            SettingsFormRow("Email") {
                SettingsTextField("Email", text: bind(\.git.defaultAuthorEmail), prompt: global.email ?? "you@example.com")
            }
        }
    }

    private var authorFooter: String {
        let fallback = "Avi commits with this name and email only in repositories where Git has none, "
            + "so a repository's own identity and includeIf ones always win."
        guard let name = global.name, let email = global.email else { return fallback }
        return "Git's global identity is \(name) <\(email)>. " + fallback
    }

    private var commits: some View {
        SettingsGroup("Commits and Refresh") {
            SettingsFormRow(
                "Sign commits",
                description: "Signs every commit Avi makes, as Git's commit.gpgSign does. Needs a GPG or SSH "
                    + "signing key set up in Git. Off leaves it to Git."
            ) {
                Toggle("Sign commits", isOn: bind(\.git.signCommits))
                    .labelsHidden()
            } detail: {
                if global.signsCommits, !store.config.git.signCommits {
                    SettingsStatus("Git signs your commits anyway: commit.gpgSign is on", tone: .neutral, symbol: "signature")
                        .padding(.top, 6)
                }
            }
            SettingsDivider()
            SettingsFormRow(
                "Prune on fetch",
                description: "Fetching drops remote branches deleted on the remote, so their local branches show as gone."
            ) {
                Toggle("Prune on fetch", isOn: bind(\.git.pruneOnFetch))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsFormRow(
                "Auto-refresh",
                description: "Refreshes when files in the repository change. Off refreshes after Avi's own "
                    + "commands and when you come back to Avi, which suits very large repositories."
            ) {
                Toggle("Auto-refresh", isOn: bind(\.git.autoRefresh))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsFormRow(
                "Commits to load",
                description: "History loads this many at first and more as you scroll. Applies to repositories opened next."
            ) {
                Stepper(value: historyLimit, in: AdvancedConfig.historyLimits, step: 50) {
                    Text("\(store.config.advanced.clampedHistoryLimit)")
                        .font(.system(size: 12).monospacedDigit())
                }
            }
        }
    }

    // MARK: Values

    static let fetchItems: [SettingsPopupMenu<Int>.Item] = [
        .option(0, "Off"),
        .divider,
        .option(5, "Every 5 minutes"),
        .option(10, "Every 10 minutes"),
        .option(15, "Every 15 minutes"),
        .option(30, "Every 30 minutes"),
        .option(60, "Every hour")
    ]

    private var historyLimit: Binding<Int> {
        Binding(
            get: { store.config.advanced.clampedHistoryLimit },
            set: { value in store.update { $0.advanced.historyLimit = value } }
        )
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Git's global identity and signing, which Settings > Git shows beside
/// Avi's fallbacks.
struct GitGlobalSettings: Equatable {
    var name: String?
    var email: String?
    var signsCommits = false

    static func load() async -> GitGlobalSettings {
        let git = GitCommandOptions.invocation(["config", "--global", "--get-regexp", #"^(user\.name|user\.email|commit\.gpgsign)$"#])
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let result = try? await ProcessRunner.run(executable: git.executable, arguments: git.arguments, workingDirectory: home),
              result.exitCode == 0
        else { return GitGlobalSettings() }
        return parse(result.stdoutString)
    }

    /// `git config --get-regexp` output: a key, a space, and its value.
    static func parse(_ output: String) -> GitGlobalSettings {
        var settings = GitGlobalSettings()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0].lowercased() {
            case "user.name": settings.name = value
            case "user.email": settings.email = value
            case "commit.gpgsign": settings.signsCommits = ["true", "yes", "on", "1"].contains(value.lowercased())
            default: break
            }
        }
        return settings
    }
}
