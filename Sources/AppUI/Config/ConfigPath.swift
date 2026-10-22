import AppKit
import Foundation

/// Canonical location for the Avi config file.
enum ConfigPath {
    static let appName = "Avi"
    static let fileName = "config.toml"

    #if DEBUG
    /// Set by the screenshot harness, so a run never reads or writes your
    /// config file.
    nonisolated(unsafe) static var directoryOverride: URL?
    #endif

    static var directoryURL: URL {
        #if DEBUG
        if let directoryOverride {
            return directoryOverride
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func ensureDirectoryExists() throws {
        let dir = directoryURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func openFile() {
        NSWorkspace.shared.open(fileURL)
    }

    static func openFolder() {
        NSWorkspace.shared.open(directoryURL)
    }
}
