import SwiftUI

/// Settings > Agents: whether agents may send proposals, and one-click install
/// of the `avi` command and the skill for Claude Code and Codex.
struct AgentsSettingsView: View {
    @Bindable var store = ConfigStore.shared
    private let bridge = AgentBridge.shared
    private let installer = AgentInstaller()

    @Environment(\.openWindow) private var openWindow
    @State private var states: [AgentInstaller.Target: AgentInstaller.State] = [:]
    @State private var confirmation: Confirmation?
    @State private var lastError: String?

    private struct Confirmation: Identifiable {
        let target: AgentInstaller.Target
        let remove: Bool
        let message: String

        var id: String {
            target.rawValue + (remove ? "-remove" : "-install")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Agent proposals") {
                SettingsFormRow("Accept proposals", description: "Agents hand finished work to Avi with the avi command. Nothing is committed until you approve it.") {
                    Toggle("", isOn: bind(\.agents.enabled))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel("Accept proposals from agents")
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Socket") {
                    socketStatus
                }
            }

            SettingsGroup("Install") {
                ForEach(AgentInstaller.Target.allCases) { target in
                    installRow(target)
                    if target != AgentInstaller.Target.allCases.last {
                        Divider().padding(.vertical, 4)
                    }
                }
                Divider().padding(.vertical, 4)
                HStack {
                    if let lastError {
                        Text(lastError)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("How to Use…") {
                        openWindow(id: AgentGuideView.windowID)
                    }
                    Button("Install All", action: installAll)
                        .disabled(!canInstallAny)
                }
            }

            SettingsGroup("Waiting for review") {
                let pending = bridge.openRepositories.filter { !$0.commitPlan.isEmpty || $0.fieldProposal != nil }
                if pending.isEmpty {
                    Text("No proposals are waiting in open repositories.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pending) { repository in
                        SettingsFormRow(repository.root?.lastPathComponent ?? "Repository") {
                            Text(pendingSummary(repository))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog(
            confirmation?.message ?? "",
            isPresented: Binding(get: { confirmation != nil }, set: {
                if !$0 {
                    confirmation = nil
                }
            }),
            titleVisibility: .visible,
            presenting: confirmation
        ) { pending in
            Button(pending.remove ? "Remove" : "Replace", role: .destructive) {
                perform(pending.target, remove: pending.remove, force: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var socketStatus: some View {
        switch bridge.state {
        case .listening(let path):
            statusLine("checkmark.circle.fill", .green, "Listening", detail: installer.tildePath(URL(fileURLWithPath: path)))
        case .stopped:
            statusLine("pause.circle", .secondary, "Off", detail: nil)
        case .servedElsewhere(let path):
            statusLine("exclamationmark.triangle.fill", .orange, "Another Avi is already listening", detail: installer.tildePath(URL(fileURLWithPath: path)))
        case .failed(let message):
            statusLine("xmark.circle.fill", .red, "Could not listen", detail: message)
        }
    }

    private func statusLine(_ symbol: String, _ color: Color, _ title: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }

    private func installRow(_ target: AgentInstaller.Target) -> some View {
        let state = states[target] ?? .notInstalled
        return SettingsFormRow(target.title, description: description(for: target)) {
            HStack(spacing: 8) {
                Image(systemName: symbol(for: state))
                    .foregroundStyle(color(for: state))
                Text(AgentCLI.Runner.describe(state))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color(for: state))
                    .lineLimit(2)
                Spacer()
                if case .unavailable = state {
                    EmptyView()
                } else {
                    Button(installTitle(for: state)) {
                        perform(target, remove: false, force: false)
                    }
                    .disabled(state == .installed)
                    if state != .notInstalled {
                        Button("Remove") {
                            perform(target, remove: true, force: false)
                        }
                    }
                }
            }
        }
    }

    private func description(for target: AgentInstaller.Target) -> String {
        let path = installer.tildePath(installer.location(of: target))
        switch target {
        case .command:
            return "\(path). Needs ~/.local/bin on your PATH."
        case .claude, .codex:
            return path
        }
    }

    private func installTitle(for state: AgentInstaller.State) -> String {
        switch state {
        case .notInstalled: return "Install"
        case .outdated: return "Update"
        default: return "Reinstall"
        }
    }

    private func symbol(for state: AgentInstaller.State) -> String {
        switch state {
        case .installed: return "checkmark.circle.fill"
        case .notInstalled: return "circle.dashed"
        case .outdated, .modified: return "arrow.triangle.2.circlepath.circle.fill"
        case .foreign: return "exclamationmark.triangle.fill"
        case .unavailable: return "minus.circle"
        }
    }

    private func color(for state: AgentInstaller.State) -> Color {
        switch state {
        case .installed: return .green
        case .notInstalled, .unavailable: return .secondary
        case .outdated, .modified, .foreign: return .orange
        }
    }

    private func pendingSummary(_ repository: RepositoryStore) -> String {
        var sources: [String] = []
        for draft in repository.commitPlan.drafts where !sources.contains(draft.source.displayName) {
            sources.append(draft.source.displayName)
        }
        if let field = repository.fieldProposal, !sources.contains(field.source.displayName) {
            sources.append(field.source.displayName)
        }
        let commits = repository.commitPlan.drafts.count + (repository.fieldProposal == nil ? 0 : 1)
        return "\(commits) commit\(commits == 1 ? "" : "s") from \(sources.joined(separator: ", "))"
    }

    // MARK: Actions

    private var canInstallAny: Bool {
        AgentInstaller.Target.allCases.contains { target in
            switch states[target] ?? .notInstalled {
            case .notInstalled, .outdated: return true
            default: return false
            }
        }
    }

    private func installAll() {
        for target in AgentInstaller.Target.allCases {
            switch states[target] ?? .notInstalled {
            case .notInstalled, .outdated:
                perform(target, remove: false, force: false)
            default:
                continue
            }
        }
    }

    private func perform(_ target: AgentInstaller.Target, remove: Bool, force: Bool) {
        do {
            if remove {
                try installer.remove(target, force: force)
            } else {
                try installer.install(target, force: force)
            }
            lastError = nil
        } catch AgentInstaller.InstallError.needsConfirmation(_, let state) {
            confirmation = Confirmation(
                target: target,
                remove: remove,
                message: state == .modified
                    ? "The \(target.title) was edited after Avi installed it. \(remove ? "Remove" : "Replace") it anyway?"
                    : "Something Avi did not install is at \(installer.tildePath(installer.location(of: target))). \(remove ? "Remove" : "Replace") it?"
            )
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        var next: [AgentInstaller.Target: AgentInstaller.State] = [:]
        for target in AgentInstaller.Target.allCases {
            next[target] = installer.state(of: target)
        }
        states = next
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Lets menu commands open Settings on a particular section.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var requested: SettingsSection?
}

/// Agents > Install Agent Skills... (also in Help), which opens Settings > Agents.
public struct InstallAgentSkillsCommand: View {
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        Button("Install Agent Skills…") {
            SettingsNavigation.shared.requested = .agents
            openSettings()
        }
    }
}
