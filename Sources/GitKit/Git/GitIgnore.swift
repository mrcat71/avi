import Foundation

/// Builds ignore patterns for a changed file and appends them to `.gitignore`
/// or `.git/info/exclude`. Patterns match literally: a name containing `*`,
/// `?`, `[`, or `\` is escaped so it never matches other files.
public enum GitIgnore {
    /// Matches exactly `path`, anchored at the repository root. A folder
    /// pattern ends in `/` and covers everything inside it.
    public static func pattern(forPath path: String, isDirectory: Bool) throws -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else {
            throw GitError.invalidInput("A path with a line break cannot be written to an ignore file.")
        }
        return "/" + escape(trimmed) + (isDirectory ? "/" : "")
    }

    /// `*.ext`, matching files with the same extension in every folder. Nil for
    /// a name without one, or a dotfile such as `.env` whose "extension" is its name.
    public static func extensionPattern(forPath path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, name != "." + ext, !ext.contains(where: \.isNewline) else { return nil }
        return "*." + escape(ext)
    }

    /// Folders containing `path`, nearest first: `a/b/c.txt` gives `a/b` and `a`.
    public static func parentFolders(of path: String) -> [String] {
        var folders: [String] = []
        var current = (path as NSString).deletingLastPathComponent
        while !current.isEmpty, current != "/", current != "." {
            folders.append(current)
            current = (current as NSString).deletingLastPathComponent
        }
        return folders
    }

    /// Adds `pattern` on its own line at the end of `file`, creating the file
    /// and its folder when missing. Appending in place keeps a symlinked
    /// ignore file a symlink. Returns false when the pattern is already listed.
    @discardableResult
    public static func append(_ pattern: String, to file: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: file.path) else {
            try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: file.path, contents: Data((pattern + "\n").utf8)) else {
                throw GitError.invalidInput("Could not create \(file.path).")
            }
            return true
        }
        let existing = try Data(contentsOf: file)
        let lines = String(decoding: existing, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        guard !lines.contains(where: { $0 == pattern }) else { return false }
        let needsNewline = existing.last.map { $0 != 0x0A } ?? false
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(((needsNewline ? "\n" : "") + pattern + "\n").utf8))
        return true
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\*?[".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        // Git drops trailing spaces from a pattern unless each is escaped.
        let trailing = escaped.reversed().prefix { $0 == " " }.count
        guard trailing > 0 else { return escaped }
        return String(escaped.dropLast(trailing)) + String(repeating: "\\ ", count: trailing)
    }
}
