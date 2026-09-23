import Foundation

/// An ordered list of commits, each taking the working-tree content of its
/// files. Paths are literal and relative to the repository root. Changes to
/// files outside the plan, staged or not, stay where they are.
public struct FileCommitPlan: Sendable, Equatable {
    public struct Commit: Sendable, Equatable {
        public let files: [String]
        public let message: String

        public init(files: [String], message: String) {
            self.files = files
            self.message = message
        }
    }

    public let commits: [Commit]

    public init(commits: [Commit]) {
        self.commits = commits
    }

    /// Why a plan cannot be applied to the current working copy. Each case
    /// names the offending paths so a caller can correct the plan.
    public enum ValidationError: Error, Sendable, Equatable {
        case noCommits
        case emptyMessage(commit: Int)
        case noFiles(commit: Int)
        case unknownPaths([String])
        case duplicatePaths([String])
        case conflicts([String])
    }

    /// Checks the plan against `status` and returns its commits with both sides
    /// of every staged rename in the same commit. Listing either side of a
    /// rename brings in the other, since committing one without the other would
    /// split the rename into an unrelated delete and add.
    public func resolved(against status: WorkingCopyStatus) throws -> [Commit] {
        guard !commits.isEmpty else { throw ValidationError.noCommits }
        let conflicted = status.entries
            .filter { $0.index == .updatedButUnmerged || $0.worktree == .updatedButUnmerged }
            .map(\.path)
        guard conflicted.isEmpty else { throw ValidationError.conflicts(conflicted) }

        var partner: [String: String] = [:]
        for entry in status.entries {
            guard let original = entry.originalPath, entry.index == .renamed else { continue }
            partner[entry.path] = original
            partner[original] = entry.path
        }
        let changed = Set(status.entries.map(\.path)).union(partner.keys)

        var resolved: [Commit] = []
        var unknown: [String] = []
        var seen = Set<String>()
        var duplicates: [String] = []
        for (index, commit) in commits.enumerated() {
            guard !commit.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.emptyMessage(commit: index + 1)
            }
            guard !commit.files.isEmpty else { throw ValidationError.noFiles(commit: index + 1) }
            var files: [String] = []
            for path in commit.files {
                guard changed.contains(path) else {
                    unknown.append(path)
                    continue
                }
                for member in [path, partner[path]].compactMap(\.self) where !files.contains(member) {
                    files.append(member)
                }
            }
            for path in files where !seen.insert(path).inserted {
                duplicates.append(path)
            }
            resolved.append(Commit(files: files, message: commit.message))
        }
        guard unknown.isEmpty else { throw ValidationError.unknownPaths(unknown) }
        guard duplicates.isEmpty else { throw ValidationError.duplicatePaths(duplicates) }
        return resolved
    }
}

extension FileCommitPlan.ValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noCommits:
            return "A commit plan needs at least one commit."
        case .emptyMessage(let commit):
            return "Commit \(commit) needs a message."
        case .noFiles(let commit):
            return "Commit \(commit) has no files."
        case .unknownPaths(let paths):
            return "These paths have no changes to commit: \(paths.joined(separator: ", "))"
        case .duplicatePaths(let paths):
            return "Each file can be in only one commit: \(paths.joined(separator: ", "))"
        case .conflicts(let paths):
            return "Resolve conflicts before committing: \(paths.joined(separator: ", "))"
        }
    }
}

/// A plan stopped part way. Commits made before the failure stay in history;
/// nothing is rolled back or retried, because hooks may already have acted.
public struct CommitPlanError: Error, Sendable, Equatable, LocalizedError {
    public let completed: Int
    public let total: Int
    public let reason: String

    public init(completed: Int, total: Int, reason: String) {
        self.completed = completed
        self.total = total
        self.reason = reason
    }

    public var errorDescription: String? {
        "Stopped after \(completed) of \(total) commits. Check history and the remaining changes before continuing. "
            + "No automatic rollback was attempted.\n\n\(reason)"
    }
}
