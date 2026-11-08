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
        [.ai, .agents]
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
        }
    }

    /// The color of the section's icon tile.
    var tint: Color {
        switch self {
        case .general, .keyboard, .externalTools: return .gray
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
    /// groups and rows outside Advanced. A new row's label belongs here, or
    /// in `advancedKeywords` when it sits under Advanced.
    var keywords: [String] {
        switch self {
        case .general:
            return ["Avi", "Version", "Updates", "Check for Updates", "Check automatically", "Install automatically",
                    "Startup", "Launch at login"]
        case .appearance:
            return ["Theme", "Appearance", "Light", "Dark", "System", "Density", "Row density", "Compact", "Comfortable",
                    "Changes and History", "Changed files", "File list", "Tree", "Flat list", "Diff text size", "Font size",
                    "Author pictures", "Gravatar", "Avatars"]
        case .git:
            return ["Fetch", "Auto-fetch", "Fetch automatically", "Pull requests", "Merge requests", "Create as drafts",
                    "Drafts", "Capitalize the first word"]
        case .clone:
            return ["Clone directory", "Default location", "Choose", "Protocol", "HTTPS", "SSH", "Open after cloning"]
        case .keyboard:
            return ["Shortcuts", "Keyboard shortcuts", "Clear a shortcut"] + AviShortcuts.Action.allCases.map(\.label)
        case .github:
            return ["gh", "Command-line tool", "Accounts", "Sign in", "Personal access token", "Token", "Check",
                    "Validate", "Sign out", "Pull requests"]
        case .gitlab:
            return ["glab", "Command-line tool", "Accounts", "Sign in", "Personal access token", "Token", "Self-hosted",
                    "Check", "Validate", "Sign out", "Merge requests"]
        case .ai:
            return ["AI", "Enable AI commit messages", "Backend", "Custom command", "OpenAI-compatible API", "Model",
                    "API key", "Keychain", "Check setup", "Conventional Commits", "Insert directly", "Preview", "codex",
                    "claude"]
        case .agents:
            return ["Agent proposals", "Accept proposals", "Install", "Install All", "Claude Code", "Codex",
                    "OpenCode", "avi command", "Skill", "How to Use", "Waiting for review"]
        case .externalTools:
            return ["Open in Editor", "Editor", "Terminal", "Open in Terminal", "Diff tool", "External Diff",
                    "Merge tool", "Open conflicts in", "Custom Command"]
        }
    }

    /// What Search Settings finds under the section's Advanced disclosure;
    /// a search that only these match opens it.
    var advancedKeywords: [String] {
        switch self {
        case .general:
            return ["Config file", "config.toml", "Open Config", "Open Folder", "Reload", "Export", "Import",
                    "Log Git commands", "Logging", "Verbose logging", "Console", "Reset all settings", "Restore defaults"]
        case .appearance:
            return ["Diff font", "Monospaced font", "Graph lane width", "Graph"]
        case .git:
            return ["Author", "Name", "Email", "Identity", "Sign commits", "GPG", "SSH signing", "Prune on fetch",
                    "Auto-refresh", "Watch for changes", "History", "Commits to load", "History limit",
                    "Pull request titles", "Ticket prefixes", "Keep hyphens in", "Learn names from the repository",
                    "Try a branch"]
        case .clone:
            return ["Remember destination", "Remember the folder", "Per host"]
        case .externalTools:
            return ["Command-line tools", "Re-detect", "git", "gh", "glab", "codex", "claude", "Path", "Override path",
                    "Test"]
        case .ai:
            return ["Reasoning effort", "Temperature", "Max tokens", "Timeout", "Command template", "Base URL",
                    "Message limits", "Subject soft limit", "Subject hard limit", "Body wrap", "Prompts",
                    "Prompt template", "Reword", "Split", "Revise plan"]
        case .agents:
            return ["Socket", "Control socket"]
        case .keyboard, .github, .gitlab:
            return []
        }
    }

    /// What the Advanced disclosure holds, in a line under its title; nil
    /// for a section without one.
    var advancedSummary: String? {
        switch self {
        case .general: return "Config file, import and export, Git command log, reset"
        case .appearance: return "Diff font and graph lane width"
        case .git: return "Author fallback, signing, pruning, auto-refresh, history size, pull request titles"
        case .clone: return "Remember the folder per host"
        case .externalTools: return "Paths of git, gh, glab, codex, and claude"
        case .ai: return "Reasoning effort, temperature, tokens, timeout, command, limits, prompts"
        case .agents: return "Control socket"
        case .keyboard, .github, .gitlab: return nil
        }
    }

    /// The sections, in sidebar order, whose title or keywords hold every
    /// word of `query`; all of them for an empty query.
    static func matching(_ query: String) -> [SettingsSection] {
        let order = sidebarGroups.flatMap { $0 }
        let words = searchWords(query)
        guard !words.isEmpty else { return order }
        return order.filter { $0.contains(words, in: [$0.title] + $0.keywords + $0.advancedKeywords) }
    }

    /// Whether `query` finds this section only by what its Advanced
    /// disclosure holds, so showing the section should open it.
    func revealsAdvanced(for query: String) -> Bool {
        let words = Self.searchWords(query)
        guard !words.isEmpty, !advancedKeywords.isEmpty else { return false }
        return !contains(words, in: [title] + keywords) && contains(words, in: [title] + keywords + advancedKeywords)
    }

    private func contains(_ words: [Substring], in phrases: [String]) -> Bool {
        let text = Self.searchable(phrases.joined(separator: " "))
        return words.allSatisfy { text.contains($0) }
    }

    private static func searchWords(_ query: String) -> [Substring] {
        searchable(query).split(separator: " ")
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
                visitFromSearch(first)
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
                    visitFromSearch(section)
                }
            }
        )
    }

    /// Shows `section`, with its Advanced settings open when the search
    /// found it only there.
    private func visitFromSearch(_ section: SettingsSection) {
        if isSearching, section.revealsAdvanced(for: query) {
            SettingsAdvanced.reveal(section)
        }
        history.visit(section)
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
            }
            .padding(.vertical, 2)
            .tag(section)
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
