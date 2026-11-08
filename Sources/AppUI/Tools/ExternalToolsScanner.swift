import Foundation
import GitKit

/// A command-line tool Avi runs, with the path Settings can set for it.
enum CLITool: String, CaseIterable, Identifiable, Sendable {
    case git
    case gh
    case glab
    case codex
    case claude

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .git: return "Git"
        case .gh: return "GitHub CLI"
        case .glab: return "GitLab CLI"
        case .codex: return "Codex CLI"
        case .claude: return "Claude Code CLI"
        }
    }

    /// What Avi runs it for.
    var purpose: String {
        switch self {
        case .git: return "Every Git command"
        case .gh: return "Pull requests, accounts, and clones on GitHub"
        case .glab: return "Merge requests, accounts, and clones on GitLab"
        case .codex: return "AI commands that start with codex"
        case .claude: return "AI commands that start with claude"
        }
    }

    var overridePath: WritableKeyPath<ExternalToolsConfig, String> {
        switch self {
        case .git: return \.gitPath
        case .gh: return \.ghPath
        case .glab: return \.glabPath
        case .codex: return \.codexPath
        case .claude: return \.claudePath
        }
    }
}

/// Where Avi runs a tool from, and the version it reports.
struct CLIToolStatus: Identifiable, Equatable, Sendable {
    let tool: CLITool
    /// What Avi runs: the path from Settings when it is an executable, else
    /// where Avi finds the tool; nil when it finds none.
    let path: String?
    let version: String?

    var id: String {
        tool.id
    }
}

/// Finds the command-line tools Avi runs. Blocking: call off the main thread.
enum ExternalToolsScanner {
    static func status(of tool: CLITool, config: ExternalToolsConfig) -> CLIToolStatus {
        let path = path(of: tool, config: config)
        return CLIToolStatus(tool: tool, path: path, version: path.flatMap(version))
    }

    /// The executable Avi runs for `tool`, as each part of Avi looks for it.
    static func path(of tool: CLITool, config: ExternalToolsConfig) -> String? {
        let chosen = config[keyPath: tool.overridePath]
        switch tool {
        case .git:
            // CLIGitProvider runs /usr/bin/git unless Settings names another.
            return ToolPath.executable(chosen) ?? ToolPath.executable(GitCommandOptions.defaultExecutable.path)
        case .gh, .glab:
            return ProviderCLISupport.resolve(preferred: ToolPath.executable(chosen) ?? "", name: tool.rawValue)
        case .codex, .claude:
            return ToolPath.executable(chosen) ?? findExecutable(named: tool.rawValue)
        }
    }

    private static func findExecutable(named name: String) -> String? {
        let found = runProcess(executable: "/usr/bin/which", arguments: [name])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let path = found, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin",
            "\(home)/.local/bin", "\(home)/.cargo/bin", "\(home)/.nix-profile/bin"
        ]
        return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func version(of path: String) -> String? {
        runProcess(executable: path, arguments: ["--version"])?
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
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            // Read before waiting, so output larger than the pipe's buffer
            // cannot leave the tool blocked on a write.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
