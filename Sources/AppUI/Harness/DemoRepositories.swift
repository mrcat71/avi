#if DEBUG
import Foundation
import GitKit

/// Real Git repositories with made-up history, for screenshots and for
/// trying the interface without touching your own work. Every commit has a
/// fixed author and date, so the pictures come out the same each time.
enum DemoRepositories {
    struct Result {
        /// Repositories to open, in sidebar order.
        let repositories: [URL]
        /// A linked worktree of the first one.
        let worktree: URL
    }

    /// Builds the demo repositories under `folder`, replacing what is there.
    static func make(in folder: URL) async throws -> Result {
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let web = try await makeWeb(in: folder)
        let infra = try await makeInfra(in: folder)
        let dotfiles = try await makeDotfiles(in: folder)
        let worktree = folder.appendingPathComponent("skyline-web-search")
        try await git(["worktree", "add", "-q", worktree.path, "feature/search"], in: web)
        return Result(repositories: [web, infra, dotfiles], worktree: worktree)
    }

    // MARK: Repositories

    private static func makeWeb(in folder: URL) async throws -> URL {
        let origin = folder.appendingPathComponent(".remotes/skyline-web.git")
        let repo = folder.appendingPathComponent("skyline-web")
        try await initRepository(repo)

        let mara = Author(name: "Mara Lindqvist", email: "mara@skyline.dev")
        let theo = Author(name: "Theo Ramos", email: "theo@skyline.dev")
        let ines = Author(name: "Ines Okafor", email: "ines@skyline.dev")

        var day = 0
        func next() -> Int {
            day += 1
            return day
        }

        try await commit(repo, files: [
            "README.md": "# Skyline\n\nA small web app for planning trips.\n",
            "package.json": "{\n  \"name\": \"skyline-web\",\n  \"version\": \"0.1.0\"\n}\n",
            "src/app.ts": "export function start() {\n  console.log(\"Skyline\")\n}\n"
        ], message: "chore: start the project", author: mara, day: next())
        try await commit(repo, files: [
            "src/routes/trips.ts": tripsRoute(limit: 20),
            "src/app.ts": "import { trips } from \"./routes/trips\"\n\nexport function start() {\n  trips.listen()\n}\n"
        ], message: "feat(trips): list a user's trips", author: theo, day: next())
        try await commit(repo, files: [
            "src/auth/session.ts": sessionFile(timeout: 900)
        ], message: "feat(auth): keep people signed in for 15 minutes", author: ines, day: next())
        try await git(["tag", "-a", "v1.0.0", "-m", "First release"], in: repo, date: day)
        try await commit(repo, files: [
            "src/routes/trips.ts": tripsRoute(limit: 50)
        ], message: "perf(trips): page through long trip lists", author: theo, day: next())

        try await git(["switch", "-q", "-c", "fix/login-timeout"], in: repo)
        try await commit(repo, files: [
            "src/auth/session.ts": sessionFile(timeout: 3600)
        ], message: "fix(auth): stop signing people out after 15 minutes", author: ines, day: next())
        try await git(["switch", "-q", "main"], in: repo)
        try await git(["merge", "-q", "--no-ff", "fix/login-timeout", "-m", "Merge branch 'fix/login-timeout'"], in: repo, date: next(), author: mara)
        try await git(["tag", "-a", "v1.1.0", "-m", "Session fix"], in: repo, date: day)

        try await git(["switch", "-q", "-c", "feature/search"], in: repo)
        try await commit(repo, files: [
            "src/search/index.ts": "export function search(query: string) {\n  return query.trim().toLowerCase()\n}\n"
        ], message: "feat(search): search trips by name", author: theo, day: next())
        try await commit(repo, files: [
            "src/search/index.ts": "export function search(query: string, limit = 10) {\n  return query.trim().toLowerCase().slice(0, limit)\n}\n"
        ], message: "feat(search): limit the results", author: theo, day: next())
        try await git(["switch", "-q", "main"], in: repo)

        for (index, message) in [
            "docs: explain how to run the app locally",
            "chore(deps): update typescript to 6.1",
            "fix(trips): sort trips by start date"
        ].enumerated() {
            try await commit(repo, files: [
                "CHANGELOG.md": "# Changes\n\n" + (0 ... index).map { "- change \($0 + 1)\n" }.joined()
            ], message: message, author: [mara, theo, ines][index % 3], day: next())
        }

        // The remote has one commit main lacks, and main has two it lacks.
        try await git(["clone", "-q", "--bare", repo.path, origin.path], in: folder)
        try await git(["remote", "add", "origin", origin.path], in: repo)
        try await git(["fetch", "-q", "origin"], in: repo)
        try await git(["branch", "-q", "--set-upstream-to=origin/main", "main"], in: repo)
        try await git(["branch", "-q", "--set-upstream-to=origin/feature/search", "feature/search"], in: repo)
        let other = folder.appendingPathComponent(".remotes/skyline-web-other")
        try await git(["clone", "-q", origin.path, other.path], in: folder)
        try await commit(other, files: ["docs/deploy.md": "# Deploy\n\nPush to main and the pipeline does the rest.\n"],
                         message: "docs: describe deployments", author: mara, day: next())
        try await git(["push", "-q", "origin", "main"], in: other)
        try await git(["fetch", "-q", "origin"], in: repo)
        try await commit(repo, files: ["src/app.ts": "import { trips } from \"./routes/trips\"\n\nexport function start(port = 8080) {\n  trips.listen(port)\n}\n"],
                         message: "feat(app): choose the port", author: theo, day: next())
        try await commit(repo, files: ["package.json": "{\n  \"name\": \"skyline-web\",\n  \"version\": \"1.2.0\"\n}\n"],
                         message: "chore(release): prepare version 1.2.0", author: mara, day: next())

        // A stash, then work in progress: staged, unstaged and new files.
        try write("src/routes/trips.ts", tripsRoute(limit: 50, sortByDate: true, archived: false), in: repo)
        try await git(["stash", "push", "-q", "-m", "try sorting trips by date"], in: repo, date: next())
        try write("src/auth/session.ts", sessionFile(timeout: 3600, refresh: true), in: repo)
        try write("src/routes/trips.ts", tripsRoute(limit: 50, sortByDate: true, archived: true), in: repo)
        try write("src/routes/archive.ts", "import { trips } from \"./trips\"\n\nexport const archive = trips.filter((trip) => trip.archived)\n", in: repo)
        try write("README.md", "# Skyline\n\nA small web app for planning trips.\n\n## Run it\n\n    npm install\n    npm start\n", in: repo)
        try write("docs/architecture.md", "# Architecture\n\nRoutes call services; services own the data.\n", in: repo)
        try await git(["add", "README.md"], in: repo)
        return repo
    }

    private static func makeInfra(in folder: URL) async throws -> URL {
        let origin = folder.appendingPathComponent(".remotes/infra-live.git")
        let repo = folder.appendingPathComponent("infra-live")
        try await initRepository(repo)
        let ops = Author(name: "Sam Novak", email: "sam@skyline.dev")
        try await commit(repo, files: [
            "README.md": "# infra-live\n\nClusters and their releases.\n",
            "environments/k8s-infra-ah-ams1/main.tf": "module \"cluster\" {\n  source = \"../../modules/cluster\"\n  name   = \"k8s-infra-ah-ams1\"\n}\n",
            "environments/k8s-web-fra2/main.tf": "module \"cluster\" {\n  source = \"../../modules/cluster\"\n  name   = \"k8s-web-fra2\"\n}\n"
        ], message: "chore: import the clusters", author: ops, day: 3)
        try await git(["clone", "-q", "--bare", repo.path, origin.path], in: folder)
        try await git(["remote", "add", "origin", origin.path], in: repo)
        try await git(["fetch", "-q", "origin"], in: repo)
        try await git(["branch", "-q", "--set-upstream-to=origin/main", "main"], in: repo)
        // Looks like GitHub, so pull requests are offered; pushes go to the local copy.
        try await git(["remote", "set-url", "origin", "https://github.com/skyline-demo/infra-live.git"], in: repo)
        try await git(["remote", "set-url", "--push", "origin", origin.path], in: repo)
        try await git(["switch", "-q", "-c", "INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress"], in: repo)
        try await commit(repo, files: [
            "environments/k8s-infra-ah-ams1/ingress.tf": "resource \"helm_release\" \"ingress\" {\n  name    = \"ingress-nginx\"\n  version = \"4.12.1\"\n}\n"
        ], message: "feat(ingress): upgrade ingress-nginx on k8s-infra-ah-ams1", author: ops, day: 5)
        return repo
    }

    private static func makeDotfiles(in folder: URL) async throws -> URL {
        let repo = folder.appendingPathComponent("dotfiles")
        try await initRepository(repo)
        let me = Author(name: "Mara Lindqvist", email: "mara@skyline.dev")
        try await commit(repo, files: [".zshrc": "export EDITOR=vim\n", ".gitconfig": "[pull]\n\trebase = true\n"],
                         message: "chore: add shell and git settings", author: me, day: 2)
        return repo
    }

    // MARK: File contents

    private static func tripsRoute(limit: Int, sortByDate: Bool = false, archived: Bool = false) -> String {
        var lines = [
            "import { db } from \"../db\"",
            "",
            "export const trips = {",
            "  async list(userID: string) {",
            "    const rows = await db.trips.where({ userID }).limit(\(limit))"
        ]
        if archived {
            lines.append("    const visible = rows.filter((trip) => !trip.archived)")
        }
        if sortByDate {
            lines.append("    return \(archived ? "visible" : "rows").sort((a, b) => a.startsOn.getTime() - b.startsOn.getTime())")
        } else {
            lines.append("    return rows")
        }
        lines += ["  },", "", "  listen(port = 8080) {", "    console.log(`trips on ${port}`)", "  }", "}", ""]
        return lines.joined(separator: "\n")
    }

    private static func sessionFile(timeout: Int, refresh: Bool = false) -> String {
        var lines = [
            "// How long a signed-in session lasts, in seconds.",
            "export const sessionTimeout = \(timeout)",
            "",
            "export function isExpired(startedAt: Date, now = new Date()) {",
            "  return now.getTime() - startedAt.getTime() > sessionTimeout * 1000",
            "}"
        ]
        if refresh {
            lines += ["", "export function refresh(startedAt: Date) {", "  return isExpired(startedAt) ? new Date() : startedAt", "}"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Git

    private struct Author {
        let name: String
        let email: String
    }

    /// Fixed dates: day 1 is September 1, 2026, 10:00 UTC.
    private static func date(_ day: Int) -> String {
        let base = 1_788_256_800 // 2026-09-01T10:00:00Z
        return "\(base + day * 86400 + (day * 37 % 300) * 60) +0000"
    }

    private static func initRepository(_ url: URL) async throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try await git(["init", "-q", "-b", "main"], in: url)
        try await git(["config", "user.name", "Mara Lindqvist"], in: url)
        try await git(["config", "user.email", "mara@skyline.dev"], in: url)
        try await git(["config", "commit.gpgsign", "false"], in: url)
        try await git(["config", "tag.gpgsign", "false"], in: url)
    }

    private static func write(_ path: String, _ text: String, in repo: URL) throws {
        let url = repo.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func commit(_ repo: URL, files: [String: String], message: String, author: Author, day: Int) async throws {
        for (path, text) in files {
            try write(path, text, in: repo)
        }
        try await git(["add", "-A"], in: repo)
        try await git(["commit", "-q", "-m", message], in: repo, date: day, author: author)
    }

    @discardableResult
    private static func git(_ arguments: [String], in directory: URL, date day: Int? = nil, author: Author? = nil) async throws -> String {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        if let day {
            environment["GIT_AUTHOR_DATE"] = date(day)
            environment["GIT_COMMITTER_DATE"] = date(day)
        }
        if let author {
            environment["GIT_AUTHOR_NAME"] = author.name
            environment["GIT_AUTHOR_EMAIL"] = author.email
            environment["GIT_COMMITTER_NAME"] = author.name
            environment["GIT_COMMITTER_EMAIL"] = author.email
        }
        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            workingDirectory: directory,
            environment: environment
        )
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(command: "git " + arguments.joined(separator: " "), exitCode: result.exitCode, stderr: result.stderrString)
        }
        return result.stdoutString
    }
}
#endif
