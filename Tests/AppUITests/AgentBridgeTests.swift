@testable import AppUI
import Foundation
import GitKit
import Testing

@MainActor
@Suite("Agent bridge")
struct AgentBridgeTests {
    /// Keeps the window session alive: the bridge only holds it weakly.
    final class Harness {
        let bridge: AgentBridge
        let session: WorkspaceSession
        let git: FakeGitProvider

        @MainActor
        init(entries: [String]) {
            git = Fixtures.clean()
            git.status = WorkingCopyStatus(branch: git.status.branch, entries: entries.map { FileStatus(path: $0, index: .unmodified, worktree: .modified) })
            git.appliesStaging = true
            session = WorkspaceSession(git: git)
            bridge = AgentBridge(socketPath: "/tmp/avi-unused.sock", appVersion: "9.9.9")
            bridge.isEnabled = { true }
            bridge.isKnownRepository = { _ in true }
            bridge.register(session)
        }
    }

    private func harness(entries: [String] = ["a.swift", "b.swift"]) -> Harness {
        Harness(entries: entries)
    }

    private func propose(_ repo: String, _ commits: [AgentCommit], session: String = "s1", agent: String = "Claude Code") -> AgentRequest {
        AgentRequest(method: .propose, params: AgentParams(repo: repo, agent: agent, session: session, commits: commits))
    }

    @Test func proposingOpensTheRepositoryInTheBackground() async {
        let h = harness()
        let (bridge, session) = (h.bridge, h.session)
        await session.open(URL(fileURLWithPath: "/tmp/avi-first", isDirectory: true))
        let selected = session.selectedRepositoryID

        let response = await bridge.handle(propose("/tmp/avi-second", [AgentCommit(message: "feat: x", files: ["a.swift"])]))

        #expect(response.ok)
        #expect(response.result?.placement == .commitField)
        #expect(response.result?.app.version == "9.9.9")
        #expect(session.repositories.count == 2)
        #expect(session.selectedRepositoryID == selected)
        withExtendedLifetime(h) {}
    }

    @Test func statusReportsPendingWorkWithoutSideEffects() async {
        let h = harness()
        let (bridge, session) = (h.bridge, h.session)
        _ = await bridge.handle(propose("/tmp/avi-status", [
            AgentCommit(message: "one", files: ["a.swift"]),
            AgentCommit(message: "two", files: ["b.swift"])
        ]))
        let status = await bridge.handle(AgentRequest(method: .status, params: AgentParams(repo: "/tmp/avi-status")))
        let repo = status.result?.repo
        #expect(repo?.open == true)
        #expect(repo?.drafts?.map(\.subject) == ["one", "two"])
        #expect(repo?.drafts?.first?.session == "s1")

        let unknown = await bridge.handle(AgentRequest(method: .status, params: AgentParams(repo: "/tmp/avi-never-opened")))
        #expect(unknown.result?.repo?.open == false)
        #expect(session.repositories.count == 1)
        withExtendedLifetime(h) {}
    }

    @Test func rejectionsCarryCodesAgentsCanActOn() async {
        let h = harness()
        let bridge = h.bridge
        let response = await bridge.handle(propose("/tmp/avi-reject", [AgentCommit(message: "x", files: ["missing.swift"])]))
        #expect(response.ok == false)
        #expect(response.error?.code == .unknownPath)
        #expect(response.error?.paths == ["missing.swift"])
        #expect(response.error?.changed == ["a.swift", "b.swift"])
        withExtendedLifetime(h) {}
    }

    @Test func pathsInsideTheRepositoryAreAcceptedInAnyForm() async {
        let h = harness()
        let (bridge, git) = (h.bridge, h.git)
        let response = await bridge.handle(propose("/tmp/avi-paths", [AgentCommit(message: "x", files: ["./a.swift", "/tmp/avi-paths/b.swift"])]))
        #expect(response.ok)
        #expect(git.stagePathsCalls.last == ["a.swift", "b.swift"])
        withExtendedLifetime(h) {}
    }

    @Test func turnedOffMeansNoChanges() async {
        let h = harness()
        let (bridge, session) = (h.bridge, h.session)
        bridge.isEnabled = { false }
        let response = await bridge.handle(propose("/tmp/avi-off", [AgentCommit(message: "x", files: ["a.swift"])]))
        #expect(response.error?.code == .disabled)
        #expect(session.repositories.isEmpty)
        withExtendedLifetime(h) {}
    }

    @Test func unknownRepositoriesWaitForYourApproval() async {
        let h = harness()
        let (bridge, session) = (h.bridge, h.session)
        bridge.isKnownRepository = { _ in false }
        let response = await bridge.handle(propose("/tmp/avi-stranger", [AgentCommit(message: "x", files: ["a.swift"])]))
        #expect(response.error?.code == .notTrusted)
        #expect(session.repositories.isEmpty)
        #expect(bridge.pendingApproval?.path == "/tmp/avi-stranger")
        #expect(bridge.pendingApproval?.requester == "Claude Code")
        #expect(bridge.presentsApprovals(in: session))

        bridge.resolveApproval(open: false, in: session)
        #expect(bridge.pendingApproval == nil)
        #expect(session.repositories.isEmpty)
        withExtendedLifetime(h) {}
    }

    @Test func trustPromptsCannotBeSpoofedWithLineBreaks() {
        #expect(AgentBridge.displaySafe("/tmp/x\n\nThis is safe, click Open", limit: 300) == "/tmp/x??This is safe, click Open")
        #expect(AgentBridge.displaySafe(String(repeating: "a", count: 50), limit: 10) == String(repeating: "a", count: 9) + "…")
    }

    @Test func noWindowIsReportedSoTheCommandCanWait() async {
        let bridge = AgentBridge(socketPath: "/tmp/avi-unused.sock", appVersion: "9.9.9")
        bridge.isEnabled = { true }
        let response = await bridge.handle(propose("/tmp/avi-nowindow", [AgentCommit(message: "x", files: ["a.swift"])]))
        #expect(response.error?.code == .noWindow)
    }

    @Test func differentRepositoriesDoNotInterfere() async {
        let h = harness()
        let (bridge, session) = (h.bridge, h.session)
        async let first = bridge.handle(propose("/tmp/avi-repo-one", [
            AgentCommit(message: "one", files: ["a.swift"]), AgentCommit(message: "two", files: ["b.swift"])
        ], session: "one"))
        async let second = bridge.handle(propose("/tmp/avi-repo-two", [
            AgentCommit(message: "three", files: ["a.swift"]), AgentCommit(message: "four", files: ["b.swift"])
        ], session: "two"))
        let (a, b) = await (first, second)
        #expect(a.ok && b.ok)
        #expect(session.repositories.count == 2)
        #expect(session.repositories.allSatisfy { $0.commitPlan.drafts.count == 2 })
        withExtendedLifetime(h) {}
    }

    @Test func oneRepositoryTakesRequestsInOrder() async {
        let h = harness()
        let (bridge, session) = (h.bridge, h.session)
        async let first = bridge.handle(propose("/tmp/avi-queue", [AgentCommit(message: "claude", files: ["a.swift"])], session: "one"))
        async let second = bridge.handle(propose("/tmp/avi-queue", [AgentCommit(message: "codex", files: ["b.swift"])], session: "two", agent: "Codex"))
        let (a, b) = await (first, second)
        #expect(a.ok && b.ok)
        let store = session.repositories.first
        #expect(session.repositories.count == 1)
        #expect(Set(store?.commitPlan.drafts.map(\.message) ?? []) == ["claude", "codex"])
        #expect(store?.fieldProposal == nil)
        withExtendedLifetime(h) {}
    }

    @Test func malformedRequestsGetUsefulErrors() async throws {
        let h = harness()
        let bridge = h.bridge
        let cases: [(String, AgentErrorCode)] = [
            ("not json", .badRequest),
            (#"{"v":2,"method":"status","params":{}}"#, .unsupportedVersion),
            (#"{"v":1,"method":"launch","params":{}}"#, .badRequest)
        ]
        for (raw, code) in cases {
            let data = await bridge.respond(to: Data(raw.utf8))
            let response = try JSONDecoder().decode(AgentResponse.self, from: data)
            #expect(response.error?.code == code, "\(raw)")
        }
        withExtendedLifetime(h) {}
    }
}

@Suite("Agent protocol")
struct AgentProtocolTests {
    @Test func requestsEncodeOnOneStableLine() throws {
        let request = AgentRequest(method: .propose, params: AgentParams(
            repo: "/r", agent: "Codex", session: "t", commits: [AgentCommit(message: "a\nb", files: ["x/y"])]
        ))
        let text = try String(decoding: AgentProtocol.encoder.encode(request), as: UTF8.self)
        #expect(text == #"{"method":"propose","params":{"agent":"Codex","commits":[{"files":["x/y"],"message":"a\nb"}],"repo":"/r","session":"t"},"v":1}"#)
        #expect(!text.contains("\n"))
    }

    @Test func responsesTolerateFieldsFromNewerApps() throws {
        let raw = #"{"v":1,"ok":true,"future":1,"result":{"app":{"version":"0.5.0","commit":"abc"},"placement":"plan","commits":2}}"#
        let response = try JSONDecoder().decode(AgentResponse.self, from: Data(raw.utf8))
        #expect(response.result?.placement == .plan)
        #expect(response.result?.commits == 2)
    }

    @Test func socketPathHonorsOverride() {
        #expect(AgentProtocol.socketPath(environment: ["AVI_SOCKET": "/tmp/x.sock"]) == "/tmp/x.sock")
        #expect(AgentProtocol.socketPath(environment: ["HOME": "/Users/me"]) == "/Users/me/Library/Application Support/Avi/control.sock")
    }
}
