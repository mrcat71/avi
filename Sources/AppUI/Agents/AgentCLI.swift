import Foundation
import GitKit

/// The `avi` command: the app binary run as `Avi --cli ...` through the shim
/// in `~/.local/bin`. Talks to the running app over the control socket.
public enum AgentCLI {
    public enum ExitCode {
        public static let ok: Int32 = 0
        public static let rejected: Int32 = 1
        public static let usage: Int32 = 2
        public static let unreachable: Int32 = 3
    }

    public static func run(_ arguments: [String]) -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let invocation: Invocation
        do {
            invocation = try parse(arguments)
        } catch {
            printError("avi: \(error.localizedDescription)\nRun `avi help` for usage.")
            return ExitCode.usage
        }
        let runner = Runner(
            invocation: invocation,
            environment: environment,
            workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).resolvingSymlinksInPath()
        )
        return runner.run()
    }

    // MARK: - Parsing

    struct Invocation: Equatable {
        enum Command: Equatable {
            case status(repo: String?)
            case open(path: String?)
            case propose(Propose)
            case skillStatus
            case skillInstall(targets: [AgentInstaller.Target], force: Bool)
            case skillRemove(targets: [AgentInstaller.Target], force: Bool)
            case version
            case help
        }

        var command: Command
        var json = false
        var focus = false
    }

    struct Propose: Equatable {
        var repo: String?
        var agent: String?
        var session: String?
        var title: String?
        var planFile: String?
        var messages: [String] = []
        var files: [String] = []
        var replace = false
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case unknownCommand(String)
        case unknownOption(String)
        case missingValue(String)
        case unexpected(String)
        case planOrMessage

        var errorDescription: String? {
            switch self {
            case .unknownCommand(let name): return "unknown command `\(name)`"
            case .unknownOption(let name): return "unknown option `\(name)`"
            case .missingValue(let name): return "`\(name)` needs a value"
            case .unexpected(let value): return "unexpected argument `\(value)`"
            case .planOrMessage: return "`propose` needs either `--file PLAN.json` or `-m MESSAGE`, not both"
            }
        }
    }

    static func parse(_ arguments: [String]) throws -> Invocation {
        var args = arguments[...]
        guard let name = args.popFirst() else { return Invocation(command: .help) }
        switch name {
        case "help", "--help", "-h":
            return Invocation(command: .help)
        case "version", "--version":
            return Invocation(command: .version)
        case "status":
            var repo: String?
            var json = false
            while let arg = args.popFirst() {
                switch arg {
                case "--repo": repo = try value(for: arg, from: &args)
                case "--json": json = true
                default: throw ParseError.unknownOption(arg)
                }
            }
            return Invocation(command: .status(repo: repo), json: json)
        case "open":
            var path: String?
            var invocation = Invocation(command: .open(path: nil))
            while let arg = args.popFirst() {
                switch arg {
                case "--focus": invocation.focus = true
                case "--json": invocation.json = true
                default:
                    guard !arg.hasPrefix("-"), path == nil else { throw arg.hasPrefix("-") ? ParseError.unknownOption(arg) : ParseError.unexpected(arg) }
                    path = arg
                }
            }
            invocation.command = .open(path: path)
            return invocation
        case "propose":
            return try parsePropose(&args)
        case "skill":
            return try parseSkill(&args)
        default:
            throw ParseError.unknownCommand(name)
        }
    }

    private static func parsePropose(_ args: inout ArraySlice<String>) throws -> Invocation {
        var propose = Propose()
        var invocation = Invocation(command: .help)
        var filesOnly = false
        while let arg = args.popFirst() {
            if filesOnly {
                propose.files.append(arg)
                continue
            }
            switch arg {
            case "--repo": propose.repo = try value(for: arg, from: &args)
            case "--agent": propose.agent = try value(for: arg, from: &args)
            case "--session": propose.session = try value(for: arg, from: &args)
            case "--title": propose.title = try value(for: arg, from: &args)
            case "--file", "-F": propose.planFile = try value(for: arg, from: &args)
            case "-m", "--message": try propose.messages.append(value(for: arg, from: &args))
            case "--replace": propose.replace = true
            case "--focus": invocation.focus = true
            case "--json": invocation.json = true
            case "--": filesOnly = true
            default:
                guard !arg.hasPrefix("-") else { throw ParseError.unknownOption(arg) }
                propose.files.append(arg)
            }
        }
        guard (propose.planFile == nil) != propose.messages.isEmpty else { throw ParseError.planOrMessage }
        if propose.planFile != nil, !propose.files.isEmpty {
            throw ParseError.unexpected(propose.files[0])
        }
        invocation.command = .propose(propose)
        return invocation
    }

    private static func parseSkill(_ args: inout ArraySlice<String>) throws -> Invocation {
        guard let action = args.popFirst() else { return Invocation(command: .skillStatus) }
        var targets: [AgentInstaller.Target] = []
        var force = false
        var json = false
        while let arg = args.popFirst() {
            switch arg {
            case "--claude": targets.append(.claude)
            case "--codex": targets.append(.codex)
            case "--command": targets.append(.command)
            case "--force": force = true
            case "--json": json = true
            default: throw ParseError.unknownOption(arg)
            }
        }
        switch action {
        case "status":
            return Invocation(command: .skillStatus, json: json)
        case "install":
            return Invocation(command: .skillInstall(targets: targets, force: force), json: json)
        case "remove", "uninstall":
            return Invocation(command: .skillRemove(targets: targets, force: force), json: json)
        default:
            throw ParseError.unknownCommand("skill \(action)")
        }
    }

    private static func value(for option: String, from args: inout ArraySlice<String>) throws -> String {
        guard let value = args.popFirst() else { throw ParseError.missingValue(option) }
        return value
    }

    // MARK: - Agent identity

    /// Who is calling, from the environment agents set for their commands.
    /// Codex is checked first: it can run inside a Claude Code session and
    /// inherit Claude's variables, never the other way round.
    static func detectAgent(in environment: [String: String]) -> (name: String, session: String)? {
        if let thread = environment["CODEX_THREAD_ID"], !thread.isEmpty {
            return ("Codex", thread)
        }
        if let session = environment["CODEX_SESSION_ID"], !session.isEmpty {
            return ("Codex", session)
        }
        if let session = environment["CLAUDE_CODE_SESSION_ID"], !session.isEmpty {
            return ("Claude Code", session)
        }
        if environment["CLAUDECODE"] == "1" {
            return ("Claude Code", "default")
        }
        return nil
    }

    /// Turns a path given on the command line (relative to `cwd`) into one
    /// relative to the repository root, the form Avi expects.
    static func repositoryRelative(_ path: String, cwd: URL, root: String) -> String {
        let absolute = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : cwd.appendingPathComponent(path)).standardizedFileURL
        // The file may be deleted, so resolve symlinks (like /tmp) in its folder only.
        let physical = absolute.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(absolute.lastPathComponent).path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return physical.hasPrefix(prefix) ? String(physical.dropFirst(prefix.count)) : path
    }

    /// Plan file as agents write it.
    struct PlanFile: Decodable {
        var version: Int?
        var agent: String?
        var session: String?
        var title: String?
        var commits: [AgentCommit]
    }

    static let helpText = """
    avi: hand finished work to Avi for review.

    Usage:
      avi status [--repo PATH] [--json]
      avi open [PATH] [--focus] [--json]
      avi propose --file PLAN.json|- [--repo PATH] [--agent NAME] [--session ID]
                  [--title TEXT] [--replace] [--focus] [--json]
      avi propose -m SUBJECT [-m BODY]... [--agent NAME] [--session ID] [--] [FILE...]
      avi skill status | install | remove [--claude] [--codex] [--command] [--force]
      avi version

    A plan file lists commits with paths relative to the repository root:
      {"version": 1, "title": "...", "commits": [{"message": "...", "files": ["a", "b"]}]}

    One commit fills Avi's commit field and stages its files; several commits go
    to Avi's Plan view. Nothing is committed until you approve it in Avi.

    Exit codes: 0 ok, 1 rejected by Avi, 2 usage error, 3 Avi not reachable.
    See https://github.com/mrcat71/avi/blob/main/docs/AGENT-INTEGRATION.md
    """

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

// MARK: - Running

extension AgentCLI {
    struct Runner {
        let invocation: Invocation
        let environment: [String: String]
        let workingDirectory: URL

        private var socketPath: String {
            AgentProtocol.socketPath(environment: environment)
        }

        func run() -> Int32 {
            switch invocation.command {
            case .help:
                print(AgentCLI.helpText)
                return ExitCode.ok
            case .version:
                print(GitKit.version)
                return ExitCode.ok
            case .status(let repo):
                let root = repo.flatMap { resolveRoot(URL(fileURLWithPath: $0, relativeTo: workingDirectory)) }
                    ?? resolveRoot(workingDirectory)
                return send(AgentRequest(method: .status, params: AgentParams(repo: root)), launch: false)
            case .open(let path):
                let target = path.map { URL(fileURLWithPath: $0, relativeTo: workingDirectory) } ?? workingDirectory
                guard let root = resolveRoot(target) else {
                    AgentCLI.printError("avi: \(target.path) is not inside a Git repository.")
                    return ExitCode.rejected
                }
                return send(AgentRequest(method: .open, params: AgentParams(repo: root, focus: invocation.focus)), launch: true)
            case .propose(let propose):
                return runPropose(propose)
            case .skillStatus:
                return skillStatus()
            case .skillInstall(let targets, let force):
                return skillChange(targets, force: force, remove: false)
            case .skillRemove(let targets, let force):
                return skillChange(targets, force: force, remove: true)
            }
        }

        private func runPropose(_ propose: Propose) -> Int32 {
            let repoURL = propose.repo.map { URL(fileURLWithPath: $0, relativeTo: workingDirectory) } ?? workingDirectory
            guard let root = resolveRoot(repoURL) else {
                AgentCLI.printError("avi: \(repoURL.path) is not inside a Git repository.")
                return ExitCode.rejected
            }
            var params = AgentParams(repo: root, replace: propose.replace ? true : nil, focus: invocation.focus ? true : nil)
            let detected = AgentCLI.detectAgent(in: environment)
            if let planFile = propose.planFile {
                let plan: PlanFile
                do {
                    let data = planFile == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: URL(fileURLWithPath: planFile, relativeTo: workingDirectory))
                    plan = try JSONDecoder().decode(PlanFile.self, from: data)
                } catch {
                    AgentCLI.printError("avi: cannot read the plan: \(error.localizedDescription)")
                    return ExitCode.usage
                }
                params.commits = plan.commits
                params.agent = propose.agent ?? plan.agent ?? detected?.name
                params.session = propose.session ?? plan.session ?? detected?.session
                params.title = propose.title ?? plan.title
            } else {
                let files = propose.files.map { AgentCLI.repositoryRelative($0, cwd: workingDirectory, root: root) }
                params.commits = [AgentCommit(message: propose.messages.joined(separator: "\n\n"), files: files)]
                params.agent = propose.agent ?? detected?.name
                params.session = propose.session ?? detected?.session
                params.title = propose.title
            }
            return send(AgentRequest(method: .propose, params: params), launch: true)
        }

        // MARK: Transport

        private func send(_ request: AgentRequest, launch: Bool) -> Int32 {
            if !AgentClient.isReachable(socketPath), launch, !launchAvi() {
                return report(unreachable: .notRunning)
            }
            let deadline = Date().addingTimeInterval(30)
            while true {
                let response: AgentResponse
                do {
                    response = try AgentClient.send(request, to: socketPath)
                } catch let failure as AgentClient.Failure {
                    return report(unreachable: failure)
                } catch {
                    return report(unreachable: .io(error.localizedDescription))
                }
                // A fresh launch has no window yet, and a commit in progress
                // finishes on its own: both are worth waiting out.
                if let code = response.error?.code, code == .busy || code == .noWindow, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
                return render(response)
            }
        }

        /// Starts the Avi app this command belongs to and waits for its socket.
        private func launchAvi() -> Bool {
            let bundle = Bundle.main.bundleURL
            guard bundle.pathExtension == "app" else { return false }
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-g", "-a", bundle.path]
            do {
                try open.run()
                open.waitUntilExit()
            } catch {
                return false
            }
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if AgentClient.isReachable(socketPath) {
                    return true
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return false
        }

        private func report(unreachable failure: AgentClient.Failure) -> Int32 {
            let body: AgentErrorBody
            switch failure {
            case .notRunning:
                body = AgentErrorBody(code: .notRunning, message: "Avi is not running, or agent proposals are turned off in Avi > Settings > Agents.")
            case .blocked(let code):
                let reason = String(cString: strerror(code))
                let hint = environment["CODEX_SANDBOX_NETWORK_DISABLED"] == "1"
                    ? "Codex runs this command without network access. Allow it (`[sandbox_workspace_write] network_access = true`) or approve running avi outside the sandbox."
                    : "A sandbox or file permissions blocked the connection to Avi's socket."
                body = AgentErrorBody(code: .blocked, message: "\(reason). \(hint)")
            case .timedOut:
                body = AgentErrorBody(code: .failed, message: "Avi did not answer in time.")
            case .io(let message), .badResponse(let message):
                body = AgentErrorBody(code: .failed, message: message)
            }
            if invocation.json {
                printJSON(AgentResponse.failure(body))
            } else {
                AgentCLI.printError("avi: \(body.message)")
            }
            return ExitCode.unreachable
        }

        private func render(_ response: AgentResponse) -> Int32 {
            if invocation.json {
                printJSON(response)
                return response.ok ? ExitCode.ok : ExitCode.rejected
            }
            guard response.ok, let result = response.result else {
                let error = response.error ?? AgentErrorBody(code: .failed, message: "Avi returned no result.")
                var lines = ["avi: \(error.message)"]
                if let changed = error.changed {
                    lines.append(changed.isEmpty ? "Nothing in the repository has changes." : "Files with changes:")
                    lines += changed.map { "  \($0)" }
                }
                AgentCLI.printError(lines.joined(separator: "\n"))
                return ExitCode.rejected
            }
            print(describe(result))
            return ExitCode.ok
        }

        private func describe(_ result: AgentResult) -> String {
            var lines: [String] = []
            switch invocation.command {
            case .propose:
                switch result.placement {
                case .commitField:
                    let staged = result.staged ?? []
                    lines.append(staged.isEmpty
                        ? "Filled Avi's commit message."
                        : "Staged \(staged.count) file\(staged.count == 1 ? "" : "s") and filled Avi's commit message.")
                case .previewCard:
                    lines.append("Your message is waiting beside the one already in Avi's commit field.")
                case .plan, .none:
                    let count = result.commits ?? 0
                    lines.append("\(count) commit\(count == 1 ? " is" : "s are") waiting in Avi's Plan.")
                }
                lines += result.notes ?? []
            case .open:
                lines.append("Opened \(result.repo?.path ?? "the repository") in Avi.")
            default:
                lines.append("Avi \(result.app.version) is running.")
                if let repo = result.repo {
                    lines.append(repo.open ? "\(repo.path): open\(repo.branch.map { " on \($0)" } ?? "")" : "\(repo.path): not open in Avi")
                    for draft in repo.drafts ?? [] {
                        lines.append("  pending: \(draft.subject.isEmpty ? "(no message)" : draft.subject) [\(draft.agent ?? draft.source)]")
                    }
                } else {
                    for repo in result.repositories ?? [] {
                        lines.append("\(repo.path)\(repo.branch.map { " (\($0))" } ?? "")")
                    }
                }
            }
            return lines.joined(separator: "\n")
        }

        private func printJSON(_ response: AgentResponse) {
            if let data = try? AgentProtocol.encoder.encode(response) {
                print(String(decoding: data, as: UTF8.self))
            }
        }

        // MARK: Repository

        /// The worktree root containing `url`, from Git itself.
        private func resolveRoot(_ url: URL) -> String? {
            var isDirectory: ObjCBool = false
            let path = url.standardizedFileURL.path
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            let directory = exists && isDirectory.boolValue
                ? URL(fileURLWithPath: path, isDirectory: true)
                : URL(fileURLWithPath: path).deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["rev-parse", "--show-toplevel"]
            git.currentDirectoryURL = directory
            let output = Pipe()
            git.standardOutput = output
            git.standardError = FileHandle.nullDevice
            do {
                try git.run()
            } catch {
                return nil
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            git.waitUntilExit()
            guard git.terminationStatus == 0 else { return nil }
            let root = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return root.isEmpty ? nil : URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        }

        // MARK: Skills

        private var installer: AgentInstaller {
            AgentInstaller(environment: environment)
        }

        private func skillStatus() -> Int32 {
            for target in AgentInstaller.Target.allCases {
                print("\(target.title): \(Self.describe(installer.state(of: target))) (\(installer.tildePath(installer.location(of: target))))")
            }
            return ExitCode.ok
        }

        private func skillChange(_ targets: [AgentInstaller.Target], force: Bool, remove: Bool) -> Int32 {
            let chosen = targets.isEmpty
                ? AgentInstaller.Target.allCases.filter { target in
                    if case .unavailable = installer.state(of: target) {
                        return false
                    }
                    return true
                }
                : targets
            var failed = false
            for target in chosen {
                do {
                    if remove {
                        try installer.remove(target, force: force)
                        print("Removed the \(target.title).")
                    } else {
                        try installer.install(target, force: force)
                        print("Installed the \(target.title) at \(installer.tildePath(installer.location(of: target))).")
                    }
                } catch {
                    failed = true
                    AgentCLI.printError("avi: \(error.localizedDescription)\(error is AgentInstaller.InstallError ? " Pass --force to go ahead." : "")")
                }
            }
            return failed ? ExitCode.rejected : ExitCode.ok
        }

        static func describe(_ state: AgentInstaller.State) -> String {
            switch state {
            case .notInstalled: return "not installed"
            case .installed: return "installed"
            case .outdated(let detail): return "outdated (\(detail))"
            case .modified: return "installed, edited since"
            case .foreign: return "something else is there"
            case .unavailable(let reason): return reason
            }
        }
    }
}
