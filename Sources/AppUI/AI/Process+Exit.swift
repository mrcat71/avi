import Foundation
import os

extension Process {
    /// Suspends until the process exits. The termination handler and the
    /// `isRunning` check for an exit that already happened both fire when the
    /// process exits in between, so only the first of them resumes.
    func waitForExit() async {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeOnce: @Sendable () -> Void = {
                let isFirst = resumed.withLock { resumed in
                    defer { resumed = true }
                    return !resumed
                }
                if isFirst {
                    continuation.resume()
                }
            }
            terminationHandler = { _ in resumeOnce() }
            if !isRunning {
                resumeOnce()
            }
        }
    }
}
