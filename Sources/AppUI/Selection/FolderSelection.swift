import GitKit

/// In a changed-files tree, selecting a folder selects everything inside it,
/// collapsed subfolders included, so one click stages, unstages, or discards
/// a whole folder. Tags are whatever the list uses for its rows.
enum FolderSelection {
    /// `new`, as the list reported it, widened for folders: every selected
    /// folder brings the files and folders under it along. With `isToggle`
    /// (a Command-click), only a folder switched on brings its contents, and
    /// one switched off takes them away, so single files inside can still be
    /// switched off.
    static func apply(
        old: Set<String>,
        new: Set<String>,
        entries: [FileStatus],
        fileTag: (String) -> String,
        folderTag: (String) -> String,
        isToggle: Bool = false
    ) -> Set<String> {
        let folders = FileTreeBuilder.allFolderIds(for: entries)
        guard !folders.isEmpty else { return new }
        let folderByTag = Dictionary(folders.map { (folderTag($0), $0) }, uniquingKeysWith: { first, _ in first })
        func contents(_ tag: String) -> Set<String> {
            guard let folder = folderByTag[tag] else { return [] }
            return Self.contents(of: folder, entries: entries, folders: folders, fileTag: fileTag, folderTag: folderTag)
        }
        var result = new
        if isToggle {
            for tag in new.subtracting(old) {
                result.formUnion(contents(tag))
            }
            for tag in old.subtracting(new) {
                result.subtract(contents(tag))
            }
        } else {
            for tag in new {
                result.formUnion(contents(tag))
            }
        }
        return result
    }

    /// The files under `folder`, nested ones included.
    static func files(in folder: String, entries: [FileStatus]) -> [FileStatus] {
        let prefix = folder + "/"
        return entries.filter { $0.path.hasPrefix(prefix) }
    }

    private static func contents(
        of folder: String,
        entries: [FileStatus],
        folders: Set<String>,
        fileTag: (String) -> String,
        folderTag: (String) -> String
    ) -> Set<String> {
        let prefix = folder + "/"
        let fileTags = files(in: folder, entries: entries).map { fileTag($0.path) }
        let folderTags = folders.filter { $0.hasPrefix(prefix) }.map(folderTag)
        return Set(fileTags).union(folderTags)
    }
}
