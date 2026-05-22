import SwiftUI

struct GitLabSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var manager = AccountManager.shared
    @State private var showingPATSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderInfoBanner(
                provider: "GitLab",
                features: "Open on GitLab, create merge requests"
            )

            SettingsGroup("Accounts") {
                if gitlabAccounts.isEmpty {
                    SettingsFormRow("No GitLab account") {
                        Text("Sign in to enable MR creation and 'Open on GitLab' actions. Supports gitlab.com and self-hosted.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(gitlabAccounts) { account in
                        SettingsFormRow(account.username, description: instanceDescription(account)) {
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
                    Button("Use Personal Access Token") {
                        showingPATSheet = true
                    }
                }
            }
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
        self._instanceURL = State(initialValue: instanceURLDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to \(providerName)")
                .font(.system(size: 14, weight: .semibold))
            Text(instructions)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)

            if requiresInstanceURL {
                Text("Instance URL")
                    .font(.system(size: 11, weight: .medium))
                TextField("https://gitlab.com", text: $instanceURL)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Token")
                .font(.system(size: 11, weight: .medium))
            SecureField("ghp_… / glpat_…", text: $token)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Sign In") {
                    onSubmit(token.trimmingCharacters(in: .whitespacesAndNewlines), instanceURL)
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
