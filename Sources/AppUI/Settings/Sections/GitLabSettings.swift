import SwiftUI

struct GitLabSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var manager = AccountManager.shared
    @State private var showingPATSheet = false
    @State private var glabAuth: ProviderAuthState = .cliMissing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderInfoBanner(
                section: .gitlab,
                features: "Open on GitLab, create merge requests"
            )

            SettingsGroup("Command-line tool (glab)") {
                SettingsHeroRow("GitLab CLI") {
                    SettingsIcon(symbol: "terminal", tint: SettingsSection.gitlab.tint, size: SettingsMetrics.heroIcon)
                } subtitle: {
                    VStack(alignment: .leading, spacing: 3) {
                        ProviderCLIStatusBadge(state: glabAuth)
                        Text("Avi reuses glab's sign-in to clone, list repositories, and create merge requests.")
                    }
                } trailing: {
                    Button("Refresh") {
                        Task { glabAuth = await GlabCLI.authStatus() }
                    }
                }
            }

            SettingsGroup("Accounts", footer: "Works with gitlab.com and self-hosted GitLab. A token from Settings is used where glab is not signed in.") {
                ProviderAccountRows(
                    accounts: store.config.integrations.accounts.filter { $0.kind == "gitlab" },
                    emptyTitle: "No GitLab account",
                    emptyDescription: "Sign in to create merge requests and open repositories on GitLab."
                )
                SettingsDivider()
                SettingsFormRow("Add account") {
                    Button("Use a Token…") { showingPATSheet = true }
                }
            }
        }
        .task {
            glabAuth = await GlabCLI.authStatus()
        }
        .sheet(isPresented: $showingPATSheet) {
            PATEntrySheet(
                providerName: "GitLab",
                instructions: "Create a personal access token with the api scope in your GitLab user settings, under Access tokens, then paste it here.",
                instanceURLDefault: "https://gitlab.com",
                requiresInstanceURL: true
            ) { token, instanceURL in
                try await manager.addGitLabPATAccount(token: token, instanceURL: instanceURL)
            }
        }
    }
}
