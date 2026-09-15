import Foundation

/// A file-level partition of an already reviewed staged diff.
public struct StagedCommitPlan: Sendable {
    public struct Group: Sendable {
        public let files: [String]
        public let message: String

        public init(files: [String], message: String) {
            self.files = files
            self.message = message
        }
    }

    public let groups: [Group]
    public let expectedDiff: String

    public init(groups: [Group], expectedDiff: String) {
        self.groups = groups
        self.expectedDiff = expectedDiff
    }

    func validate(status: WorkingCopyStatus, currentDiff: String) throws {
        guard !expectedDiff.isEmpty, currentDiff == expectedDiff else {
            throw GitError.invalidInput("Staged changes have changed. Generate a new split preview before applying.")
        }
        let staged = status.entries.filter(\.isStaged)
        guard !staged.isEmpty, !groups.isEmpty else {
            throw GitError.invalidInput("A split requires staged files and at least one commit group.")
        }
        guard !status.entries.contains(where: { $0.index == .updatedButUnmerged || $0.worktree == .updatedButUnmerged }) else {
            throw GitError.invalidInput("Resolve conflicts before splitting staged changes.")
        }
        guard staged.allSatisfy({ !$0.hasUnstagedChanges && $0.originalPath == nil }) else {
            throw GitError.invalidInput("File-level splitting does not support partially staged files or renames. Commit these separately first.")
        }
        var seen = Set<String>()
        let allowed = Set(staged.map(\.path))
        for group in groups {
            guard !group.files.isEmpty, !group.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GitError.invalidInput("Each commit group needs files and a non-empty message.")
            }
            for path in group.files {
                guard allowed.contains(path), seen.insert(path).inserted else {
                    throw GitError.invalidInput("Each staged file must appear exactly once in the split preview.")
                }
            }
        }
        guard seen == allowed else {
            throw GitError.invalidInput("The split preview must include every staged file.")
        }
    }
}
