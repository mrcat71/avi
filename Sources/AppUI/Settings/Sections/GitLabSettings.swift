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
                        Text("Avi will reuse glab's authentication when cloning and listing repositories.")
                    }
                } trailing: {
                    Button("Refresh") {
                        Task { glabAuth = await GlabCLI.authStatus() }
                    }
                }
            }

            SettingsGroup("Accounts") {
                if gitlabAccounts.isEmpty {
                    SettingsFormRow(
                        "No GitLab account",
                        description: "Sign in to enable MR creation and 'Open on GitLab' actions. Supports gitlab.com and self-hosted."
                    ) {}
                    SettingsDivider()
                } else {
                    ForEach(gitlabAccounts) { account in
                        SettingsFormRow(account.username, description: instanceDescription(account)) {
                            HStack(spacing: 8) {
                                Text(account.status)
                                    .font(.system(size: 11))
                                    .foregroundStyle(statusColor(account.status))
                                Button("Validate") {
                                    Task { await manager.validate(accountID: account.id) }
                                }
                                Button("Sign Out", role: .destructive) {
                                    manager.removeAccount(id: account.id)
                                }
                            }
                            .fixedSize()
                        }
                        SettingsDivider()
                    }
                }
                SettingsFormRow("Add account") {
                    Button("Use Personal Access Token") {
                        showingPATSheet = true
                    }
                }
            }
        }
        .task {
            glabAuth = await GlabCLI.authStatus()
        }
        .sheet(isPresented: $showingPATSheet) {
            PATEntrySheet(
                providerName: "GitLab",
                instructions: "Create a token at gitlab.com/-/user_settings/personal_access_tokens with 'api' scope, then paste it here.",
                instanceURLDefault: "https://gitlab.com",
                requiresInstanceURL: true
            ) { token, instanceURL in
                Task {
                    try? await manager.addGitLabPATAccount(token: token, instanceURL: instanceURL)
                    showingPATSheet = false
                }
            }
        }
    }

    private var gitlabAccounts: [ProviderAccount] {
        store.config.integrations.accounts.filter { $0.kind == "gitlab" }
    }

    private func instanceDescription(_ a: ProviderAccount) -> String {
        a.instanceURL.isEmpty ? "gitlab.com" : a.instanceURL
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "ok": return .green
        case "invalid", "unreachable": return .red
        default: return .secondary
        }
    }
}

/// Shared sheet for pasting a personal access token + optional instance URL.
struct PATEntrySheet: View {
    let providerName: String
    let instructions: String
    let instanceURLDefault: String
    let requiresInstanceURL: Bool
    let onSubmit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var instanceURL: String

    init(
        providerName: String,
        instructions: String,
        instanceURLDefault: String,
        requiresInstanceURL: Bool,
        onSubmit: @escaping (String, String) -> Void
    ) {
        self.providerName = providerName
        self.instructions = instructions
        self.instanceURLDefault = instanceURLDefault
        self.requiresInstanceURL = requiresInstanceURL
        self.onSubmit = onSubmit
        _instanceURL = State(initialValue: instanceURLDefault)
    }

    var body: some View {
        AviPopup(
            symbol: "key.fill",
            tint: DS.Palette.infoIndigo,
            title: "Sign in to \(providerName)",
            subtitle: "With a personal access token",
            width: 440
        ) {
            Text(instructions)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if requiresInstanceURL {
                AviPopupField("Instance URL") {
                    TextField("https://gitlab.com", text: $instanceURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Instance URL")
                }
            }

            AviPopupField("Token", note: "Avi keeps it in your Keychain.") {
                SecureField("ghp_… / glpat_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Token")
            }
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .aviKeyboardShortcut(.cancelAction)
            Button("Sign In") {
                onSubmit(token.trimmingCharacters(in: .whitespacesAndNewlines), instanceURL)
            }
            .buttonStyle(.aviProminent)
            .aviKeyboardShortcut(.defaultAction)
            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
