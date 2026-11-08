import SwiftUI

/// The accounts of one provider in Settings > GitHub or GitLab: who each is,
/// whether its token still works, and when that was last checked.
struct ProviderAccountRows: View {
    let accounts: [ProviderAccount]
    let emptyTitle: String
    let emptyDescription: String
    @State private var manager = AccountManager.shared
    @State private var validating: Set<String> = []

    var body: some View {
        if accounts.isEmpty {
            SettingsFormRow(emptyTitle, description: emptyDescription) {}
        } else {
            ForEach(accounts) { account in
                if account.id != accounts.first?.id {
                    SettingsDivider()
                }
                SettingsFormRow(account.username, description: Self.description(of: account)) {
                    HStack(spacing: 8) {
                        Button {
                            validate(account)
                        } label: {
                            if validating.contains(account.id) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Check")
                            }
                        }
                        .disabled(validating.contains(account.id))
                        Button("Sign Out", role: .destructive) {
                            manager.removeAccount(id: account.id)
                        }
                    }
                    .fixedSize()
                } detail: {
                    Self.status(of: account)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func validate(_ account: ProviderAccount) {
        validating.insert(account.id)
        Task {
            await manager.validate(accountID: account.id)
            validating.remove(account.id)
        }
    }

    /// The instance for a self-hosted account, and when the token was last checked.
    static func description(of account: ProviderAccount, now: Date = Date()) -> String {
        var parts: [String] = []
        if !account.instanceURL.isEmpty {
            parts.append(account.instanceURL)
        }
        if let date = ISO8601DateFormatter().date(from: account.lastValidatedISO) {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = AviLocale.display
            formatter.unitsStyle = .full
            parts.append("Checked \(formatter.localizedString(for: date, relativeTo: now))")
        } else {
            parts.append("Not checked yet")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    static func status(of account: ProviderAccount) -> some View {
        switch account.status {
        case "ok": SettingsStatus("Token works", tone: .success)
        case "invalid": SettingsStatus("Token not accepted; sign in again", tone: .error)
        case "unreachable": SettingsStatus("Could not reach the server", tone: .warning)
        default: SettingsStatus("Not checked", tone: .neutral)
        }
    }
}

/// Shared sheet for pasting a personal access token + optional instance URL.
/// The token is checked before the sheet closes; a refusal stays on screen.
struct PATEntrySheet: View {
    let providerName: String
    let instructions: String
    let instanceURLDefault: String
    let requiresInstanceURL: Bool
    let onSubmit: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var instanceURL: String
    @State private var isSigningIn = false
    @State private var failure: String?

    init(
        providerName: String,
        instructions: String,
        instanceURLDefault: String,
        requiresInstanceURL: Bool,
        onSubmit: @escaping (String, String) async throws -> Void
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
                    AviPopupTextField("Instance URL", text: $instanceURL, prompt: "https://gitlab.com")
                }
            }

            AviPopupField("Token", note: "Avi keeps it in your Keychain.") {
                SettingsTextField("Token", text: $token, prompt: "ghp_… / glpat_…", isSecure: true, maxWidth: .infinity)
            }

            if let failure {
                AviPopupCallout(failure, tone: .warning)
            }
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .aviKeyboardShortcut(.cancelAction)
            Button(isSigningIn ? "Checking…" : "Sign In", action: signIn)
                .buttonStyle(.aviProminent)
                .aviKeyboardShortcut(.defaultAction)
                .disabled(isSigningIn || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func signIn() {
        isSigningIn = true
        failure = nil
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await onSubmit(token, instanceURL)
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
