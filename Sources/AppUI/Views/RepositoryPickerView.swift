import AppKit
import SwiftUI

/// Fork-style repository picker. Replaces the old WelcomeView and is reopened
/// from the tab bar's `+` as a sheet. Lists recent repositories with live
/// metadata (current branch, dirty state, last-opened), supports search and
/// filtering, and is the entry point for "Add existing" and (future) "Clone".
public struct RepositoryPickerView: View {
    public let openRepository: (URL) -> Void
    public let onClone: (() -> Void)?
    public let onDismiss: (() -> Void)?
    public let presentation: Presentation

    public enum Presentation {
        case standalone // full-screen empty state when no repos open
        case sheet // modal sheet, has a Close button
    }

    @State private var entries: [RecentEntry] = []
    @State private var searchText: String = ""
    @State private var providerFilter: ProviderFilter = .all
    @State private var book = RepositoryBook()

    public init(
        openRepository: @escaping (URL) -> Void,
        onClone: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        presentation: Presentation = .standalone
    ) {
        self.openRepository = openRepository
        self.onClone = onClone
        self.onDismiss = onDismiss
        self.presentation = presentation
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(DS.Palette.surface)
        .onAppear(perform: reload)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(DS.Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Repositories")
                    .font(.system(size: 15, weight: .semibold))
                if entries.isEmpty {
                    Text("Open or add a repository to get started")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(entries.count) recent · search to filter")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if presentation == .sheet, let onDismiss {
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
                .help("Close")
                .accessibilityLabel("Close repository picker")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search by name, path or branch", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            filterMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filterMenu: some View {
        Menu {
            ForEach(ProviderFilter.allCases, id: \.self) { filter in
                Button {
                    providerFilter = filter
                } label: {
                    HStack {
                        Text(filter.label)
                        if providerFilter == filter {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: providerFilter.icon)
                    .font(.system(size: 10))
                Text(providerFilter.label)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            emptyState
        } else if filteredEntries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No matches")
                    .font(.system(size: 12, weight: .semibold))
                Text("Try a different search term or filter.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        } else {
            List {
                ForEach(filteredEntries) { entry in
                    PickerRepoRow(
                        entry: entry,
                        metadata: book.metadata(for: entry.url),
                        onOpen: { openRepository(entry.url); onDismiss?() },
                        onReveal: { revealInFinder(entry.url) },
                        onOpenInTerminal: { openInTerminal(entry.url) },
                        onCopyPath: { copyPath(entry.url) },
                        onRemove: { remove(entry) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .onAppear {
                        book.hydrate(entry.url)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(DS.Palette.accent)
            VStack(spacing: 4) {
                Text("No repositories yet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add an existing local repository or clone one from GitHub or GitLab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                AviButton("Add existing", icon: "folder", variant: .primary, size: .medium, action: openPanelToAdd)
                if onClone != nil {
                    AviButton("Clone", icon: "square.and.arrow.down", variant: .secondary, size: .medium) {
                        onClone?()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openPanelToAdd()
            } label: {
                Label("Add existing", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            if onClone != nil {
                Button {
                    onClone?()
                } label: {
                    Label("Clone", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()

            if !entries.isEmpty {
                Text("\(filteredEntries.count) of \(entries.count) shown")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Filtering

    private var filteredEntries: [RecentEntry] {
        var list = entries
        if providerFilter != .all {
            list = list.filter { entry in
                let meta = book.metadata(for: entry.url)
                return providerFilter.matches(entry: entry, metadata: meta)
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return list }
        return list.filter { entry in
            if entry.path.lowercased().contains(query) { return true }
            if entry.displayName.lowercased().contains(query) { return true }
            if let branch = book.metadata(for: entry.url)?.branch,
               branch.lowercased().contains(query) { return true }
            if let hint = entry.providerHint, hint.lowercased().contains(query) { return true }
            return false
        }
    }

    // MARK: - Actions

    private func reload() {
        entries = RecentRepositories.entries()
        book.clear()
        for entry in entries {
            book.hydrate(entry.url)
        }
    }

    private func openPanelToAdd() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRepository(url)
        onDismiss?()
    }

    private func remove(_ entry: RecentEntry) {
        RecentRepositories.remove(entry.url)
        entries = RecentRepositories.entries()
        book.invalidate(entry.url)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openInTerminal(_ url: URL) {
        let terminalPath = ConfigStore.shared.config.git.terminalApp
        if !terminalPath.isEmpty,
           FileManager.default.fileExists(atPath: terminalPath) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: terminalPath),
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: { _, _ in }
            )
            // Best-effort: also open the folder via Finder so the user can drag-drop
            // it into the terminal. A proper handoff requires a per-app script.
            NSWorkspace.shared.open(url)
            return
        }
        let terminalAppURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: terminalAppURL, configuration: configuration, completionHandler: { _, _ in })
    }

    private func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }
}

// MARK: - Provider filter

private enum ProviderFilter: CaseIterable, Hashable {
    case all
    case github
    case gitlab
    case local

    var label: String {
        switch self {
        case .all: return "All"
        case .github: return "GitHub"
        case .gitlab: return "GitLab"
        case .local: return "Local"
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "globe"
        case .local: return "folder"
        }
    }

    func matches(entry: RecentEntry, metadata _: RepositoryBook.LiveMetadata?) -> Bool {
        guard let hint = entry.providerHint?.lowercased() else {
            return self == .local
        }
        switch self {
        case .all: return true
        case .github: return hint.hasPrefix("github")
        case .gitlab: return hint.hasPrefix("gitlab")
        case .local: return !hint.hasPrefix("github") && !hint.hasPrefix("gitlab")
        }
    }
}

// MARK: - Row

private struct PickerRepoRow: View {
    let entry: RecentEntry
    let metadata: RepositoryBook.LiveMetadata?
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onOpenInTerminal: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                providerIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if metadata?.isMissing == true {
                            chip("Missing", color: .red)
                        } else if metadata?.isDirty == true {
                            dirtyDot
                        }
                    }
                    HStack(spacing: 4) {
                        Text(entry.path)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                metaColumn
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(entry.path)
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Reveal in Finder") { onReveal() }
            Button("Open in Terminal") { onOpenInTerminal() }
            Button("Copy Path") { onCopyPath() }
            Divider()
            Button("Remove from Recent", role: .destructive) { onRemove() }
        }
        .accessibilityLabel("Open \(entry.displayName)")
    }

    @ViewBuilder
    private var providerIcon: some View {
        let symbol: String = {
            guard let hint = entry.providerHint?.lowercased() else { return "folder" }
            if hint.hasPrefix("github") { return "chevron.left.forwardslash.chevron.right" }
            if hint.hasPrefix("gitlab") { return "globe" }
            return "folder"
        }()
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }

    @ViewBuilder
    private var dirtyDot: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 7, height: 7)
            .help("Working tree has changes")
    }

    @ViewBuilder
    private var metaColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let branch = metadata?.branch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(branch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let cached = entry.lastKnownBranch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(cached)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            if entry.lastOpened != .distantPast {
                Text(Self.relativeFormatter.localizedString(for: entry.lastOpened, relativeTo: Date()))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minWidth: 80, alignment: .trailing)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}
