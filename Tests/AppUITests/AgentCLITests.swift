@testable import AppUI
import Foundation
import Testing

@Suite("avi command")
struct AgentCLITests {
    typealias Invocation = AgentCLI.Invocation

    @Test(arguments: [
        ([], Invocation(command: .help)),
        (["--help"], Invocation(command: .help)),
        (["version"], Invocation(command: .version)),
        (["status", "--json"], Invocation(command: .status(repo: nil), json: true)),
        (["status", "--repo", "/r"], Invocation(command: .status(repo: "/r"))),
        (["open", ".", "--focus"], Invocation(command: .open(path: "."), focus: true)),
        (["skill"], Invocation(command: .skillStatus)),
        (["skill", "install", "--codex", "--force"], Invocation(command: .skillInstall(targets: [.codex], force: true))),
        (["skill", "remove"], Invocation(command: .skillRemove(targets: [], force: false)))
    ] as [([String], Invocation)])
    func parsesCommands(arguments: [String], expected: Invocation) throws {
        #expect(try AgentCLI.parse(arguments) == expected)
    }

    @Test func parsesAPlanProposal() throws {
        let parsed = try AgentCLI.parse(["propose", "--file", "-", "--agent", "Codex", "--session", "t1", "--replace", "--json"])
        guard case .propose(let propose) = parsed.command else {
            Issue.record("expected propose")
            return
        }
        #expect(propose.planFile == "-")
        #expect(propose.agent == "Codex")
        #expect(propose.session == "t1")
        #expect(propose.replace)
        #expect(parsed.json)
    }

    @Test func parsesAMessageProposalWithFilesAfterDoubleDash() throws {
        let parsed = try AgentCLI.parse(["propose", "-m", "feat: x", "-m", "body", "a.swift", "--", "-odd-name.swift"])
        guard case .propose(let propose) = parsed.command else {
            Issue.record("expected propose")
            return
        }
        #expect(propose.messages == ["feat: x", "body"])
        #expect(propose.files == ["a.swift", "-odd-name.swift"])
    }

    @Test(arguments: [
        (["launch"], AgentCLI.ParseError.unknownCommand("launch")),
        (["status", "--bogus"], .unknownOption("--bogus")),
        (["propose"], .planOrMessage),
        (["propose", "--file", "p.json", "-m", "x"], .planOrMessage),
        (["propose", "--file"], .missingValue("--file")),
        (["propose", "--file", "p.json", "a.swift"], .unexpected("a.swift"))
    ] as [([String], AgentCLI.ParseError)])
    func rejectsBadUsage(arguments: [String], expected: AgentCLI.ParseError) {
        #expect(throws: expected) { try AgentCLI.parse(arguments) }
    }

    @Test(arguments: [
        (["CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "c1"], "Claude Code", "c1"),
        (["CODEX_THREAD_ID": "t9", "CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "c1"], "Codex", "t9"),
        (["CLAUDECODE": "1"], "Claude Code", "default")
    ] as [([String: String], String, String)])
    func detectsTheCallingAgent(environment: [String: String], name: String, session: String) throws {
        let detected = try #require(AgentCLI.detectAgent(in: environment))
        #expect(detected.name == name)
        #expect(detected.session == session)
    }

    @Test func unknownCallersAreNotGuessed() {
        #expect(AgentCLI.detectAgent(in: ["TERM": "xterm"]) == nil)
    }

    @Test func pathsFromASubdirectoryBecomeRootRelative() {
        let cwd = URL(fileURLWithPath: "/repo/Sources/App", isDirectory: true)
        #expect(AgentCLI.repositoryRelative("View.swift", cwd: cwd, root: "/repo") == "Sources/App/View.swift")
        #expect(AgentCLI.repositoryRelative("../../README.md", cwd: cwd, root: "/repo") == "README.md")
        #expect(AgentCLI.repositoryRelative("/repo/a.txt", cwd: cwd, root: "/repo") == "a.txt")
        #expect(AgentCLI.repositoryRelative("/elsewhere/a.txt", cwd: cwd, root: "/repo") == "/elsewhere/a.txt")
    }
}

@Suite("Agent installer", .serialized)
struct AgentInstallerTests {
    private func home(claude: Bool = true, codex: Bool = true) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("avi-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if claude {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        }
        if codex {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        }
        return home
    }

    private func installer(_ home: URL, version: String = "0.4.0", executable: String = "/Applications/Avi.app/Contents/MacOS/Avi") -> AgentInstaller {
        AgentInstaller(home: home, executablePath: executable, version: version, environment: [:])
    }

    @Test func agentsThatAreNotSetUpAreUnavailable() throws {
        let home = try home(claude: false, codex: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = installer(home)
        guard case .unavailable = installer.state(of: .claude), case .unavailable = installer.state(of: .codex) else {
            Issue.record("expected unavailable")
            return
        }
        #expect(throws: AgentInstaller.InstallError.self) { try installer.install(.claude) }
    }

    @Test func installsBothSkillsAndTheCommand() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = installer(home)
        for target in AgentInstaller.Target.allCases {
            try installer.install(target)
            #expect(installer.state(of: target) == .installed)
        }
        let skill = try String(contentsOf: home.appendingPathComponent(".claude/skills/avi/SKILL.md"), encoding: .utf8)
        #expect(skill.hasPrefix("---\nname: avi\n"))
        #expect(skill.contains("<!-- avi-skill 0.4.0 -->"))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/skills/avi/agents/openai.yaml").path))

        let shim = home.appendingPathComponent(".local/bin/avi")
        #expect(try String(contentsOf: shim, encoding: .utf8).contains("exec '/Applications/Avi.app/Contents/MacOS/Avi' --cli \"$@\""))
        #expect(FileManager.default.isExecutableFile(atPath: shim.path))
    }

    @Test func editedAndForeignFilesNeedConfirmation() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = installer(home)
        try installer.install(.claude)
        let skill = home.appendingPathComponent(".claude/skills/avi/SKILL.md")
        try (String(contentsOf: skill, encoding: .utf8) + "\nmy note\n").write(to: skill, atomically: true, encoding: .utf8)
        #expect(installer.state(of: .claude) == .modified)
        #expect(throws: AgentInstaller.InstallError.needsConfirmation(.claude, .modified)) { try installer.install(.claude) }
        #expect(throws: AgentInstaller.InstallError.needsConfirmation(.claude, .modified)) { try installer.remove(.claude) }
        try installer.install(.claude, force: true)
        #expect(installer.state(of: .claude) == .installed)

        try "---\nname: avi\n---\nsomeone else's\n".write(to: skill, atomically: true, encoding: .utf8)
        #expect(installer.state(of: .claude) == .foreign)
        #expect(throws: AgentInstaller.InstallError.needsConfirmation(.claude, .foreign)) { try installer.install(.claude) }
    }

    @Test func olderCopiesAndMovedAppsAreOutdated() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try installer(home, version: "0.3.9").install(.codex)
        try installer(home, executable: "/old/Avi.app/Contents/MacOS/Avi").install(.command)
        let current = installer(home)
        #expect(current.state(of: .codex) == .outdated("Installed by Avi 0.3.9"))
        #expect(current.state(of: .command) == .outdated("Points at another copy of Avi"))
        try current.install(.codex)
        #expect(current.state(of: .codex) == .installed)
    }

    @Test func removeTakesOnlyWhatAviWrote() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = installer(home)
        try installer.install(.codex)
        let extra = home.appendingPathComponent(".codex/skills/avi/notes.md")
        try "mine".write(to: extra, atomically: true, encoding: .utf8)
        try installer.remove(.codex)
        #expect(FileManager.default.fileExists(atPath: extra.path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/skills/avi/SKILL.md").path))
    }

    @Test func codexHomeFromTheEnvironmentWins() throws {
        let home = try home(codex: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let installer = AgentInstaller(home: home, executablePath: "/x", version: "0.4.0", environment: ["CODEX_HOME": custom.path])
        try installer.install(.codex)
        #expect(FileManager.default.fileExists(atPath: custom.appendingPathComponent("skills/avi/SKILL.md").path))
    }

    @Test func skillDescribesTheCommandsItNeeds() {
        let skill = AgentSkillContent.skillMarkdown(version: "1.2.3")
        #expect(AgentSkillContent.installedVersion(in: skill) == "1.2.3")
        for needed in ["avi status --json", "avi propose --file", "file_claimed", "edited_by_user", "unknown_path", "Never"] {
            #expect(skill.contains(needed), "\(needed)")
        }
        let description = skill.split(separator: "\n").first { $0.hasPrefix("description: ") } ?? ""
        #expect(description.count <= 1024)
    }
}
