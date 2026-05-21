import Foundation

/// FSEvents watcher for the config file directory. Coalesces rapid events
/// with a short debounce and invokes `onChange` on the main actor.
final class ConfigWatcher: @unchecked Sendable {
    private let path: String
    private let onChange: @MainActor () -> Void

    private var stream: FSEventStreamRef?
    private var lastFireAt: Date = .distantPast
    private let debounce: TimeInterval = 0.25

    init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ConfigWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvent()
        }

        let paths = [path] as CFArray
        let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        guard let s else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit {
        stop()
    }

    private func handleEvent() {
        let now = Date()
        if now.timeIntervalSince(lastFireAt) < debounce {
            return
        }
        lastFireAt = now
        let handler = onChange
        Task { @MainActor in
            handler()
        }
    }
}
