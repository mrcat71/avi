import AppKit
import SwiftUI

/// Multi-step modal that walks the user from "pick a source" to "clone completed".
/// Sources: GitHub or GitLab CLI accounts, or a pasted URL. Destination defaults
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
            FinishedStep(localURL: url) {
                onClone(url)
                onDismiss()
            }
        case .failed(let message):
            FailedStep(message: message) {
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a source")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(CloneSource.allCases, id: \.self) { source in
                SourceCard(source: source, controller: controller)
            }

            Spacer()
        }
    }
}

private struct SourceCard: View {
    let source: CloneSource
    let controller: CloneController

    var body: some View {
        Button {
            controller.pick(source: source)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: source.icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(source.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(authMessage(for: source))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func authMessage(for source: CloneSource) -> String {
        switch source {
        case .github:
            switch controller.githubAuth {
            case .authenticated(let user, _): return "Signed in via gh as \(user)"
            case .unauthenticated: return "gh installed but not signed in. Run `gh auth login`."
            case .cliMissing: return "GitHub CLI not found. Install with `brew install gh`."
            case .error(let message): return "Error: \(message)"
            }
        case .gitlab:
            switch controller.gitlabAuth {
            case .authenticated(let user, _): return "Signed in via glab as \(user)"
            case .unauthenticated: return "glab installed but not signed in. Run `glab auth login`."
            case .cliMissing: return "GitLab CLI not found. Install with `brew install glab`."
            case .error(let message): return "Error: \(message)"
            }
        case .url:
            return "Paste an HTTPS or SSH URL to clone any git repository."
        }
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
        if trimmed.isEmpty { return controller.repos }
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
    let controller: CloneController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destination")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if let repo = controller.selectedRepo {
                HStack(spacing: 8) {
                    Image(systemName: repo.provider == .github ? "chevron.left.forwardslash.chevron.right" : "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(repo.nameWithOwner)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
            } else if !controller.pastedURL.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(controller.pastedURL)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }

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
            Button("Open repository") { onOpen() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FailedStep: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            Text("Clone failed")
                .font(.system(size: 14, weight: .semibold))
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
