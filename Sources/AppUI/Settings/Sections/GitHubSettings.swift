import SwiftUI

struct GitHubSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var manager = AccountManager.shared
    @State private var showingDeviceFlow = false
    @State private var showingPATSheet = false
    @State private var patValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderInfoBanner(
                provider: "GitHub",
                features: "Open on GitHub, create pull requests, view PR status"
            )

            SettingsGroup("Accounts") {
                if githubAccounts.isEmpty {
                    SettingsFormRow("No GitHub account") {
                        Text("Sign in to enable PR creation and 'Open on GitHub' actions.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(githubAccounts) { account in
                        SettingsFormRow(account.username, description: account.statusDescription) {
                            HStack(spacing: 8) {
                                Text(account.status)
                                    .font(.system(size: 11))
                                    .foregroundStyle(statusColor(account.status))
                                Spacer()
                                Button("Validate") {
                                    Task { await manager.validate(accountID: account.id) }
                                }
                                Button("Sign Out", role: .destructive) {
                                    manager.removeAccount(id: account.id)
                                }
                            }
                        }
                        Divider().padding(.vertical, 4)
                    }
                }
                SettingsFormRow("Add account") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Button("Sign in with browser") { showingDeviceFlow = true }
                                .disabled(!isDeviceFlowConfigured)
                            Button("Use Personal Access Token") {
                                patValue = ""
                                showingPATSheet = true
                            }
                        }
                        if !isDeviceFlowConfigured {
                            Text("Browser sign-in is planned. Use a Personal Access Token for now.")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
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
                instructions: "Create a token at github.com/settings/tokens with 'repo' scope, then paste it here.",
                instanceURLDefault: "",
                requiresInstanceURL: false
            ) { token, _ in
                Task {
                    try? await manager.addGitHubPATAccount(token: token)
                    showingPATSheet = false
                }
            }
        }
    }

    private var githubAccounts: [ProviderAccount] {
        store.config.integrations.accounts.filter { $0.kind == "github" }
    }

    private var isDeviceFlowConfigured: Bool {
        !GitHubDeviceFlowConfig.clientID.isEmpty
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "ok": return .green
        case "invalid", "unreachable": return .red
        default: return .secondary
        }
    }
}

private extension ProviderAccount {
    var statusDescription: String {
        if lastValidatedISO.isEmpty { return "Never validated" }
        return "Last validated \(lastValidatedISO)"
    }
}
