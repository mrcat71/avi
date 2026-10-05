import Foundation
import GitKit

/// Where a detached HEAD points. AI agents leave HEAD detached often, in this
/// repository or in their own worktrees, and a commit made there belongs to
/// no branch.
public struct DetachedHead: Equatable, Sendable {
    public let oid: String
    public let subject: String
    /// Commits HEAD has that no branch, tag, or remote branch has: what
    /// switching away would leave only in the reflog. Nil when Git could not
    /// count them.
    public let unreferencedCount: Int?
    /// Local branches at this very commit; switching to one loses nothing.
    public let branchesHere: [String]

    public var shortOID: String {
        String(oid.prefix(8))
    }
}

/// A checkout that would strand a detached HEAD's commits, waiting for you.
public struct PendingCheckout: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let ref: GitReference
    public let carryingLocalChanges: Bool
    public let leftBehind: Int
}

/// How removing a worktree went.
public enum WorktreeRemoval: Equatable, Sendable {
    case removed
    /// Git refused because the worktree has uncommitted or untracked files.
    case needsForce
    case failed
}

// MARK: - Detached HEAD

public extension RepositoryStore {
    /// Fills `detachedHead` while HEAD is detached and clears it otherwise.
    func refreshDetachedHead() async {
        guard let root, let head = branch, head.isDetached, let oid = head.oid else {
            if detachedHead != nil {
                detachedHead = nil
            }
            return
        }
        let count: Int?
        do {
            count = try await git.unreferencedCommitCount(in: root)
        } catch {
            // Without a count the banner still says commits here go nowhere.
            count = nil
        }
        var subject = historyRows.first { $0.commit.oid == oid }?.commit.subject
        if subject == nil {
            subject = try? await git.commitMessage(for: oid, in: root)?.split(separator: "\n").first.map(String.init)
        }
        let value = DetachedHead(
            oid: oid,
            subject: subject ?? "",
            unreferencedCount: count,
            branchesHere: refs.localBranches.filter { $0.oid == oid }.map(\.name)
        )
        if detachedHead != value {
            detachedHead = value
        }
    }

    /// Switches once you confirmed leaving the detached HEAD's commits behind.
    func checkoutLeavingCommits(_ pending: PendingCheckout) async {
        if pendingCheckout?.id == pending.id {
            pendingCheckout = nil
        }
        await checkoutConfirmed(pending.ref, carryingLocalChanges: pending.carryingLocalChanges)
    }
}

extension RepositoryStore {
    /// True when the checkout may go ahead. When it would leave a detached
    /// HEAD's unbranched commits behind, it waits in `pendingCheckout` instead.
    func confirmLeavingDetachedHead(for ref: GitReference, carryingLocalChanges: Bool) -> Bool {
        guard let head = detachedHead, let count = head.unreferencedCount, count > 0, ref.targetOID != head.oid else {
            return true
        }
        pendingCheckout = PendingCheckout(ref: ref, carryingLocalChanges: carryingLocalChanges, leftBehind: count)
        return false
    }

    /// A worktree of this repository inside its folder. Git lists it as an
    /// untracked folder whose `.git` file points into our common dir.
    func isLinkedWorktreeEntry(_ entry: FileStatus) -> Bool {
        guard entry.isUntracked, entry.path.hasSuffix("/"), let root, let commonDir = location?.commonDir else { return false }
        let folder = root.appendingPathComponent(entry.path, isDirectory: true)
        guard let text = try? String(contentsOf: folder.appendingPathComponent(".git"), encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:")
        else { return false }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDir = target.hasPrefix("/") ? URL(fileURLWithPath: target) : folder.appendingPathComponent(target)
        let worktrees = commonDir.appendingPathComponent("worktrees").resolvingSymlinksInPath().standardizedFileURL.path
        return gitDir.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(worktrees + "/")
    }
}

// MARK: - Worktrees

public extension RepositoryStore {
    /// Removes `worktree`'s folder and Git's record of it. Its branch stays.
    func removeWorktree(_ worktree: Worktree, force: Bool) async -> WorktreeRemoval {
        guard let root else { return .failed }
        do {
            try await git.removeWorktree(at: worktree.path, force: force, in: root)
        } catch let error as GitError {
            if !force, case let .commandFailed(_, _, stderr) = error, GitError.indicatesDirtyWorktree(stderr) {
                return .needsForce
            }
            errorMessage = error.localizedDescription
            return .failed
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
        // A tab open on it has nothing left to show.
        NotificationCenter.default.post(name: .aviWorktreeRemoved, object: worktree.path)
        await refresh()
        return .removed
    }

    /// Forgets worktrees whose folders were deleted without Git.
    func pruneWorktrees() async {
        await perform { _ = try await $0.pruneWorktrees(in: $1) }
    }

    /// Puts a detached worktree on a new branch, so its commits have a name.
    func createBranch(named name: String, inWorktree worktree: Worktree) async {
        await perform { git, _ in
            try await git.createBranch(named: name, startPoint: nil, checkout: true, in: worktree.path)
        }
    }

    /// Other worktrees whose changes and detached commits the sidebar shows.
    var otherWorktrees: [Worktree] {
        let current = currentWorktree?.id
        return worktrees.filter { $0.id != current && !$0.isBare && !$0.isPrunable }
    }
}

extension RepositoryStore {
    /// Counts each other worktree's uncommitted changes and names detached
    /// commits, in the background. An agent working in a worktree inside this
    /// folder refreshes the repository constantly, so this runs at most every
    /// few seconds unless the worktrees changed.
    func refreshWorktreeDetails(force: Bool) {
        let others = otherWorktrees
        guard !others.isEmpty else {
            worktreeDetailsTask?.cancel()
            if !worktreeChanges.isEmpty {
                worktreeChanges = [:]
            }
            return
        }
        if !force, let loaded = worktreeDetailsLoaded, Date().timeIntervalSince(loaded) < 5 {
            return
        }
        worktreeDetailsLoaded = Date()
        worktreeDetailsTask?.cancel()
        let git = git
        worktreeDetailsTask = Task { [weak self] in
            var changes: [String: Int] = [:]
            var subjects: [String: String] = [:]
            for worktree in others {
                if let status = try? await git.status(in: worktree.path) {
                    changes[worktree.id] = status.entries.count
                }
                if worktree.isDetached, let oid = worktree.headOID,
                   let message = try? await git.commitMessage(for: oid, in: worktree.path) {
                    subjects[oid] = message.split(separator: "\n").first.map(String.init) ?? ""
                }
                if Task.isCancelled {
                    return
                }
            }
            guard let self else { return }
            if worktreeChanges != changes {
                worktreeChanges = changes
            }
            if worktreeSubjects != subjects {
                worktreeSubjects = subjects
            }
        }
    }
}
