public extension Task where Success == Never, Failure == Never {
    /// Suspends the current task for `duration`, throwing `CancellationError`
    /// if the task is cancelled first. Use it instead of `Task.sleep(for:)`.
    ///
    /// `Task.sleep(for:)` and `Clock.sleep(for:)` are compiled into every module
    /// that calls them. Swift 6.2 and 6.3 release builds can pair one module's
    /// copy with the async context size another module computed, so the sleep
    /// writes past its context and the app aborts in `swift_task_dealloc` when
    /// it wakes up (https://github.com/swiftlang/swift/issues/86204).
    /// `ContinuousClock.sleep(until:)` lives in the Swift runtime instead.
    static func safeSleep(for duration: Duration) async throws {
        let clock = ContinuousClock()
        try await clock.sleep(until: clock.now.advanced(by: duration))
    }
}
