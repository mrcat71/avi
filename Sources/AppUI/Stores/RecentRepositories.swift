import Foundation

/// Persists recently opened repository paths in UserDefaults.
enum RecentRepositories {
    private static let key = "recentRepositories"
    private static let limit = 12

    static func urls() -> [URL] {
        paths().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func paths() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        var list = paths()
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
