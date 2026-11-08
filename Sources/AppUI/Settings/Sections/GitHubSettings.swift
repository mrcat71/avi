import SwiftUI

struct GitHubSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var manager = AccountManager.shared
    @State private var showingDeviceFlow = false
    @State private var showingPATSheet = false
    @State private var ghAuth: ProviderAuthState = .cliMissing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderInfoBanner(
                section: .github,
                features: "Open on GitHub, create pull requests, view PR status"
            )

            SettingsGroup("Command-line tool (gh)") {
                SettingsHeroRow("GitHub CLI") {
                    SettingsIcon(symbol: "terminal", tint: SettingsSection.github.tint, size: SettingsMetrics.heroIcon)
                } subtitle: {
                    VStack(alignment: .leading, spacing: 3) {
                        ProviderCLIStatusBadge(state: ghAuth)
                        Text("Avi reuses gh's sign-in to clone, list repositories, and create pull requests.")
                    }
                } trailing: {
                    Button("Refresh") {
                        Task { ghAuth = await GhCLI.authStatus() }
                    }
                }
            }

            SettingsGroup("Accounts", footer: "A token from Settings is used where gh is not signed in.") {
                ProviderAccountRows(
                    accounts: store.config.integrations.accounts.filter { $0.kind == "github" },
                    emptyTitle: "No GitHub account",
                    emptyDescription: "Sign in to create pull requests and open repositories on GitHub."
                )
                SettingsDivider()
                SettingsFormRow("Add account") {
                    HStack(spacing: 8) {
                        // Browser sign-in needs an OAuth app's client ID in the build.
                        if !GitHubDeviceFlowConfig.clientID.isEmpty {
                            Button("Sign In with Browser…") { showingDeviceFlow = true }
                        }
                        Button("Use a Token…") { showingPATSheet = true }
                    }
                    .fixedSize()
                }
            }
        }
        .task {
            ghAuth = await GhCLI.authStatus()
        }
        .sheet(isPresented: $showingDeviceFlow) {
            GitHubDeviceFlowSheet { account in
                manager.addAccount(account)
                showingDeviceFlow = false
            }
        }
        .sheet(isPresented: $showingPATSheet) {
            PATEntrySheet(
                providerName: "GitHub",
                instructions: "Create a token at github.com/settings/tokens with the repo scope, then paste it here.",
                instanceURLDefault: "",
                requiresInstanceURL: false
            ) { token, _ in
                try await manager.addGitHubPATAccount(token: token)
            }
        }
    }
}
