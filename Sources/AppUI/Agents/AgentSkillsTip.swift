import Foundation
import Observation
import SwiftUI

/// The tip that suggests installing the agent skills. A fresh install, the
/// launch that creates the config file, arms it; updating Avi never does. It
/// stays across launches until you dismiss it or the `avi` command or a skill
/// is installed, however that happens.
@MainActor
@Observable
public final class AgentSkillsTip {
    public static let shared = AgentSkillsTip()
    static let pendingKey = "agentSkillsTipPending"

    public private(set) var isShowing = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let skillsInstalled: @MainActor () -> Bool

    init(defaults: UserDefaults = .standard, skillsInstalled: @escaping @MainActor () -> Bool = AgentSkillsTip.anythingInstalled) {
        self.defaults = defaults
        self.skillsInstalled = skillsInstalled
    }

    /// Call once per launch, before any window shows.
    public func noteLaunch(isFreshInstall: Bool) {
        if isFreshInstall {
            defaults.set(true, forKey: Self.pendingKey)
        }
        refresh()
    }

    /// Hides the tip for good once the skills are installed.
    public func refresh() {
        guard defaults.bool(forKey: Self.pendingKey) else {
            isShowing = false
            return
        }
        if skillsInstalled() {
            dismiss()
        } else {
            isShowing = true
        }
    }

    public func dismiss() {
        defaults.set(false, forKey: Self.pendingKey)
        isShowing = false
    }

    /// Whether the `avi` command or either skill is in place, current or not.
    static func anythingInstalled() -> Bool {
        let installer = AgentInstaller()
        return AgentInstaller.Target.allCases.contains { target in
            switch installer.state(of: target) {
            case .installed, .outdated, .modified: return true
            case .notInstalled, .foreign, .unavailable: return false
            }
        }
    }
}

/// The tip itself, above the window's content.
struct AgentSkillsTipBanner: View {
    let tip: AgentSkillsTip
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(DS.Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Let Claude Code and Codex hand their work to Avi")
                    .font(.system(size: 12, weight: .semibold))
                Text("Install the avi command and skill: agents stage files and propose commits, and nothing is committed until you approve it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("How It Works") {
                openWindow(id: AgentGuideView.windowID)
            }
            .controlSize(.small)
            Button("Install Agent Skills…") {
                SettingsNavigation.shared.requested = .agents
                openSettings()
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            Button {
                tip.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Don't show this again")
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.Palette.accent.opacity(0.08))
    }
}
