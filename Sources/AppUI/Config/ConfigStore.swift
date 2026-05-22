import Foundation
import Observation

public enum ConfigStatus: Equatable, Sendable {
    case loaded
    case createdNew
    case invalid(reason: String)
    case pathNotWritable(reason: String)

    public var isError: Bool {
        switch self {
        case .invalid, .pathNotWritable: return true
        case .loaded, .createdNew: return false
        }
    }
}

/// Observable wrapper around the on-disk Avi config. UI reads `store.config`
/// and writes via `update`. Changes from outside the app (file edited
/// externally) are picked up by `ConfigWatcher` and reflected through `reload`.
@MainActor
@Observable
public final class ConfigStore {
    public static let shared = ConfigStore()

    public private(set) var config: AviConfig
    public private(set) var status: ConfigStatus = .loaded

    /// Legacy convenience; some sections still read this. Mirrors `status` errors.
    public var loadError: String? {
        switch status {
        case .invalid(let reason), .pathNotWritable(let reason): return reason
        default: return nil
        }
    }

    private var watcher: ConfigWatcher?
    private var saveTask: Task<Void, Never>?
    private var ignoreNextWatcherEvent = false

    private init() {
        var loaded = AviConfig()
        var initialStatus: ConfigStatus = .loaded

        if ConfigPath.exists {
            do {
                loaded = try ConfigStore.readFromDisk()
                initialStatus = .loaded
            } catch {
                initialStatus = .invalid(reason: "\(error)")
            }
        } else {
            initialStatus = .createdNew
        }
        self.config = loaded
        self.status = initialStatus
        self.startWatcher()
        if !ConfigPath.exists {
            saveImmediately()  // writes the default file; updates status if write fails
        }
    }

    // MARK: - Public mutation

    public func update(_ mutate: (inout AviConfig) -> Void) {
        var copy = config
        mutate(&copy)
        guard copy != config else { return }
        config = copy
        scheduleSave()
    }

    /// Apply a snapshot (e.g. from import). Persists immediately.
    public func replace(with newConfig: AviConfig) {
        guard newConfig != config else { return }
        config = newConfig
        saveImmediately()
    }

    public func reload() {
        guard ConfigPath.exists else {
            status = .createdNew
            saveImmediately()
            return
        }
        do {
            let updated = try ConfigStore.readFromDisk()
            if updated != config {
                config = updated
            }
            status = .loaded
        } catch {
            // Keep the previous in-memory config; surface the issue.
            status = .invalid(reason: "\(error)")
        }
    }

    public func reset() {
        config = AviConfig()
        saveImmediately()
        KeychainStore.deleteAll()
    }

    public func exportTOML() throws -> String {
        try ConfigStore.serialize(config)
    }

    public func importTOML(_ text: String) throws {
        let imported = try ConfigStore.decode(from: text)
        replace(with: imported)
    }

    // MARK: - Disk I/O

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            saveImmediately()
        }
    }

    private func saveImmediately() {
        do {
            try ConfigPath.ensureDirectoryExists()
            let text = try ConfigStore.serialize(config)
            let url = ConfigPath.fileURL
            ignoreNextWatcherEvent = true
            // Atomic write via temp file + rename.
            let tmp = url.appendingPathExtension("tmp")
            try text.data(using: .utf8)?.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            // Only flip from "createdNew" to "loaded" once the file exists and
            // we've not surfaced an unrelated error.
            if case .invalid = status {} else if case .pathNotWritable = status {} else {
                status = .loaded
            }
        } catch {
            status = .pathNotWritable(reason: "\(error)")
        }
    }

    private static func readFromDisk() throws -> AviConfig {
        let url = ConfigPath.fileURL
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ConfigStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Config file is not UTF-8"])
        }
        return try decode(from: text)
    }

    private static func serialize(_ config: AviConfig) throws -> String {
        let raw = try JSONEncoder().encode(config)
        guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw NSError(domain: "ConfigStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Encoded config is not a dict"])
        }
        let normalized = normalizeForTOML(object)
        return MiniTOML.encode(normalized as! [String: Any])
    }

    private static func decode(from text: String) throws -> AviConfig {
        let dict = try MiniTOML.parse(text)
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(AviConfig.self, from: data)
    }

    /// `JSONSerialization` produces `NSNumber` etc; we need plain Swift values for MiniTOML.
    private static func normalizeForTOML(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                out[k] = normalizeForTOML(v)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map(normalizeForTOML)
        }
        if let n = value as? NSNumber {
            // Determine if this is a bool, an int, or a double.
            // CFGetTypeID(n) == CFBooleanGetTypeID() detects bools.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue
            }
            let raw = String(cString: n.objCType)
            if raw == "q" || raw == "i" || raw == "l" || raw == "s" || raw == "Q" || raw == "I" || raw == "L" || raw == "S" {
                return n.intValue
            }
            return n.doubleValue
        }
        return value
    }

    // MARK: - Watcher

    private func startWatcher() {
        do {
            try ConfigPath.ensureDirectoryExists()
        } catch {
            return
        }
        let dirPath = ConfigPath.directoryURL.path
        let w = ConfigWatcher(path: dirPath) { [weak self] in
            self?.handleWatcherEvent()
        }
        w.start()
        watcher = w
    }

    private func handleWatcherEvent() {
        if ignoreNextWatcherEvent {
            ignoreNextWatcherEvent = false
            return
        }
        reload()
    }
}
