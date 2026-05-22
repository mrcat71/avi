import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case git
    case clone
    case github
    case gitlab
    case ai
    case externalTools
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .git: return "Git"
        case .clone: return "Clone"
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .ai: return "AI Commit Messages"
        case .externalTools: return "External Tools"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintpalette"
        case .git: return "arrow.triangle.branch"
        case .clone: return "square.and.arrow.down"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "globe"
        case .ai: return "wand.and.stars"
        case .externalTools: return "wrench.and.screwdriver"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

public struct SettingsRoot: View {
    @State private var selection: SettingsSection = .general
    @State private var store = ConfigStore.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                HStack(spacing: 6) {
                    Label(section.title, systemImage: section.systemImage)
                    Spacer()
                    if shouldShowPlannedChip(section) {
                        Text("Planned")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                    }
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(selection.title)
            .navigationSubtitle(ConfigPath.fileURL.path)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private func shouldShowPlannedChip(_ section: SettingsSection) -> Bool {
        switch section {
        case .github: return GitHubDeviceFlowConfig.clientID.isEmpty
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .git: GitSettingsView()
        case .clone: CloneSettingsView()
        case .github: GitHubSettingsView()
        case .gitlab: GitLabSettingsView()
        case .ai: AISettingsView()
        case .externalTools: ExternalToolsSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

/// Standard section row layout used by every settings panel.
struct SettingsFormRow<Content: View>: View {
    let label: String
    var description: String?
    let content: Content

    init(_ label: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.description = description
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(width: 180, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.bottom, 14)
    }
}
