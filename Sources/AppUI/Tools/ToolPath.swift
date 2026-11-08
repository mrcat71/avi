import Foundation
import GitKit

/// Paths typed into Settings for command-line tools.
enum ToolPath {
    /// `text` as an executable file, `~` expanded, or nil when it is empty
    /// or names no executable.
    static func executable(_ text: String, fileManager: FileManager = .default) -> String? {
        let path = (text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty, fileManager.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    /// Why Settings ignores `text`, or nil when it is empty or usable.
    static func problem(_ text: String, fileManager: FileManager = .default) -> String? {
        let path = (text.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty, executable(text, fileManager: fileManager) == nil else { return nil }
        return fileManager.fileExists(atPath: path) ? "Not an executable file" : "Nothing at this path"
    }
}

extension GitCommandOptions {
    /// Git's part of Avi's settings. A git path that names no executable is
    /// ignored, so a typo cannot stop every command.
    init(settings config: AviConfig) {
        self.init(
            executable: ToolPath.executable(config.externalTools.gitPath).map { URL(fileURLWithPath: $0) },
            fallbackName: config.git.defaultAuthorName.trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackEmail: config.git.defaultAuthorEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            signCommits: config.git.signCommits,
            pruneOnFetch: config.git.pruneOnFetch,
            logCommands: config.advanced.verboseLogging
        )
    }
}

extension GitCommandOptions {
    /// How a git command outside `CLIGitProvider` starts: the git from
    /// Settings > External Tools, else the first `git` on PATH.
    static func invocation(_ arguments: [String]) -> (executable: URL, arguments: [String]) {
        if let git = current.executable {
            return (git, arguments)
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments)
    }
}
