import AppKit
import GitKit
import OSLog
import SwiftUI

/// What you can do with a repository's or worktree's folder outside Avi.
@MainActor
enum FolderActions {
    private static let log = Logger(subsystem: "com.svinarenko.avi", category: "folders")
    private static let defaultTerminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)

    static func copyPath(_ folder: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(folder.path, forType: .string)
    }

    static func revealInFinder(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    /// Opens a terminal window in `folder`, in the app set in Settings >
    /// External Tools > Terminal. Terminal, iTerm2, Ghostty, WezTerm, and most
    /// others start in a folder they are asked to open.
    static func openInTerminal(_ folder: URL) {
        open(folder, withApplicationAt: terminalApp(configured: ConfigStore.shared.config.git.terminalApp))
    }

    /// The editor Open in Editor uses, from Settings > External Tools >
    /// Editor; nil when none is set or installed.
    static var editor: EditorTarget? {
        EditorTarget.resolve(configured: ConfigStore.shared.config.git.externalEditor)
    }

    /// Opens `url`, a folder or a file, in the editor from Settings.
    static func openInEditor(_ url: URL) {
        switch editor {
        case let .app(app)?:
            open(url, withApplicationAt: app)
        case let .command(executable)?:
            Task {
                do {
                    let result = try await ProcessRunner.run(executable: executable, arguments: [url.path])
                    if result.exitCode != 0 {
                        let reason = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
                        report("Could not open \(url.lastPathComponent) with \(executable.lastPathComponent): "
                            + (reason.isEmpty ? "exit \(result.exitCode)" : reason))
                    }
                } catch {
                    report("Could not open \(url.lastPathComponent) with \(executable.lastPathComponent): \(error.localizedDescription)")
                }
            }
        case nil:
            report("No editor to open \(url.lastPathComponent) in. Choose one in Settings > External Tools.")
        }
    }

    private static func open(_ url: URL, withApplicationAt app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in
                report("Could not open \(url.lastPathComponent) in \(KnownApps.displayName(of: app)): \(error.localizedDescription)")
            }
        }
    }

    private static func report(_ message: String) {
        log.error("\(message, privacy: .private)")
        AviNoticeCenter.shared.show(.error(id: "folder-actions", text: message) {
            AviNoticeCenter.shared.dismiss(id: "folder-actions")
        })
    }

    /// The configured terminal app, or Terminal when none is set or it is gone.
    static func terminalApp(configured: String) -> URL {
        let path = (configured.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return defaultTerminal }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// "Open in <editor>" for a folder or file, left out while no editor is set
/// or installed.
struct OpenInEditorButton: View {
    let url: URL?

    var body: some View {
        if let url, let editor = FolderActions.editor {
            Button("Open in \(editor.name)") {
                FolderActions.openInEditor(url)
            }
        }
    }
}
