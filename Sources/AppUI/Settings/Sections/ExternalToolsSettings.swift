import AppKit
import GitKit
import SwiftUI
import UniformTypeIdentifiers

struct ExternalToolsSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var editors: [InstalledApp] = []
    @State private var terminals: [InstalledApp] = []
    @State private var tools: [CLIToolStatus] = []
    @State private var isDetecting = false
    @State private var testing: Set<CLITool> = []
    @State private var testResults: [CLITool: AICLIValidator.TestResult] = [:]
    @State private var redetectTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Open In") {
                SettingsFormRow("Editor", description: "For Open in Editor on repositories, worktrees, and changed files.") {
                    SettingsPopupMenu(
                        "Editor",
                        selection: bind(\.git.externalEditor),
                        items: editorItems,
                        fallbackTitle: displayName(store.config.git.externalEditor)
                    )
                } detail: {
                    if let problem = editorProblem {
                        SettingsStatus(problem, tone: .warning)
                            .padding(.top, 6)
                    }
                }
                SettingsDivider()
                SettingsFormRow("Terminal", description: "For Open in Terminal on repositories and worktrees.") {
                    SettingsPopupMenu(
                        "Terminal",
                        selection: bind(\.git.terminalApp),
                        items: terminalItems,
                        fallbackTitle: displayName(store.config.git.terminalApp)
                    )
                }
            }

            SettingsGroup("Diff and Merge") {
                SettingsFormRow(
                    "Diff tool",
                    description: "For External Diff in Changes. Avi runs it with the old and new version of the file. "
                        + "Empty uses Git's diff.tool."
                ) {
                    HStack(spacing: 6) {
                        SettingsTextField("Diff tool", text: bind(\.externalTools.diffToolPath), prompt: "Git's diff.tool", monospaced: true, maxWidth: 220)
                        Button("Choose…", action: chooseDiffTool)
                    }
                } detail: {
                    if let problem = ToolPath.problem(store.config.externalTools.diffToolPath) {
                        SettingsStatus(problem, tone: .warning)
                            .padding(.top, 6)
                    }
                }
                SettingsDivider()
                MergeToolRow(store: store)
            }

            SettingsAdvancedSection(.externalTools) {
                SettingsGroup(
                    "Command-Line Tools",
                    footer: "Avi finds these itself. A path here runs that executable instead; one that is not an executable is ignored."
                ) {
                    ForEach(CLITool.allCases) { tool in
                        if tool != CLITool.allCases.first {
                            SettingsDivider()
                        }
                        toolRow(tool)
                    }
                } accessory: {
                    Button(action: redetect) {
                        HStack(spacing: 4) {
                            if isDetecting {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Re-detect")
                        }
                    }
                    .disabled(isDetecting)
                }
            }
        }
        .task {
            editors = InstalledApp.list(KnownApps.editors)
            terminals = InstalledApp.list(KnownApps.terminals)
            if tools.isEmpty {
                redetect()
            }
        }
    }

    // MARK: Editor and terminal

    private var editorItems: [SettingsPopupMenu<String>.Item] {
        let automatic = KnownApps.installed(KnownApps.automaticEditors).first.map { "Automatic (\($0.app.name))" }
            ?? "Automatic (none installed)"
        return [.option("", automatic)]
            + appItems(editors, configured: store.config.git.externalEditor)
            + [.divider, .action("Choose…") { choose(into: \.git.externalEditor, allowsCommands: true) }]
    }

    private var terminalItems: [SettingsPopupMenu<String>.Item] {
        // Empty is Terminal, so Terminal's own entry would only repeat it.
        let others = terminals.filter { $0.app.bundleID != "com.apple.Terminal" }
        return [.option("", "Terminal")]
            + appItems(others, configured: store.config.git.terminalApp)
            + [.divider, .action("Choose…") { choose(into: \.git.terminalApp, allowsCommands: false) }]
    }

    /// The installed apps, and the configured one when it is not among them.
    private func appItems(_ apps: [InstalledApp], configured: String) -> [SettingsPopupMenu<String>.Item] {
        var items = apps.map { SettingsPopupMenu<String>.Item.option($0.url.path, $0.app.name) }
        let path = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty, !apps.contains(where: { $0.url.path == path }) {
            items.append(.option(configured, displayName(configured)))
        }
        return items.isEmpty ? [] : [.divider] + items
    }

    private var editorProblem: String? {
        let configured = store.config.git.externalEditor
        if configured.trimmingCharacters(in: .whitespaces).isEmpty {
            return FolderActions.editor == nil ? "No editor Avi knows is installed. Choose one." : nil
        }
        return FolderActions.editor == nil ? "Nothing Avi can open at this path" : nil
    }

    private func displayName(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return KnownApps.displayName(of: URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
    }

    private func choose(into keyPath: WritableKeyPath<AviConfig, String>, allowsCommands: Bool) {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = allowsCommands ? [.application, .unixExecutable] : [.application]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.update { $0[keyPath: keyPath] = url.path }
        }
    }

    private func chooseDiffTool() {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.message = "Choose the executable External Diff runs, such as ksdiff or bcomp."
        panel.allowedContentTypes = [.unixExecutable, .item]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.update { $0.externalTools.diffToolPath = url.path }
        }
    }

    // MARK: Command-line tools

    private func toolRow(_ tool: CLITool) -> some View {
        let status = tools.first { $0.tool == tool }
        let chosen = store.config.externalTools[keyPath: tool.overridePath]
        return SettingsFormRow(tool.name, description: [tool.purpose, status?.version].compactMap(\.self).joined(separator: " · ")) {
            Button {
                runTest(tool, path: status?.path)
            } label: {
                if testing.contains(tool) {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Test")
                }
            }
            .disabled(status?.path == nil || testing.contains(tool))
        } detail: {
            VStack(alignment: .leading, spacing: 6) {
                if let status {
                    if let path = status.path {
                        SettingsStatus(path, tone: .success)
                            .textSelection(.enabled)
                    } else {
                        SettingsStatus("Not found", tone: .error)
                    }
                }
                SettingsTextField("\(tool.name) path", text: overrideBinding(tool), prompt: "Path to use instead", monospaced: true, maxWidth: 420)
                if let problem = ToolPath.problem(chosen) {
                    SettingsStatus("\(problem); Avi ignores it", tone: .warning)
                }
                if let result = testResults[tool] {
                    testResultView(result)
                }
            }
            .padding(.top, 6)
        }
    }

    private func testResultView(_ result: AICLIValidator.TestResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if result.timedOut {
                SettingsStatus("Timed out after \(result.durationMS / 1000) s", tone: .warning, symbol: "clock.badge.exclamationmark")
            } else if result.exitCode == 0 {
                SettingsStatus("Exit 0 in \(result.durationMS) ms", tone: .success)
            } else {
                SettingsStatus("Exit \(result.exitCode.map(String.init) ?? "?") in \(result.durationMS) ms", tone: .error)
            }
            if !result.stdoutFirstLine.isEmpty {
                Text(result.stdoutFirstLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !result.stderrFirstLine.isEmpty {
                Text(result.stderrFirstLine)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Palette.danger)
                    .textSelection(.enabled)
            }
        }
    }

    private func runTest(_ tool: CLITool, path: String?) {
        guard let path else { return }
        testing.insert(tool)
        Task {
            let result = await AICLIValidator.runTest(executable: path)
            testResults[tool] = result
            testing.remove(tool)
        }
    }

    private func redetect() {
        isDetecting = true
        let config = store.config.externalTools
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                CLITool.allCases.map { ExternalToolsScanner.status(of: $0, config: config) }
            }.value
            tools = found
            isDetecting = false
        }
    }

    /// A path typed here is checked again once you stop typing.
    private func overrideBinding(_ tool: CLITool) -> Binding<String> {
        Binding(
            get: { store.config.externalTools[keyPath: tool.overridePath] },
            set: { value in
                store.update { $0.externalTools[keyPath: tool.overridePath] = value }
                testResults[tool] = nil
                redetectTask?.cancel()
                redetectTask = Task {
                    try? await Task.safeSleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    redetect()
                }
            }
        )
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// An app from `KnownApps` that is installed, and where.
struct InstalledApp: Equatable {
    let app: KnownApp
    let url: URL

    static func list(_ apps: [KnownApp]) -> [InstalledApp] {
        KnownApps.installed(apps).map { InstalledApp(app: $0.app, url: $0.url) }
    }
}
