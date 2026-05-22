import Foundation

/// One entry in the recent-repositories list. Persistent metadata only;
/// volatile fields like dirty state and current branch are hydrated lazily
/// by `RepositoryBook` when the picker is visible.
public struct RecentEntry: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var lastOpened: Date
    public var lastKnownBranch: String?
    public var providerHint: String?

    public var id: String {
        path
    }

    public init(
        path: String,
        lastOpened: Date = Date(),
        lastKnownBranch: String? = nil,
        providerHint: String? = nil
    ) {
        self.path = path
        self.lastOpened = lastOpened
        self.lastKnownBranch = lastKnownBranch
        self.providerHint = providerHint
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    public var displayName: String {
        url.lastPathComponent
    }
}

/// Persists recently opened repositories in UserDefaults. The store supports the
/// historical path-only schema (key `"recentRepositories"`) and the enriched v2
/// schema (key `"recentRepositoriesV2"`, JSON-encoded `[RecentEntry]`). The legacy
/// key is preserved across migrations as a safety net for one release.
enum RecentRepositories {
    private static let legacyKey = "recentRepositories"
    private static let v2Key = "recentRepositoriesV2"
    private static let limit = 12

    static func entries() -> [RecentEntry] {
        if let data = UserDefaults.standard.data(forKey: v2Key),
           let decoded = try? JSONDecoder().decode([RecentEntry].self, from: data) {
            return decoded
        }
        // Migrate legacy paths -> RecentEntry on first read.
        let legacy = UserDefaults.standard.stringArray(forKey: legacyKey) ?? []
        let migrated = legacy.map { RecentEntry(path: $0, lastOpened: .distantPast) }
        if !migrated.isEmpty {
            persist(migrated)
        }
        return migrated
    }

    static func urls() -> [URL] {
        entries().map(\.url)
    }

    static func paths() -> [String] {
        entries().map(\.path)
    }

    static func add(_ url: URL, providerHint: String? = nil, lastKnownBranch: String? = nil) {
        let path = url.standardizedFileURL.path
        var list = entries()
        list.removeAll { $0.path == path }
        let entry = RecentEntry(
            path: path,
            lastOpened: Date(),
            lastKnownBranch: lastKnownBranch,
            providerHint: providerHint
        )
        list.insert(entry, at: 0)
        persist(Array(list.prefix(limit)))
    }

    static func remove(_ url: URL) {
        let path = url.standardizedFileURL.path
        var list = entries()
        list.removeAll { $0.path == path }
        persist(list)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: v2Key)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    static func updateLastKnown(_ url: URL, branch: String?) {
        let path = url.standardizedFileURL.path
        var list = entries()
        guard let index = list.firstIndex(where: { $0.path == path }) else { return }
        list[index].lastKnownBranch = branch
        persist(list)
    }

    private static func persist(_ list: [RecentEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: v2Key)
        UserDefaults.standard.set(list.map(\.path), forKey: legacyKey)
    }
}
