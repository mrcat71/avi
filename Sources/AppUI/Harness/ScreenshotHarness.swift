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
        for panel in panels where only.isEmpty || only.contains(panel.name) {
            log("panel \(panel.name)")
            guard let view = await panel.view(stores) else { continue }
            try await capturePanel(view, size: panel.size, name: panel.name, into: output)
        }
        NSApp.appearance = nil
        print("render-screens: saved to \(output.path)")
    }

    /// A sheet or pane drawn on its own, at its own size. `stores` are the
    /// demo repositories in order: skyline-web, infra-live, dotfiles.
    private struct Panel {
        let name: String
        let size: CGSize
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
            Panel(name: "settings-git", size: CGSize(width: 820, height: 900)) { _ in
                ConfigStore.shared.update { $0.pullRequests.keepHyphenated = ["k8s-*-*-ams1"] }
                SettingsNavigation.shared.requested = .git
                return AnyView(SettingsRoot())
            },
            Panel(name: "settings-appearance", size: CGSize(width: 820, height: 700)) { _ in
                SettingsNavigation.shared.requested = .appearance
                return AnyView(SettingsRoot())
            }
        ]
    }

    /// Hosts `view` in a window of its own, in both appearances.
    private static func capturePanel(_ view: AnyView, size: CGSize, name: String, into output: URL) async throws {
        let window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: 80, y: 80), size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(size)
        window.orderFront(nil)
        defer { window.close() }
        for appearance in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
            try await Task.safeSleep(for: .milliseconds(1800))
            try capture(window, to: output.appendingPathComponent("\(name)-\(appearance).png"))
        }
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
#endif
