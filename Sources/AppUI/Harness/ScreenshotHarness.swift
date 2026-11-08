#if DEBUG
import AppKit
import GitKit
import SwiftUI

/// `AviApp --render-screens <folder> [--only name,name]` builds the demo
/// repositories and saves the sheets and panes listed in `panels`, in light
/// and dark, as PNG files in `<folder>`, then quits. It shows no workspace,
/// reads a temporary config file, and never starts the agent socket, so the
/// Avi you use is left alone. Captures need Screen Recording permission for
/// the terminal.
@MainActor
public enum ScreenshotHarness {
    public private(set) static var outputDirectory: URL?
    private static var only: Set<String> = []

    public static var isActive: Bool {
        outputDirectory != nil
    }

    /// Reads the harness flags. Called from `main` before the app starts.
    public static func configure(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--render-screens"), index + 1 < arguments.count else { return }
        outputDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        ConfigPath.directoryOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-render-screens-config-\(UUID().uuidString)", isDirectory: true)
        if let onlyIndex = arguments.firstIndex(of: "--only"), onlyIndex + 1 < arguments.count {
            only = Set(arguments[onlyIndex + 1].split(separator: ",").map(String.init))
        }
    }

    /// Renders every panel, then quits.
    public static func run() {
        Task { @MainActor in
            do {
                try await render()
                NSApp.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("render-screens: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    private static func render() async throws {
        guard let output = outputDirectory else { return }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        PullRequestService.harnessRoute = .cli(executable: "/opt/homebrew/bin/gh")
        log("building demo repositories")
        let demo = try await DemoRepositories.make(in: FileManager.default.temporaryDirectory.appendingPathComponent("avi-demo", isDirectory: true))
        var stores: [RepositoryStore] = []
        for url in demo.repositories {
            log("opening \(url.lastPathComponent)")
            let store = RepositoryStore()
            await store.open(url)
            await store.refresh()
            stores.append(store)
        }
        for panel in panels + popupPanels where only.isEmpty || only.contains(panel.name) {
            log("panel \(panel.name)")
            guard let view = await panel.view(stores) else { continue }
            try await capturePanel(view, size: panel.size, asSheet: panel.asSheet, name: panel.name, into: output)
        }
        for section in SettingsSection.allCases where only.isEmpty || only.contains("settings-\(section.rawValue)") {
            log("panel settings-\(section.rawValue)")
            try await captureSettings(section, advanced: false, into: output)
            if section.advancedSummary != nil {
                try await captureSettings(section, advanced: true, into: output)
            }
        }
        settingsWindow?.close()
        NSApp.appearance = nil
        print("render-screens: saved to \(output.path)")
    }

    /// A sheet or pane drawn on its own, at its own size. `stores` are the
    /// demo repositories in order: skyline-web, infra-live, dotfiles.
    private struct Panel {
        let name: String
        let size: CGSize
        /// Presented as a sheet on a window of `size`, and the sheet captured.
        var asSheet = false
        let view: @MainActor ([RepositoryStore]) async -> AnyView?
    }

    private static var panels: [Panel] {
        [
            Panel(name: "sheet-push", size: CGSize(width: 520, height: 300)) { stores in
                AnyView(PushSheet(store: stores[0], dismiss: {}))
            },
            Panel(name: "sheet-push-pr", size: CGSize(width: 520, height: 640)) { stores in
                AnyView(PushSheet(store: stores[1], includesPullRequest: true, dismiss: {}))
            },
            // main is two commits ahead of origin, the last one a release.
            Panel(name: "sheet-push-tags", size: CGSize(width: 520, height: 340)) { stores in
                await stores[0].createTag(name: "v1.2.0", targetOID: "HEAD", message: nil)
                return AnyView(PushSheet(store: stores[0], dismiss: {}))
            },
            Panel(name: "commit-tags", size: CGSize(width: 560, height: 280)) { stores in
                let store = stores[0]
                store.commitSummary = "chore(release): prepare version 1.3.0"
                store.commitTags = [NewTag(name: "v1.3.0", message: "Release 1.3.0")]
                return AnyView(CommitPanelView(store: store).frame(width: 560, height: 280))
            },
            Panel(name: "sheet-commit-tag", size: CGSize(width: 380, height: 360)) { stores in
                AnyView(CommitTagSheet(store: stores[0], request: TagEditRequest(target: .stagedCommit, original: NewTag(name: "v1.3.0", message: "Release 1.3.0"))))
            },
            Panel(name: "commit-tags-empty", size: CGSize(width: 560, height: 280)) { stores in
                let store = stores[0]
                store.commitSummary = "chore(release): prepare version 0.10.1"
                store.commitTags = []
                return AnyView(CommitPanelView(store: store).frame(width: 560, height: 280))
            },
            Panel(name: "tag-banner", size: CGSize(width: 900, height: 60)) { stores in
                let store = stores[1]
                do {
                    _ = try await store.receiveTagProposal(
                        NewTag(name: "clusters-imported"),
                        at: "origin/main",
                        source: .agent(name: "Claude Code", session: "demo", title: nil)
                    )
                } catch {
                    log("tag-banner: \(error.localizedDescription)")
                    return nil
                }
                guard let proposal = store.tagProposals.first else { return nil }
                return AnyView(TagProposalBanner(store: store, proposal: proposal))
            },
            Panel(name: "diff", size: CGSize(width: 900, height: 360)) { stores in
                let store = stores[0]
                guard let file = store.entries.first(where: { $0.path == "src/routes/trips.ts" }) else { return nil }
                await store.select(file)
                return AnyView(FileDiffView(title: file.path, diff: store.diff))
            },
            // Every update step and a Git error, floating over a diff the way
            // they float over the workspace.
            Panel(name: "notices", size: CGSize(width: 900, height: 1180)) { stores in
                let store = stores[0]
                guard let file = store.entries.first(where: { $0.path == "src/routes/trips.ts" }) else { return nil }
                await store.select(file)
                return AnyView(
                    FileDiffView(title: file.path, diff: store.diff)
                        .overlay(alignment: .top) { NoticeGallery() }
                )
            },
            Panel(name: "notice-release-notes", size: CGSize(width: 520, height: 520)) { _ in
                AnyView(
                    AviNoticeCard(notice: UpdateNotice.make(.available(NoticeGallery.offer), handlers: UpdateNoticeHandlers()), expandsDetails: true)
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(HeroBackground())
                )
            }
        ]
    }

    /// Opens Avi's Settings window. Set by `ScreenshotHarnessHost`, which
    /// stands in for the workspace while the harness runs.
    static var openSettings: (@MainActor () -> Void)?

    /// Shows `section` in the Settings window itself, `settings-<section>`
    /// such as `settings-git`, so the capture has the window's own sidebar,
    /// search field, and toolbar.
    private static func captureSettings(_ section: SettingsSection, advanced: Bool, into output: URL) async throws {
        if section == .git {
            ConfigStore.shared.update { $0.pullRequests.keepHyphenated = ["k8s-*-*-ams1"] }
        }
        // `-advanced` captures open the section's Advanced settings; the
        // disclosure goes back to closed afterwards.
        UserDefaults.standard.set(advanced, forKey: SettingsAdvanced.key(for: section))
        defer { UserDefaults.standard.removeObject(forKey: SettingsAdvanced.key(for: section)) }
        let name = "settings-\(section.rawValue)" + (advanced ? "-advanced" : "")
        SettingsNavigation.shared.requested = section
        if settingsWindow == nil {
            guard let openSettings else { throw HarnessFailure(message: "nothing can open the Settings window") }
            openSettings()
        }
        try await Task.safeSleep(for: .milliseconds(1200))
        guard let window = settingsWindow else {
            let windows = NSApp.windows.map { "\($0.identifier?.rawValue ?? "?") \"\($0.title)\"" }
            throw HarnessFailure(message: "the Settings window did not open; windows: \(windows.joined(separator: ", "))")
        }
        // Open Advanced settings make a long page; the taller window shows it whole.
        window.setContentSize(CGSize(width: 820, height: advanced ? 1700 : 900))
        for appearance in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
            try await Task.safeSleep(for: .milliseconds(1800))
            try capture(window, to: output.appendingPathComponent("\(name)-\(appearance).png"))
        }
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
    }

    private struct HarnessFailure: Error, CustomStringConvertible {
        let message: String

        var description: String {
            message
        }
    }

    /// Hosts `view` in a window of its own, in both appearances. A sheet
    /// panel presents `view` as a sheet on that window and captures the sheet.
    private static func capturePanel(_ view: AnyView, size: CGSize, asSheet: Bool, name: String, into output: URL) async throws {
        let window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: 80, y: 80), size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: asSheet ? AnyView(SheetHost(sheet: view)) : view)
        window.setContentSize(size)
        window.orderFront(nil)
        defer { window.close() }
        for appearance in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
            try await Task.safeSleep(for: .milliseconds(1800))
            let target = asSheet ? (window.attachedSheet ?? window) : window
            try capture(target, to: output.appendingPathComponent("\(name)-\(appearance).png"))
        }
    }

    /// The sheets in the popup style, each presented the way the app does.
    private static var popupPanels: [Panel] {
        let sheetWindow = CGSize(width: 900, height: 760)
        return [
            Panel(name: "popup-push", size: sheetWindow, asSheet: true) { stores in
                AnyView(PushSheet(store: stores[0], dismiss: {}))
            },
            // A new branch with a pull request, the sheet at its tallest.
            Panel(name: "popup-push-pr", size: sheetWindow, asSheet: true) { stores in
                AnyView(PushSheet(store: stores[1], includesPullRequest: true, dismiss: {}))
            },
            Panel(name: "popup-merge", size: sheetWindow, asSheet: true) { stores in
                guard let branch = stores[0].refs.localBranches.first(where: { !$0.isCurrent }) else { return nil }
                return AnyView(MergeBranchSheet(store: stores[0], branch: branch))
            },
            Panel(name: "popup-delete-branch", size: sheetWindow, asSheet: true) { stores in
                guard let branch = stores[0].refs.localBranches.first(where: { !$0.isCurrent }) else { return nil }
                return AnyView(DeleteBranchSheet(store: stores[0], branch: branch, needsForce: { _ in }))
            },
            Panel(name: "popup-reset", size: sheetWindow, asSheet: true) { stores in
                guard let commit = stores[0].historyRows.dropFirst(2).first?.commit else { return nil }
                return AnyView(ResetToCommitSheet(store: stores[0], commit: commit))
            },
            Panel(name: "popup-create-branch", size: sheetWindow, asSheet: true) { stores in
                AnyView(CreateBranchSheet(store: stores[0]))
            },
            Panel(name: "popup-stash", size: sheetWindow, asSheet: true) { stores in
                let files = Array(stores[0].entries.prefix(3))
                guard !files.isEmpty else { return nil }
                return AnyView(StashFilesSheet(store: stores[0], request: FileStashRequest(files: files)))
            },
            Panel(name: "popup-plan-revision", size: sheetWindow, asSheet: true) { stores in
                AnyView(PlanRevisionSheet(
                    store: stores[0],
                    request: PlanRevisionRequest(draftIDs: [UUID(), UUID()], title: "All 2 commits", suggestion: "Put the tests in their own commit.")
                ))
            },
            Panel(name: "popup-rebase", size: sheetWindow, asSheet: true) { stores in
                guard let branch = stores[0].refs.localBranches.first(where: { !$0.isCurrent }) else { return nil }
                return AnyView(RebaseBranchSheet(store: stores[0], onto: branch))
            },
            Panel(name: "popup-worktree", size: sheetWindow, asSheet: true) { stores in
                guard let branch = stores[0].refs.localBranches.first(where: { !$0.isCurrent }) else { return nil }
                return AnyView(WorktreeCheckoutSheet(store: stores[0], branch: branch))
            },
            Panel(name: "popup-interactive-rebase", size: sheetWindow, asSheet: true) { stores in
                guard let branch = stores[0].refs.localBranches.first(where: { !$0.isCurrent }) else { return nil }
                return AnyView(InteractiveRebaseSheet(store: stores[0], onto: branch))
            },
            Panel(name: "popup-create-tag", size: sheetWindow, asSheet: true) { stores in
                guard let oid = stores[0].branch?.oid else { return nil }
                return AnyView(CreateTagSheet(store: stores[0], targetOID: oid))
            },
            Panel(name: "popup-commit-tag", size: sheetWindow, asSheet: true) { stores in
                AnyView(CommitTagSheet(store: stores[0], request: TagEditRequest(target: .stagedCommit, original: nil)))
            },
            Panel(name: "popup-ai-reword", size: sheetWindow, asSheet: true) { stores in
                AnyView(AIRewordSheet(
                    store: stores[0],
                    preview: AIRewordPreview(
                        oid: "94fec05b486d",
                        oldMessage: "fix stuff",
                        proposed: "fix(trips): hide trips that were archived\n\nArchived trips stayed in the list until the next reload."
                    )
                ))
            },
            Panel(name: "popup-token", size: sheetWindow, asSheet: true) { _ in
                AnyView(PATEntrySheet(
                    providerName: "GitLab",
                    instructions: "Create a token with the api and read_user scopes in GitLab > Preferences > Access Tokens.",
                    instanceURLDefault: "https://gitlab.com",
                    requiresInstanceURL: true,
                    onSubmit: { _, _ in }
                ))
            },
            Panel(name: "popup-github-sign-in", size: sheetWindow, asSheet: true) { _ in
                AnyView(GitHubDeviceFlowSheet(onComplete: { _ in }))
            },
            Panel(name: "popup-picker", size: sheetWindow, asSheet: true) { _ in
                AnyView(RepositoryPickerView(openRepository: { _ in }, onClone: {}, onDismiss: {}, presentation: .sheet))
            },
            Panel(name: "popup-command-palette", size: sheetWindow) { stores in
                AnyView(
                    Color(nsColor: .windowBackgroundColor)
                        .overlay {
                            CommandPaletteOverlay(
                                commands: CommandRegistry.commands(store: stores[0], setSelection: { _ in }, openCreateBranch: {}),
                                isPresented: .constant(true)
                            )
                        }
                )
            }
        ]
    }

    private static func capture(_ window: NSWindow, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(command: "screencapture", exitCode: process.terminationStatus, stderr: "")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("render-screens: \(message)\n".utf8))
    }
}

/// The workspace window's stand-in while the harness runs, from where it
/// can open the Settings window.
public struct ScreenshotHarnessHost: View {
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                ScreenshotHarness.openSettings = { openSettings() }
            }
    }
}

/// Presents `sheet` once it is on screen, as the app's windows do.
private struct SheetHost: View {
    let sheet: AnyView
    @State private var isPresented = false

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .sheet(isPresented: $isPresented) {
                sheet
            }
            .onAppear {
                isPresented = true
            }
    }
}

/// The update notice at each step, and an error notice, for screenshots.
private struct NoticeGallery: View {
    static let offer = UpdateOffer(
        version: "1.5.0",
        currentVersion: "1.4.2",
        size: 7_637_599,
        notes: """
        ### Added
        - Sheets and alerts float as Rex-style popups, and updates download and install from a notice instead of Sparkle's windows.
        - **Push** shows its options as switches with what each one does.

        ### Fixed
        - Long Git errors fold to three lines, with `Show Full Message` and Copy.
        """,
        fullNotesURL: URL(string: "https://github.com/mrcat71/avi/blob/main/CHANGELOG.md")
    )

    var body: some View {
        let handlers = UpdateNoticeHandlers()
        let phases: [UpdatePhase] = [
            .available(Self.offer),
            .downloading(Self.offer, received: 3_145_728, expected: 7_637_599),
            .ready(Self.offer),
            .upToDate(currentVersion: "1.4.2")
        ]
        let error = AviNotice.error(
            id: "error",
            text: "Could not push main to origin: ! [rejected] main -> main (fetch first)\nerror: failed to push some refs to 'github.com:skyline/skyline-web.git'\nhint: Updates were rejected because the remote contains work that you do not have locally. Integrate the remote changes (e.g. 'git pull ...') before pushing again.",
            onDismiss: {}
        )
        VStack(spacing: 10) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                AviNoticeCard(notice: Self.still(UpdateNotice.make(phase, handlers: handlers), id: "\(index)"))
            }
            AviNoticeCard(notice: error)
        }
        .padding(.top, 16)
    }

    /// A copy that stays put for the capture.
    private static func still(_ notice: AviNotice, id: String) -> AviNotice {
        var notice = notice
        notice.id = id
        notice.autoDismiss = nil
        return notice
    }
}
#endif
