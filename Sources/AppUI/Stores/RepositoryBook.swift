import Foundation
import GitKit

/// Hydrates volatile metadata (current branch, dirty state, .git mtime) for
/// repositories shown in the picker. Hydration is lazy per row, capped to a
/// small concurrency budget, and short-lived (TTL); callers re-hydrate as
/// rows scroll in. Missing-repo paths are flagged so the UI can offer cleanup.
@MainActor
@Observable
public final class RepositoryBook {
    public struct LiveMetadata: Sendable, Equatable {
        public var branch: String?
        public var isDirty: Bool
        public var changedFiles: Int
        public var headModifiedAt: Date?
        public var isMissing: Bool
    }

    private struct CacheEntry {
        var data: LiveMetadata
        var fetchedAt: Date
    }

    public private(set) var cache: [String: LiveMetadata] = [:]
    private var inFlight: Set<String> = []
    private var entries: [String: CacheEntry] = [:]

    private let ttl: TimeInterval = 15
    private let maxConcurrent: Int = 4

    public init() {}

    public func metadata(for url: URL) -> LiveMetadata? {
        cache[url.standardizedFileURL.path]
    }

    public func hydrate(_ url: URL) {
        let path = url.standardizedFileURL.path
        if inFlight.contains(path) { return }
        if let entry = entries[path], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            cache[path] = entry.data
            return
        }
        guard inFlight.count < maxConcurrent else {
            // The next visible row will retry; we simply skip this tick.
            return
        }
        inFlight.insert(path)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.inFlight.remove(path)
            }
            let result = await Self.probe(url: url)
            entries[path] = CacheEntry(data: result, fetchedAt: Date())
            cache[path] = result
        }
    }

    public func invalidate(_ url: URL) {
        let path = url.standardizedFileURL.path
        entries.removeValue(forKey: path)
        cache.removeValue(forKey: path)
    }

    public func clear() {
        entries.removeAll()
        cache.removeAll()
        inFlight.removeAll()
    }

    private static func probe(url: URL) async -> LiveMetadata {
        let gitDir = url.appendingPathComponent(".git")
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) else {
            return LiveMetadata(branch: nil, isDirty: false, changedFiles: 0, headModifiedAt: nil, isMissing: true)
        }

        let headURL = gitDir.appendingPathComponent("HEAD")
        let headDate = (try? fileManager.attributesOfItem(atPath: headURL.path))?[.modificationDate] as? Date

        let branch = await Self.readBranch(at: url)
        let (dirty, changedCount) = await Self.readDirty(at: url)

        return LiveMetadata(
            branch: branch,
            isDirty: dirty,
            changedFiles: changedCount,
            headModifiedAt: headDate,
            isMissing: false
        )
    }

    private static func readBranch(at url: URL) async -> String? {
        let headURL = url.appendingPathComponent(".git").appendingPathComponent("HEAD")
        guard let raw = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: ") {
            let refPath = String(trimmed.dropFirst(5))
            if let last = refPath.split(separator: "/").last {
                return String(last)
            }
            return refPath
        }
        // Detached HEAD - return short SHA.
        if trimmed.count >= 7 { return "(\(trimmed.prefix(7)))" }
        return nil
    }

    private static func readDirty(at url: URL) async -> (Bool, Int) {
        let env = [
            "GIT_TERMINAL_PROMPT": "0",
            // Read-only status must not take .git/index.lock for an opportunistic
            // index refresh, so a picker scan never collides with the open repo's
            // git operations.
            "GIT_OPTIONAL_LOCKS": "0",
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin"
        ]
        do {
            let result = try await GitCommandQueue.shared.run(repository: url) {
                try await ProcessRunner.run(
                    executable: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["git", "status", "--porcelain=v1", "-uall"],
                    workingDirectory: url,
                    environment: env
                )
            }
            guard result.exitCode == 0 else { return (false, 0) }
            let lines = result.stdoutString.split(separator: "\n", omittingEmptySubsequences: true)
            return (!lines.isEmpty, lines.count)
        } catch {
            return (false, 0)
        }
    }
}
