import AppKit
import SwiftUI

/// Agents > How to Use Avi with AI Agents: the one-time setup and the everyday
/// flow, with prompts to copy into an agent.
public struct AgentGuideView: View {
    /// The window this guide opens in.
    public static let windowID = "agent-guide"
    static let fullGuide = URL(string: "https://github.com/mrcat71/avi/blob/main/docs/AGENT-INTEGRATION.md")!

    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hand commits from AI agents to Avi")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Claude Code, Codex, and other local agents propose commits; you review and commit them in Avi. Agents never commit or push.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                step(1, "Install the skill", "Installs the `avi` command in ~/.local/bin, which must be on your PATH, and the avi skill for Claude Code and Codex.") {
                    InstallAgentSkillsCommand()
                        .controlSize(.small)
                }
                step(2, "Open the repository in Avi once", "Agents can only reach repositories you have opened in Avi.")
                step(3, "Codex only: let avi reach Avi", "Set `network_access = true` under `[sandbox_workspace_write]` in ~/.codex/config.toml, or approve running avi when Codex asks.")
                step(4, "Ask your agent", "When a task is done, ask it to hand the work to Avi, for example:") {
                    VStack(alignment: .leading, spacing: 6) {
                        prompt("Hand this to Avi as one commit.")
                        prompt("Send this to Avi split into logical commits.")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("What you get in Changes")
                        .font(.system(size: 13, weight: .semibold))
                    bullet("One commit: its files are staged as Commit 1 and its message fills the commit field.")
                    bullet("Several commits: they wait as planned commits under Commit 1.")
                    bullet("Nothing is committed until you press Commit or Commit All.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Make it the default")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add this line to your global agent instructions, such as ~/.claude/CLAUDE.md or ~/.codex/AGENTS.md:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    prompt("When a task in a git repository is done, hand the commit to Avi with the avi skill.")
                }

                HStack {
                    Text("Check the setup from a terminal with `avi status`.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Full Guide") {
                        openURL(Self.fullGuide)
                    }
                    .controlSize(.small)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private func step(_ number: Int, _ title: String, _ detail: LocalizedStringKey) -> some View {
        step(number, title, detail) { EmptyView() }
    }

    private func step(_ number: Int, _ title: String, _ detail: LocalizedStringKey, @ViewBuilder extra: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.16)))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number): \(title)")
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
    }

    /// A prompt you can select or copy in one click.
    private func prompt(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .accessibilityLabel("Copy prompt")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// Agents > How to Use Avi with AI Agents…, which opens the guide window.
public struct AgentGuideCommand: View {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        Button("How to Use Avi with AI Agents…") {
            openWindow(id: AgentGuideView.windowID)
        }
    }
}
