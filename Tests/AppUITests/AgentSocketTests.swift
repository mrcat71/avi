@testable import AppUI
import Darwin
import Foundation
import Testing

@Suite("Agent socket", .serialized)
struct AgentSocketTests {
    /// Short enough for sun_path, unique per test.
    private func socketPath() -> String {
        "/tmp/avi-\(UUID().uuidString.prefix(8)).sock"
    }

    private func echoServer(_ path: String) throws -> AgentSocketServer {
        let server = AgentSocketServer(path: path) { data in
            let request = try? JSONDecoder().decode(AgentRequest.self, from: data)
            let response = AgentResponse.success(AgentResult(app: AgentAppInfo(version: request?.params.session ?? "?")))
            return (try? JSONEncoder().encode(response)) ?? Data()
        }
        try server.start()
        return server
    }

    @Test func roundTripAndPrivatePermissions() throws {
        let path = socketPath()
        let server = try echoServer(path)
        defer { server.stop() }

        let response = try AgentClient.send(AgentRequest(method: .status, params: AgentParams(session: "hello")), to: path)
        #expect(response.result?.app.version == "hello")

        var info = stat()
        #expect(lstat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
    }

    @Test func manyClientsAtOnceEachGetTheirOwnAnswer() throws {
        let path = socketPath()
        let server = try echoServer(path)
        defer { server.stop() }

        // Clients block, like the real `avi` process does, so they run on
        // dispatch threads rather than Swift's cooperative pool, which the
        // server's handlers need.
        let answers = Answers()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            let response = try? AgentClient.send(AgentRequest(method: .status, params: AgentParams(session: "\(index)")), to: path, timeout: 10)
            answers.set(index, response?.result?.app.version)
        }
        let collected = answers.values
        #expect(collected.count == 12)
        #expect(collected.filter { $0.value == "\($0.key)" }.count == 12)
    }

    @Test func aSecondServerNeverTakesOverALiveSocket() throws {
        let path = socketPath()
        let server = try echoServer(path)
        defer { server.stop() }
        #expect(throws: AgentSocketError.servedElsewhere(path)) {
            try AgentSocketServer(path: path) { _ in Data() }.start()
        }
        #expect(AgentClient.isReachable(path))
    }

    @Test func aPeerThatHangsUpEarlyDoesNotKillTheServer() throws {
        let path = socketPath()
        let server = try echoServer(path)
        defer { server.stop() }
        for _ in 0 ..< 5 {
            #expect(AgentClient.isReachable(path))
        }
        Thread.sleep(forTimeInterval: 0.3)
        let response = try AgentClient.send(AgentRequest(method: .status, params: AgentParams(session: "still here")), to: path)
        #expect(response.result?.app.version == "still here")
    }

    @Test func aStaleSocketIsReplaced() throws {
        let path = socketPath()
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        _ = try UnixSocketAddress.withAddress(path) { bind(stale, $0, $1) }
        close(stale)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!AgentClient.isReachable(path))

        let server = try echoServer(path)
        defer { server.stop() }
        #expect(AgentClient.isReachable(path))
    }

    @Test func anOrdinaryFileIsLeftAlone() throws {
        let path = socketPath()
        try Data("keep me".utf8).write(to: URL(fileURLWithPath: path))
        defer { unlink(path) }
        #expect(throws: AgentSocketError.notASocket(path)) {
            try AgentSocketServer(path: path) { _ in Data() }.start()
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "keep me")
    }

    @Test func stoppingRemovesTheSocketAndClientsSeeNotRunning() throws {
        let path = socketPath()
        let server = try echoServer(path)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(throws: AgentClient.Failure.notRunning) {
            try AgentClient.send(AgentRequest(method: .status), to: path)
        }
    }

    @Test func tooLongPathsAreRefusedUpFront() {
        let path = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        #expect(throws: AgentSocketError.pathTooLong(path)) {
            try AgentSocketServer(path: path) { _ in Data() }.start()
        }
    }
}

private final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int: String] = [:]

    func set(_ index: Int, _ value: String?) {
        lock.withLock { storage[index] = value }
    }

    var values: [Int: String] {
        lock.withLock { storage }
    }
}
