import AppKit
import SwiftUI

/// Multi-step modal that walks the user from "pick a source" to "clone completed".
/// Sources: every account signed in to `gh` or `glab`, or a pasted URL, cloned
/// over HTTPS with an account or over SSH with your keys. Destination defaults
/// to the configured clone directory. Progress is reported live.
public struct CloneSheet: View {
    let onClone: (URL) -> Void // called with the local URL on success so the host can open it
    let onDismiss: () -> Void

    @State private var controller = CloneController()

    public init(onClone: @escaping (URL) -> Void, onDismiss: @escaping () -> Void) {
        self.onClone = onClone
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 460)
        .task { await controller.refreshAuth() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(DS.Palette.accent)
            Text("Clone repository")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .disabled(controller.isCloning)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .pickingSource:
            SourceStep(controller: controller)
        case .loadingRepos:
            LoadingStep()
        case .browsingRepos:
            RepoListStep(controller: controller)
        case .pickingDestination:
            DestinationStep(controller: controller)
        case .cloning:
            ProgressStep(controller: controller)
        case .finished(let url):
            FinishedStep(localURL: url, warning: controller.finishedWarning) {
                onClone(url)
                onDismiss()
            }
        case .failed(let message):
            FailedStep(message: message, hint: controller.hint(for: message)) {
                controller.reset()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            backButton
            Spacer()
            statusLabel
            primaryButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var backButton: some View {
        if controller.canGoBack {
            Button("Back") { controller.goBack() }
                .disabled(controller.isCloning)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let label = controller.statusLabel {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let title = controller.primaryTitle {
            Button(title) {
                Task { await controller.primaryAction() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.primaryEnabled)
        }
    }
}

// MARK: - Steps

private struct SourceStep: View {
    let controller: CloneController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick a source")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if controller.isLoadingAccounts {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Looking for gh and glab accounts…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(CloneProvider.allCases, id: \.self) { provider in
                        providerCards(provider)
                    }
                }

                SourceCard(
                    icon: "link",
                    tint: .blue,
                    title: "From URL",
                    detail: "Paste an HTTPS or SSH URL to clone any Git repository, over HTTPS with an account or over SSH with your keys."
                ) {
                    controller.pickURL()
                }
            }
        }
    }

    /// One card per account the CLI knows, the broken ones with their fix.
    @ViewBuilder
    private func providerCards(_ provider: CloneProvider) -> some View {
        // Token accounts cannot list repositories; From URL offers them.
        let accounts = controller.accountList.accounts.filter { $0.provider == provider && !isToken($0) }
        let missing = provider == .github ? controller.accountList.ghMissing : controller.accountList.glabMissing
        let cli = provider == .github ? "gh" : "glab"
        if missing {
            SourceCard(icon: icon(provider), tint: tint(provider), title: provider.title, detail: "\(provider.title) CLI not found. Install it with `brew install \(cli)`.", action: nil)
        } else if accounts.isEmpty {
            SourceCard(icon: icon(provider), tint: tint(provider), title: provider.title, detail: "\(cli) is not signed in. Run `\(cli) auth login`.", action: nil)
        } else {
            ForEach(accounts) { account in
                SourceCard(
                    icon: icon(provider),
                    tint: tint(provider),
                    title: "\(provider.title) · \(account.title)",
                    detail: account.problem ?? "Signed in with \(cli)",
                    action: account.canBrowse ? { controller.pick(account: account) } : nil
                )
            }
        }
    }

    private func isToken(_ account: CloneAccount) -> Bool {
        if case .token = account.source {
            return true
        }
        return false
    }

    private func icon(_ provider: CloneProvider) -> String {
        provider == .github ? "chevron.left.forwardslash.chevron.right" : "globe"
    }

    private func tint(_ provider: CloneProvider) -> Color {
        provider == .github ? .primary : .orange
    }
}

/// A source the sheet offers; without an action it only explains why not.
private struct SourceCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(action == nil ? 0.02 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.75 : 1)
    }
}

private struct LoadingStep: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading repositories…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RepoListStep: View {
    let controller: CloneController

    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter by name", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Spacer()
                Text("\(filtered.count) of \(controller.repos.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            if filtered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(controller.repos.isEmpty ? "No repositories returned" : "No matches")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { controller.selectedRepoID },
                    set: { controller.selectedRepoID = $0 }
                )) {
                    ForEach(filtered) { repo in
                        RepoRow(repo: repo)
                            .tag(repo.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filtered: [RemoteRepo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty {
            return controller.repos
        }
        return controller.repos.filter {
            $0.nameWithOwner.lowercased().contains(trimmed) || $0.description.lowercased().contains(trimmed)
        }
    }
}

private struct RepoRow: View {
    let repo: RemoteRepo

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: repo.provider == .github ? "chevron.left.forwardslash.chevron.right" : "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.nameWithOwner)
                        .font(.system(size: 12, weight: .semibold))
                    if repo.isPrivate {
                        Text("private")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.16)))
                            .foregroundStyle(.orange)
                    }
                }
                if !repo.description.isEmpty {
                    Text(repo.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !repo.defaultBranch.isEmpty {
                Text(repo.defaultBranch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DestinationStep: View {
    @Bindable var controller: CloneController
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Repository")

            if let repo = controller.selectedRepo {
                HStack(spacing: 8) {
                    Image(systemName: repo.provider == .github ? "chevron.left.forwardslash.chevron.right" : "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(repo.nameWithOwner)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
            } else {
                TextField("https://github.com/owner/repo.git or git@github.com:owner/repo.git", text: $controller.pastedURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($urlFocused)
                    .onAppear { urlFocused = controller.pastedURL.isEmpty }
                    .accessibilityLabel("Repository URL")
            }

            connection

            sectionTitle("Destination")
                .padding(.top, 4)

            HStack(spacing: 6) {
                TextField("Local path", text: Binding(
                    get: { controller.destinationPath },
                    set: { controller.destinationPath = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                Button("Choose…") {
                    chooseDirectory()
                }
            }

            Toggle("Open repository after clone", isOn: Binding(
                get: { controller.openAfterClone },
                set: { controller.openAfterClone = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            Spacer()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    /// HTTPS with an account, or SSH with your keys, and the URL that results.
    @ViewBuilder
    private var connection: some View {
        if let url = controller.cloneURL {
            HStack(spacing: 10) {
                Picker("Clone over", selection: Binding(get: { controller.transport }, set: { controller.setTransport($0) })) {
                    Text("HTTPS").tag(CloneURL.Transport.https)
                    Text("SSH").tag(CloneURL.Transport.ssh)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)

                if controller.transport == .https {
                    Picker("Account", selection: $controller.credentialAccountID) {
                        Text("Git's saved credentials").tag(String?.none)
                        ForEach(controller.credentialChoices) { account in
                            Text("\(account.title) (\(account.sourceLabel))").tag(Optional(account.id))
                        }
                    }
                    .frame(maxWidth: 300)
                }
                Spacer()
            }
            .font(.system(size: 12))

            Text(connectionNote(for: url))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !controller.pastedURL.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Cloned exactly as typed, with Git's own settings.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        if let effective = controller.effectiveURL, controller.selectedRepo != nil || effective != controller.pastedURL {
            Text(effective)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func connectionNote(for url: CloneURL) -> String {
        switch controller.transport {
        case .ssh:
            return "Uses your SSH keys and ssh-agent. Your key must be added to your account on \(url.host)."
        case .https:
            if let account = controller.credentialAccount {
                switch account.source {
                case .gh, .glab:
                    return "Signs in as \(account.title) through \(account.sourceLabel), and the clone keeps using it to fetch and push."
                case .token:
                    return "Signs in with the token saved in Settings. Fetch and push then use Git's saved credentials."
                }
            }
            return controller.credentialChoices.isEmpty
                ? "No signed-in account for \(url.host). Git uses its saved credentials; a private repository may need SSH."
                : "Git uses its saved credentials, such as the Keychain."
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            controller.setDestinationDirectory(url)
        }
    }
}

private struct ProgressStep: View {
    let controller: CloneController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cloning")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                Spacer()
                LottieView(name: "downloading", loopMode: .loop, size: CGSize(width: 96, height: 96))
                Spacer()
            }

            if let progress = controller.progress {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progress.phase)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let percent = progress.percent {
                            Text("\(percent)%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let percent = progress.percent {
                        ProgressView(value: Double(percent), total: 100)
                    } else {
                        ProgressView()
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Starting clone…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Text(controller.destinationPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Spacer()
        }
    }
}

private struct FinishedStep: View {
    let localURL: URL
    let warning: String?
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("Clone complete")
                .font(.system(size: 14, weight: .semibold))
            Text(localURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open repository") { onOpen() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FailedStep: View {
    let message: String
    let hint: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Clone failed")
                .font(.system(size: 14, weight: .semibold))
            if let hint {
                Text(hint)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            ScrollView {
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            Button("Try again") { onRetry() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
