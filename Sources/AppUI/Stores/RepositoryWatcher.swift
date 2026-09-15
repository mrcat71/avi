import CoreServices
import Foundation

/// Watches a repository tree for filesystem changes and calls back after FSEvents fires.
final class RepositoryWatcher {
    private let paths: [String]
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?

    /// `additionalPaths` covers a linked worktree, whose refs live in the main
    /// repository's common dir and so never produce events under its own root.
    init(url: URL, additionalPaths: [URL] = [], onChange: @escaping @Sendable () -> Void) {
        paths = Self.watchPaths(root: url, additional: additionalPaths)
        self.onChange = onChange
    }

    /// Drops any path already covered by the root, so the common dir of an
    /// ordinary repository is not watched twice.
    static func watchPaths(root: URL, additional: [URL]) -> [String] {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        var result = [rootPath]
        for url in additional {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != rootPath, !path.hasPrefix(rootPath + "/"), !result.contains(path) else { continue }
            result.append(path)
        }
        return result
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagUseCFTypes
        )

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
