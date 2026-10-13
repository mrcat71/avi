import AppKit
import OSLog

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

    /// Opens a terminal window in `folder`, in the app set in Settings > Git >
    /// Terminal. Terminal, iTerm2, Ghostty, WezTerm, and most others start in
    /// a folder they are asked to open.
    static func openInTerminal(_ folder: URL) {
        let app = terminalApp(configured: ConfigStore.shared.config.git.terminalApp)
        let log = log
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                log.error("Could not open \(folder.path, privacy: .private) in \(app.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// The configured terminal app, or Terminal when none is set or it is gone.
    static func terminalApp(configured: String) -> URL {
        let path = (configured.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return defaultTerminal }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
