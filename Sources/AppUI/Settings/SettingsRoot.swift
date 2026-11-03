import GitKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case git
    case clone
    case keyboard
    case github
    case gitlab
    case ai
    case agents
    case externalTools
    case advanced

    var id: String {
        rawValue
    }

    /// The sidebar's runs of sections, a gap between each. General leads on
    /// its own and is drawn larger, with Avi's icon.
    static let sidebarGroups: [[SettingsSection]] = [
        [.general],
        [.appearance, .keyboard],
        [.git, .clone, .externalTools],
        [.github, .gitlab],
        [.ai, .agents],
        [.advanced]
    ]

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .git: return "Git"
        case .clone: return "Clone"
        case .keyboard: return "Keyboard"
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .ai: return "AI Commit Messages"
        case .agents: return "Agents"
        case .externalTools: return "External Tools"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .git: return "arrow.triangle.branch"
        case .clone: return "square.and.arrow.down"
        case .keyboard: return "command"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "globe"
        case .ai: return "wand.and.stars"
        case .agents: return "terminal"
        case .externalTools: return "wrench.and.screwdriver"
        case .advanced: return "slider.horizontal.3"
        }
    }

    /// The color of the section's icon tile.
    var tint: Color {
        switch self {
        case .general, .keyboard, .externalTools, .advanced: return .gray
        case .appearance: return .purple
        case .git: return .orange
        case .clone: return .blue
        case .github: return Color(red: 0.16, green: 0.18, blue: 0.21)
        case .gitlab: return .indigo
        case .ai: return .pink
        case .agents: return .green
        }
    }

    /// What Search Settings finds the section by besides its title: its
    /// groups and rows. A new row's label belongs here too.
    var keywords: [String] {
        switch self {
        case .general:
            return ["Avi", "Version", "Updates", "Check for Updates", "Check automatically", "Install automatically",
                    "Startup", "Launch at login", "Config file", "Open Config", "Open Folder", "Reload", "Reset to defaults"]
        case .appearance:
            return ["Theme", "Light", "Dark", "Density", "Row density", "Compact", "Comfortable", "Diff font",
                    "Diff text size", "Graph lane width", "Author pictures", "Gravatar", "File list", "Local Changes display",
                    "Tree", "Flat list"]
        case .git:
            return ["Author", "Name", "Email", "Sign commits", "GPG", "SSH signing", "Fetch", "Auto-fetch interval",
                    "Prune on fetch", "Auto-refresh", "Pull requests", "Ticket prefixes", "Keep hyphens in",
                    "Learn names from the repository", "Capitalize the first word", "Create as drafts", "Try a branch",
                    "External apps", "Editor", "Terminal"]
        case .clone:
            return ["Default location", "Clone directory", "Behavior", "After clone", "Protocol", "HTTPS", "SSH",
                    "Remember destination"]
        case .keyboard:
            return ["Shortcuts", "Keyboard shortcuts", "Resetting"] + AviShortcuts.Action.allCases.map(\.label)
        case .github:
            return ["gh", "Command-line tool", "Accounts", "Sign in", "Personal access token", "Token", "Validate",
                    "Sign out", "Pull requests"]
        case .gitlab:
            return ["glab", "Command-line tool", "Accounts", "Sign in", "Personal access token", "Token", "Self-hosted",
                    "Validate", "Sign out", "Merge requests"]
        case .ai:
            return ["AI", "Validation", "Generation", "Enable AI commit messages", "Backend", "Custom command",
                    "OpenAI-compatible API", "Model", "Temperature", "Max tokens", "Reasoning effort", "Insert directly",
                    "Timeout", "Command template", "Base URL", "API key", "Keychain", "Style", "Conventional Commits",
                    "Subject soft limit", "Subject hard limit", "Body wrap", "Prompt template", "codex", "claude"]
        case .agents:
            return ["Agent proposals", "Accept proposals", "Socket", "Install", "Install All", "Claude Code", "Codex",
                    "OpenCode", "avi command", "Skill", "How to Use", "Waiting for review"]
        case .externalTools:
            return ["Auto-detected tools", "Re-detect", "git", "gh", "glab", "codex", "claude", "Editor", "Terminal",
                    "Diff tool", "Override path", "Test", "Merge Tool", "Open conflicts in", "Custom Command"]
        case .advanced:
            return ["Import", "Export", "Config", "History", "History limit", "Verbose logging", "Reset",
                    "Restore defaults", "Reset all settings"]
        }
    }

    /// The sections, in sidebar order, whose title or keywords hold every
    /// word of `query`; all of them for an empty query.
    static func matching(_ query: String) -> [SettingsSection] {
        let order = sidebarGroups.flatMap { $0 }
        let words = searchable(query).split(separator: " ")
        guard !words.isEmpty else { return order }
        return order.filter { section in
            let text = searchable(([section.title] + section.keywords).joined(separator: " "))
            return words.allSatisfy { text.contains($0) }
        }
    }

    /// Case, accents and hyphens aside, so "auto fetch" finds Auto-fetch.
    private static func searchable(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "-", with: " ")
    }
}

/// The section on show, and Back and Forward through the ones you looked at,
/// as in System Settings.
struct SettingsHistory: Equatable {
    private(set) var current: SettingsSection
    private(set) var back: [SettingsSection] = []
    private(set) var forward: [SettingsSection] = []

    init(_ current: SettingsSection) {
        self.current = current
    }

    var canGoBack: Bool {
        !back.isEmpty
    }

    var canGoForward: Bool {
        !forward.isEmpty
    }

    /// Shows `section`; Back returns to the one before, and what was ahead
    /// of it is gone.
    mutating func visit(_ section: SettingsSection) {
        guard section != current else { return }
        back.append(current)
        forward.removeAll()
        current = section
    }

    mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}

/// The Settings window, after Rex's: a sidebar of icon tiles with a search
/// field, Back and Forward beside the section's title, and the settings in
/// cards under bold group titles.
public struct SettingsRoot: View {
    @State private var history = SettingsHistory(.general)
    @State private var query = ""

    private var selection: SettingsSection {
        history.current
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                content
                    .buttonStyle(AviPopupButtonStyle(size: .small))
                    .frame(maxWidth: 680, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle(selection.title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    backForward
                }
            }
            .aviNotices()
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $query, placement: .sidebar, prompt: "Search Settings")
        .onSubmit(of: .search) {
            if let first = SettingsSection.matching(query).first {
                history.visit(first)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(UnifiedToolbarWindow())
        .onAppear(perform: applyRequestedSection)
        .onChange(of: SettingsNavigation.shared.requested) { _, _ in
            applyRequestedSection()
        }
    }

    // MARK: Sidebar

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            if isSearching {
                ForEach(SettingsSection.matching(query)) { section in
                    sidebarRow(section)
                }
            } else {
                ForEach(Array(SettingsSection.sidebarGroups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { section in
                            sidebarRow(section)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if isSearching, SettingsSection.matching(query).isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    /// Clicking a row visits its section, so Back can return.
    private var sidebarSelection: Binding<SettingsSection?> {
        Binding(
            get: { selection },
            set: { section in
                if let section {
                    history.visit(section)
                }
            }
        )
    }

    @ViewBuilder
    private func sidebarRow(_ section: SettingsSection) -> some View {
        if section == .general, !isSearching {
            HStack(spacing: 10) {
                SettingsAppIcon(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Avi \(GitKit.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .padding(.vertical, 4)
            .tag(section)
        } else {
            HStack(spacing: 6) {
                Label {
                    Text(section.title)
                        .lineLimit(1)
                } icon: {
                    SettingsIcon(symbol: section.systemImage, tint: section.tint)
                }
                Spacer(minLength: 4)
                if shouldShowPlannedChip(section) {
                    Text("Planned")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
            .tag(section)
        }
    }

    private func shouldShowPlannedChip(_ section: SettingsSection) -> Bool {
        switch section {
        case .github: return GitHubDeviceFlowConfig.clientID.isEmpty
        default: return false
        }
    }

    // MARK: Navigation

    private var backForward: some View {
        ControlGroup {
            Button {
                history.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .help("Back")
            .disabled(!history.canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            Button {
                history.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .help("Forward")
            .disabled(!history.canGoForward)
            .keyboardShortcut("]", modifiers: .command)
        }
        .controlGroupStyle(.navigation)
    }

    private func applyRequestedSection() {
        guard let requested = SettingsNavigation.shared.requested else { return }
        history.visit(requested)
        SettingsNavigation.shared.requested = nil
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .git: GitSettingsView()
        case .clone: CloneSettingsView()
        case .keyboard: KeyboardSettingsView()
        case .github: GitHubSettingsView()
        case .gitlab: GitLabSettingsView()
        case .ai: AISettingsView()
        case .agents: AgentsSettingsView()
        case .externalTools: ExternalToolsSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}

/// SwiftUI gives the Settings window the preference toolbar, with the title
/// above the toolbar's buttons, and `windowToolbarStyle` does not change it.
/// The unified toolbar puts Back, Forward, and the title on one line, with
/// no line under it, as in Rex.
private struct UnifiedToolbarWindow: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        WindowView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.toolbarStyle = .unified
            window?.titlebarSeparatorStyle = .none
        }
    }
}
