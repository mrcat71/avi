import AppKit
import Foundation

struct DetectedTool: Identifiable {
    let id: String // "git", "codex", "claude", ...
    let displayName: String
    let detectedPath: String?
    let isAvailable: Bool
    let version: String?
}

/// Detects developer tools the app integrates with. Filled in fully in Phase 3.
enum ExternalToolsScanner {
    struct ToolSpec {
        let id: String
        let displayName: String
        let executableName: String // empty for GUI apps
        let versionArgs: [String]
        let bundleID: String? // for GUI apps via mdfind
    }

    static let specs: [ToolSpec] = [
        ToolSpec(id: "git", displayName: "Git", executableName: "git", versionArgs: ["--version"], bundleID: nil),
        ToolSpec(id: "gh", displayName: "GitHub CLI", executableName: "gh", versionArgs: ["--version"], bundleID: nil),
        ToolSpec(id: "glab", displayName: "GitLab CLI", executableName: "glab", versionArgs: ["--version"], bundleID: nil),
        ToolSpec(id: "codex", displayName: "Codex CLI", executableName: "codex", versionArgs: ["--version"], bundleID: nil),
        ToolSpec(id: "claude", displayName: "Claude Code CLI", executableName: "claude", versionArgs: ["--version"], bundleID: nil),
        ToolSpec(id: "editor", displayName: "VS Code", executableName: "code", versionArgs: ["--version"], bundleID: "com.microsoft.VSCode"),
        ToolSpec(id: "terminal", displayName: "iTerm2", executableName: "", versionArgs: [], bundleID: "com.googlecode.iterm2"),
        ToolSpec(id: "diffTool", displayName: "Diff Tool", executableName: "", versionArgs: [], bundleID: nil),
        ToolSpec(id: "mergeTool", displayName: "Merge Tool", executableName: "", versionArgs: [], bundleID: nil)
    ]

    /// Run on a background queue.
    static func detectAll() -> [DetectedTool] {
        specs.map { detect($0) }
    }

    static func detect(_ spec: ToolSpec) -> DetectedTool {
        // GUI apps: look via mdfind / NSWorkspace.
        if let bundleID = spec.bundleID, !bundleID.isEmpty {
            let path = findAppPath(bundleID: bundleID)
            return DetectedTool(
                id: spec.id,
                displayName: spec.displayName,
                detectedPath: path,
                isAvailable: path != nil,
                version: nil
            )
        }

        // CLI: which + standard locations.
        guard !spec.executableName.isEmpty else {
            return DetectedTool(id: spec.id, displayName: spec.displayName, detectedPath: nil, isAvailable: false, version: nil)
        }
        let path = findExecutable(named: spec.executableName)
        var version: String? = nil
        if let path, !spec.versionArgs.isEmpty {
            version = runVersionCommand(path: path, args: spec.versionArgs)
        }
        return DetectedTool(
            id: spec.id,
            displayName: spec.displayName,
            detectedPath: path,
            isAvailable: path != nil,
            version: version
        )
    }

    private static func findExecutable(named name: String) -> String? {
        // Try `which` first.
        if let path = runProcess(executable: "/usr/bin/which", arguments: [name])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        // Fall back to a list of common bin dirs.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin",
            "\(home)/.local/bin", "\(home)/.cargo/bin", "\(home)/.nix-profile/bin"
        ]
        for dir in dirs {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func findAppPath(bundleID: String) -> String? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        return nil
    }

    private static func runVersionCommand(path: String, args: [String]) -> String? {
        runProcess(executable: path, arguments: args)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init)
    }

    private static func runProcess(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
