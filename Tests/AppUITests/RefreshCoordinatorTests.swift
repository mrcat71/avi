@testable import AppUI
import Testing

@Suite("Refresh coordination")
@MainActor
struct RefreshCoordinatorTests {
    @Test func concurrentRequestsNeverOverlapReads() async {
        let coordinator = RefreshCoordinator()
        var active = 0
        var maximum = 0
        var reads = 0
        let tasks = (0 ..< 20).map { _ in
            Task { @MainActor in
                await coordinator.run {
                    active += 1
                    maximum = max(maximum, active)
                    await Task.yield()
                    active -= 1
                    reads += 1
                }
            }
        }
        for task in tasks {
            await task.value
        }
        #expect(maximum == 1)
        #expect(reads > 0 && reads <= 20)
    }
}
