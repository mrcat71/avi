import Foundation

/// Coalesces refresh requests without letting an operation await an older
/// snapshot. Requests arriving during a read complete after the next read.
@MainActor
final class RefreshCoordinator {
    private struct Request {
        let read: @MainActor () async -> Void
        let completion: CheckedContinuation<Void, Never>
    }

    private var pending: [Request] = []
    private var running = false

    func run(_ read: @escaping @MainActor () async -> Void) async {
        await withCheckedContinuation { completion in
            pending.append(Request(read: read, completion: completion))
            guard !running else { return }
            running = true
            Task { await drain() }
        }
    }

    private func drain() async {
        while !pending.isEmpty {
            let batch = pending
            pending.removeAll()
            await batch[batch.count - 1].read()
            for request in batch {
                request.completion.resume()
            }
        }
        running = false
    }
}
