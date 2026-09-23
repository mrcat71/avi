import Foundation
import GitKit

/// Installs the `avi` command and the agent skill into your home folder.
/// It only ever writes the files it owns, and it refuses to overwrite a file
/// someone else wrote or one you edited unless told to.
public struct AgentInstaller: Sendable {
    public enum Target: String, CaseIterable, Identifiable, Sendable {
        case command
        case claude
        case codex

        public var id: String {
            rawValue
        }

        public var title: String {
            switch self {
            case .command: return "avi command"
            case .claude: return "Claude Code skill"
            case .codex: return "Codex skill"
            }
        }
    }

    public enum State: Equatable, Sendable {
        case notInstalled
        case installed
        /// Written by another Avi version, or pointing at another copy of Avi.
        case outdated(String)
        /// Written by this version and changed since.
        case modified
        /// A file Avi did not write sits where Avi would install.
        case foreign
        /// The agent is not installed here.
        case unavailable(String)
    }

    public enum InstallError: Error, Equatable, LocalizedError {
        case needsConfirmation(Target, State)
        case unavailable(Target, String)
        /// macOS runs a quarantined app from a temporary copy until it is moved,
        /// and a shim pointing there would break as soon as Avi quits.
        case translocated

        public var errorDescription: String? {
            switch self {
            case .needsConfirmation(let target, .modified):
                return "The \(target.title) was edited after Avi installed it. Confirm to overwrite it."
            case .needsConfirmation(let target, _):
                return "Something Avi did not install is already at the \(target.title) location. Confirm to replace it."
            case .unavailable(let target, let reason):
                return "Cannot install the \(target.title): \(reason)"
            case .translocated:
                return "Move Avi to the Applications folder and open it from there, then install the avi command."
            }
        }
    }

    public let home: URL
    public let executablePath: String
    public let version: String
    /// Codex honors `CODEX_HOME`; Avi launched from Finder never sees it, the CLI may.
    public let codexHome: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        executablePath: String = Bundle.main.executablePath ?? CommandLine.arguments[0],
        version: String = GitKit.version,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.home = home
        self.executablePath = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        self.version = version
        if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            codexHome = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        }
    }

    // MARK: Locations

    public func location(of target: Target) -> URL {
        switch target {
        case .command:
            return home.appendingPathComponent(".local/bin/avi")
        case .claude:
            return home.appendingPathComponent(".claude/skills/\(AgentSkillContent.name)", isDirectory: true)
        case .codex:
            return codexHome.appendingPathComponent("skills/\(AgentSkillContent.name)", isDirectory: true)
        }
    }

    private var claudeHome: URL {
        home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// Files Avi writes for a target, relative to its location, with contents.
    private func files(for target: Target) -> [(String, String)] {
        switch target {
        case .command:
            return [("", shimScript)]
        case .claude:
            return [("SKILL.md", AgentSkillContent.skillMarkdown(version: version))]
        case .codex:
            return [
                ("SKILL.md", AgentSkillContent.skillMarkdown(version: version)),
                ("agents/openai.yaml", AgentSkillContent.codexInterface)
            ]
        }
    }

    // MARK: State

    public func state(of target: Target) -> State {
        switch target {
        case .command:
            return commandState()
        case .claude:
            guard exists(claudeHome) else { return .unavailable("Claude Code is not set up here (no ~/.claude).") }
            return skillState(at: location(of: .claude))
        case .codex:
            guard exists(codexHome) else { return .unavailable("Codex is not set up here (no \(tildePath(codexHome))).") }
            return skillState(at: location(of: .codex))
        }
    }

    private func skillState(at directory: URL) -> State {
        let skill = directory.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: skill, encoding: .utf8) else {
            return exists(directory) ? .foreign : .notInstalled
        }
        guard let installed = AgentSkillContent.installedVersion(in: text) else { return .foreign }
        guard installed == version else { return .outdated("Installed by Avi \(installed)") }
        return text == AgentSkillContent.skillMarkdown(version: version) ? .installed : .modified
    }

    private func commandState() -> State {
        let url = location(of: .command)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: url.path) ? .foreign : .notInstalled
        }
        guard text.contains(Self.shimMarker) else { return .foreign }
        return text == shimScript ? .installed : .outdated("Points at another copy of Avi")
    }

    // MARK: Changes

    /// Installs or updates `target`. Without `force`, refuses when the current
    /// files were edited or were not written by Avi.
    public func install(_ target: Target, force: Bool = false) throws {
        if target == .command, executablePath.contains("/AppTranslocation/") {
            throw InstallError.translocated
        }
        let current = state(of: target)
        switch current {
        case .unavailable(let reason):
            throw InstallError.unavailable(target, reason)
        case .modified, .foreign:
            guard force else { throw InstallError.needsConfirmation(target, current) }
        case .notInstalled, .installed, .outdated:
            break
        }
        let base = location(of: target)
        for (relative, contents) in files(for: target) {
            let url = relative.isEmpty ? base : base.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url, options: .atomic)
            if target == .command {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
    }

    /// Removes what Avi installed for `target`. Files Avi did not write, or that
    /// you edited, stay unless `force` is set; the skill folder goes only once
    /// it is empty.
    public func remove(_ target: Target, force: Bool = false) throws {
        let current = state(of: target)
        if current == .foreign || current == .modified, !force {
            throw InstallError.needsConfirmation(target, current)
        }
        let base = location(of: target)
        let fileManager = FileManager.default
        for (relative, _) in files(for: target) {
            let url = relative.isEmpty ? base : base.appendingPathComponent(relative)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        guard target != .command else { return }
        for directory in [base.appendingPathComponent("agents", isDirectory: true), base] {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory.path), contents.isEmpty {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    // MARK: Command shim

    static let shimMarker = "avi-cli-shim"

    /// A tiny script rather than a symlink: the app binary resolves its
    /// frameworks relative to the real bundle, and the script keeps that path.
    var shimScript: String {
        let quoted = "'" + executablePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
        #!/bin/sh
        # \(Self.shimMarker): installed by Avi. Reinstall from Avi > Settings > Agents if Avi moves.
        exec \(quoted) --cli "$@"

        """
    }

    // MARK: Helpers

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func tildePath(_ url: URL) -> String {
        let path = url.path
        return path.hasPrefix(home.path + "/") ? "~" + path.dropFirst(home.path.count) : path
    }
}
