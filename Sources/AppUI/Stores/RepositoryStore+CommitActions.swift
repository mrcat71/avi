import AppKit
import Foundation
import GitKit
import UniformTypeIdentifiers

// MARK: - History's commit menu

public extension RepositoryStore {
    /// The loaded commits HEAD reaches, HEAD included: the ones a reset, an
    /// interactive rebase, or a revert can work on. Cherry-picking one of them
    /// would change nothing.
    func headAncestry() -> Set<String> {
        guard let head = detachedHead?.oid ?? branch?.oid else { return [] }
        var parents: [String: [String]] = [:]
        for row in historyRows {
            parents[row.commit.oid] = row.commit.parentOIDs
        }
        var reached: Set<String> = []
        var queue = [head]
        while let oid = queue.popLast() {
            guard parents[oid] != nil, reached.insert(oid).inserted else { continue }
            queue.append(contentsOf: parents[oid] ?? [])
        }
        return reached
    }

    func cherryPick(_ commit: CommitSummary) async {
        await runIntegration { try await $0.cherryPick(commit: commit.oid, isMerge: commit.parentOIDs.count > 1, in: $1) }
    }

    func revert(_ commit: CommitSummary) async {
        await runIntegration { try await $0.revert(commit: commit.oid, isMerge: commit.parentOIDs.count > 1, in: $1) }
    }

    /// Detaches HEAD at the commit. Git refuses rather than overwrite local changes.
    func checkoutCommit(_ commit: CommitSummary) async {
        await perform { try await $0.checkoutDetached(commit: commit.oid, in: $1) }
    }

    /// Moves the current branch, or a detached HEAD, to the commit.
    func reset(to commit: CommitSummary, mode: GitResetMode) async {
        await perform { try await $0.reset(mode: mode, target: commit.oid, in: $1) }
    }

    /// Starts an interactive rebase that stops at the commit, to amend it, then Continue.
    func editCommit(_ commit: CommitSummary) async {
        await perform { try await $0.rebaseSingle(commit: commit.oid, action: .edit, in: $1) }
        if operationState == .rebase {
            workspaceSelection = .localChanges
        }
    }

    /// "Save as Patch…": asks where, then writes the commit as an mbox patch.
    func savePatch(for commit: CommitSummary) async {
        guard let root else { return }
        let panel = NSSavePanel()
        panel.title = "Save as Patch"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .plainText]
        panel.nameFieldStringValue = "\(commit.shortOID)-\(Self.patchName(commit.subject)).patch"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let patch = try await git.formatPatch(commit: commit.oid, in: root)
            try patch.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebaseCandidates(ontoRevision revision: String) async throws -> [CommitSummary] {
        guard let root else { return [] }
        return try await git.rebaseCandidates(ontoRevision: revision, in: root)
    }

    func interactiveRebase(ontoRevision revision: String, plan: InteractiveRebasePlan, autostash: Bool) async {
        await runIntegration { try await $0.interactiveRebase(ontoRevision: revision, plan: plan, autostash: autostash, in: $1) }
    }

    func changedFilesAgainstWorkingTree(from oid: String) async throws -> [CommitFileChange] {
        guard let root else { return [] }
        return try await git.changedFilesAgainstWorkingTree(from: oid, in: root)
    }

    func diffAgainstWorkingTree(from oid: String, file: CommitFileChange) async throws -> FileDiff {
        guard let root else { return FileDiff(hunks: [], isBinary: false) }
        return try await git.diffAgainstWorkingTree(from: oid, path: file.path, oldPath: file.oldPath, options: DiffPreferences.shared.gitOptions, in: root)
    }

    /// A file name from a commit subject, as `git format-patch` makes one.
    static func patchName(_ subject: String) -> String {
        let words = subject.lowercased().split { !$0.isLetter && !$0.isNumber }
        let name = words.joined(separator: "-")
        return name.isEmpty ? "commit" : String(name.prefix(52))
    }
}

// MARK: - Picked lines in the Changes view

extension RepositoryStore {
    /// Stages, unstages, or discards only the picked lines of `file`. The
    /// patch comes from Git's own diff of the file, so a diff shown with more
    /// context, the whole file, or whitespace hidden still applies cleanly.
    func applyLines(_ command: DiffLineCommand, keys: Set<DiffLineKey>, file: FileStatus) async {
        guard let root else { return }
        let source: DiffSource = command == .unstage ? .staged : .unstaged
        do {
            let diff = try await git.diff(path: file.path, source: source, options: .standard, in: root)
            guard let patch = PartialPatch.make(
                diff: diff, path: file.path, selection: keys, direction: command == .stage ? .forward : .reverse
            ) else {
                errorMessage = "The picked lines changed since they were shown. Pick them again."
                return
            }
            await perform { try await $0.applyPatch(patch, toIndex: command != .discard, reverse: command != .stage, in: $1) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
