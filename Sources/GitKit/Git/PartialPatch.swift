import Foundation

/// A line of a diff the user picked, named by the side it lives on: added
/// lines by their number in the new file, removed lines by their number in
/// the old one. Numbers survive a diff shown with more context or the whole
/// file, so a selection made there still finds its lines in Git's own diff.
public struct DiffLineKey: Hashable, Sendable {
    public enum Side: Hashable, Sendable {
        case added
        case removed
    }

    public let side: Side
    public let number: Int

    public init(side: Side, number: Int) {
        self.side = side
        self.number = number
    }

    public init?(_ line: DiffLine) {
        switch line.kind {
        case .addition:
            guard let number = line.newLineNumber else { return nil }
            self.init(side: .added, number: number)
        case .deletion:
            guard let number = line.oldLineNumber else { return nil }
            self.init(side: .removed, number: number)
        case .context, .noNewline:
            return nil
        }
    }
}

/// Builds the patch that moves only the picked lines of a file's diff, for
/// `git apply`. Lines left out keep their place: in a forward patch an
/// unpicked removal stays as context and an unpicked addition is dropped; in
/// a reverse patch it is the other way round.
public enum PartialPatch {
    public enum Direction: Sendable {
        /// Applied as is: staging lines of the unstaged diff into the index.
        case forward
        /// Applied with `--reverse`: unstaging lines of the staged diff, or
        /// discarding lines of the unstaged diff from the working tree.
        case reverse
    }

    /// The patch for `path`, or nil when no picked line is a change in `diff`.
    public static func make(diff: FileDiff, path: String, selection: Set<DiffLineKey>, direction: Direction) -> String? {
        var hunks: [String] = []
        // How far the side Git does not match against has drifted, from the
        // hunks before: lines added minus lines removed.
        var offset = 0
        for hunk in diff.hunks {
            guard let built = build(hunk, selection: selection, direction: direction, offset: offset) else { continue }
            hunks.append(built.text)
            offset += direction == .forward ? built.newCount - built.oldCount : built.oldCount - built.newCount
        }
        guard !hunks.isEmpty else { return nil }
        let header = "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n"
        return header + hunks.joined()
    }

    private static func build(
        _ hunk: DiffHunk,
        selection: Set<DiffLineKey>,
        direction: Direction,
        offset: Int
    ) -> (text: String, oldCount: Int, newCount: Int)? {
        var body: [String] = []
        var oldCount = 0
        var newCount = 0
        var picksChange = false
        // Whether the line before a "\ No newline" marker made it into the patch.
        var previousKept = false

        for line in hunk.lines {
            let picked = DiffLineKey(line).map(selection.contains) ?? false
            switch line.kind {
            case .context:
                body.append(" " + line.text)
                oldCount += 1
                newCount += 1
                previousKept = true
            case .addition:
                if picked {
                    body.append("+" + line.text)
                    newCount += 1
                    picksChange = true
                    previousKept = true
                } else if direction == .reverse {
                    // Stays in the file the patch is reversed against.
                    body.append(" " + line.text)
                    oldCount += 1
                    newCount += 1
                    previousKept = true
                } else {
                    previousKept = false
                }
            case .deletion:
                if picked {
                    body.append("-" + line.text)
                    oldCount += 1
                    picksChange = true
                    previousKept = true
                } else if direction == .forward {
                    // Stays in the file the patch applies to.
                    body.append(" " + line.text)
                    oldCount += 1
                    newCount += 1
                    previousKept = true
                } else {
                    previousKept = false
                }
            case .noNewline:
                if previousKept {
                    body.append("\\ No newline at end of file")
                }
            }
        }
        guard picksChange else { return nil }
        // Git finds a hunk by the side it applies to: the old one for a forward
        // patch, the new one for a reverse patch. That side is the file as it
        // is, so it keeps Git's own numbers; the other side follows from it.
        // A side with no lines is numbered from the line before it.
        let oldStart: Int
        let newStart: Int
        switch direction {
        case .forward:
            oldStart = hunk.oldStart
            newStart = max(hunk.oldStart + offset + (oldCount == 0 ? 1 : 0) - (newCount == 0 ? 1 : 0), 0)
        case .reverse:
            newStart = hunk.newStart
            oldStart = max(hunk.newStart + offset + (newCount == 0 ? 1 : 0) - (oldCount == 0 ? 1 : 0), 0)
        }
        let header = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@\n"
        return (header + body.joined(separator: "\n") + "\n", oldCount, newCount)
    }
}

public extension CLIGitProvider {
    /// `git apply` of a patch from `PartialPatch`: to the index for staging
    /// and unstaging, to the working tree for discarding. Git checks the
    /// whole patch first and changes nothing when any of it does not apply.
    func applyPatch(_ patch: String, toIndex: Bool, reverse: Bool, in repository: URL) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("avi-\(UUID().uuidString).patch")
        try Data(patch.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var arguments = ["apply", "--recount", "--whitespace=nowarn"]
        if toIndex {
            arguments.append("--cached")
        }
        if reverse {
            arguments.append("--reverse")
        }
        try await run(arguments + [file.path], in: repository)
    }
}
