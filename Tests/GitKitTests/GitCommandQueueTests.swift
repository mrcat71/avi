@testable import GitKit
import Foundation
import Testing

/// Tracks how many operations are running at once so a test can assert the queue
/// never lets two overlap for the same repository.
private actor Probe {
    private(set) var maxActive = 0
    private(set) var completed = 0
    private var active = 0

    func enter() {
        active += 1
        maxActive = max(maxActive, active)
    }

    func leave() {
        active -= 1
        completed += 1
    }
}

struct GitCommandQueueTests {
    private let repo = URL(fileURLWithPath: "/tmp/avi-git-command-queue-test")

    @Test func serializesOperationsForSameRepository() async {
        let queue = GitCommandQueue()
        let probe = Probe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    try? await queue.run(repository: repo) {
                        await probe.enter()
                        try? await Task.sleep(for: .milliseconds(5))
                        await probe.leave()
                    }
                }
            }
        }

        // If two operations ever overlapped, the 5ms window would push maxActive past 1.
        #expect(await probe.maxActive == 1)
        #expect(await probe.completed == 8)
    }

    @Test func returnsOperationResultToCaller() async throws {
        let queue = GitCommandQueue()
        let value = try await queue.run(repository: repo) { 42 }
        #expect(value == 42)
    }

    @Test func propagatesThrownError() async {
        struct Boom: Error {}
        let queue = GitCommandQueue()
        var thrown = false
        do {
            _ = try await queue.run(repository: repo) { throw Boom() }
        } catch is Boom {
            thrown = true
        } catch {}
        #expect(thrown)
    }

    @Test func failureDoesNotStallFollowingOperations() async throws {
        struct Boom: Error {}
        let queue = GitCommandQueue()
        _ = try? await queue.run(repository: repo) { throw Boom() }
        let value = try await queue.run(repository: repo) { 7 }
        #expect(value == 7)
    }
}
