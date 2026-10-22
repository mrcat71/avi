import Foundation
import GitKit

/// A tag an agent proposed for a commit that already exists.
public struct TagProposal: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: DraftSource
    public let tag: NewTag
    /// Full ID of the commit the tag goes on, resolved when the proposal arrived.
    public let commit: String
    public let subject: String
}

/// The sheet that adds a tag to a commit you are about to make, or edits one.
public struct TagEditRequest: Identifiable, Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case stagedCommit
        case draft(UUID)
    }

    public let id = UUID()
    public let target: Target
    /// The tag being edited; nil adds a new one.
    public let original: NewTag?
}

/// A tag on a commit that a push sends.
public struct PushTagChoice: Identifiable, Equatable, Sendable {
    public let name: String
    public let isAnnotated: Bool
    /// You approved it in Avi, or it is annotated, which Git treats as meant
    /// for publishing: the Push sheet ticks it and Push sends it.
    public let isPreselected: Bool

    public var id: String {
        name
    }
}

// MARK: - Tags on the commits you are about to make

public extension RepositoryStore {
    func tags(for target: TagEditRequest.Target) -> [NewTag] {
        switch target {
        case .stagedCommit: return commitTags
        case .draft(let id): return commitPlan.draft(id: id)?.tags ?? []
        }
    }

    func setTags(_ tags: [NewTag], for target: TagEditRequest.Target) {
        switch target {
        case .stagedCommit: commitTags = tags
        case .draft(let id): commitPlan.setTags(tags, for: id)
        }
    }

    func requestTagEdit(for target: TagEditRequest.Target, editing tag: NewTag? = nil) {
        tagEditRequest = TagEditRequest(target: target, original: tag)
    }

    /// Adds `tag`, or puts it in the place of `original`.
    func saveTag(_ tag: NewTag, replacing original: NewTag?, for target: TagEditRequest.Target) {
        var tags = tags(for: target)
        if let original, let index = tags.firstIndex(where: { $0.name == original.name }) {
            tags[index] = tag
        } else {
            tags.append(tag)
        }
        setTags(CommitPlan.uniqueTags(tags), for: target)
    }

    func removeTag(named name: String, from target: TagEditRequest.Target) {
        setTags(tags(for: target).filter { $0.name != name }, for: target)
    }

    /// Why `name` cannot be a new tag here, or nil. `original` is the name of
    /// the tag being renamed, which may keep its name.
    func tagNameProblem(_ name: String, replacing original: String? = nil) -> String? {
        if let problem = NewTag.problem(with: name) {
            return problem
        }
        guard name != original else { return nil }
        if refs.tags.contains(where: { $0.name == name }) {
            return "A tag named \(name) already exists."
        }
        if pendingTagNames.contains(name) {
            return "A commit or tag waiting here already creates \(name)."
        }
        return nil
    }

    /// Every tag a commit you are about to make or a tag proposal would create.
    var pendingTagNames: Set<String> {
        var names = commitPlan.plannedTagNames
            .union(commitTags.map(\.name))
            .union(tagProposals.map(\.tag.name))
        if let field = fieldProposal {
            names.formUnion(field.tags.map(\.name))
        }
        return names
    }
}

// MARK: - Tags agents propose for existing commits

public extension RepositoryStore {
    /// Places an agent's tag for a commit that already exists. It waits in a
    /// banner until you create or dismiss it, replacing the session's earlier
    /// tag proposal. `revision` is resolved now, so the tag lands on the commit
    /// the agent meant even after you commit something else.
    func receiveTagProposal(_ tag: NewTag, at revision: String, source: DraftSource) async throws -> ProposalOutcome {
        guard let root else { throw ProposalRejection.busy }
        try Self.checkTagNames([tag.name])
        await refresh()
        if refs.tags.contains(where: { $0.name == tag.name }) {
            throw ProposalRejection.tagExists(name: tag.name, owner: nil)
        }
        // Here the session's own pending commits count: they would create it twice.
        if let owner = commitTagOwner(tag.name) {
            throw ProposalRejection.tagExists(name: tag.name, owner: owner)
        }
        if let other = tagProposals.first(where: { $0.tag.name == tag.name && $0.source.groupKey != source.groupKey }) {
            throw ProposalRejection.tagExists(name: tag.name, owner: other.source.displayName)
        }
        guard let commit = try await git.resolveCommit(revision, in: root) else {
            throw ProposalRejection.unknownRevision(revision)
        }
        let message = try await git.commitMessage(for: commit, in: root) ?? ""
        let subject = CommitMessageParts.split(message).summary
        tagProposals.removeAll { $0.source.groupKey == source.groupKey }
        tagProposals.append(TagProposal(id: UUID(), source: source, tag: tag, commit: commit, subject: subject))
        hasUnseenProposal = true
        return ProposalOutcome(placement: .tag, commits: 0, staged: [], notes: [], tags: [tag.name])
    }

    /// Creates the proposed tag. With `remote`, pushes it there too, which
    /// Avi offers only once that remote has the commit. A tag that could not
    /// be created keeps its proposal, next to the error.
    func acceptTagProposal(_ id: UUID, pushingTo remote: String? = nil) async {
        guard let proposal = tagProposals.first(where: { $0.id == id }) else { return }
        await createTag(name: proposal.tag.name, targetOID: proposal.commit, message: proposal.tag.message)
        guard refs.tags.contains(where: { $0.name == proposal.tag.name }) else { return }
        tagProposals.removeAll { $0.id == id }
        if let remote {
            await pushTag(name: proposal.tag.name, remote: remote)
        }
    }

    func dismissTagProposal(_ id: UUID) {
        tagProposals.removeAll { $0.id == id }
    }

    // MARK: Pushing

    /// The tags on commits a push of `branch` to `remote` sends. Those you
    /// approved in Avi and annotated ones come ticked.
    func tagsForPush(branch: String, remote: String) async throws -> [PushTagChoice] {
        guard let root else { return [] }
        return try await git.unpushedTags(branch: branch, remote: remote, in: root).map {
            PushTagChoice(name: $0.name, isAnnotated: $0.isAnnotated, isPreselected: $0.isAnnotated || publishableTags.contains($0.name))
        }
    }

    /// Whether `remote` has `commit` on one of its branches, so a tag on it
    /// can be pushed alone without arriving before the commit.
    func remoteHasCommit(_ commit: String, remote: String) async -> Bool {
        guard let root else { return false }
        do {
            return try await git.remoteHasCommit(commit, remote: remote, in: root)
        } catch {
            Self.pushLog.error("Could not tell whether \(remote, privacy: .public) has \(commit, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

// MARK: - Helpers

extension RepositoryStore {
    /// Creates `tags` on `target`. Returns a line per tag that failed.
    func createTags(_ tags: [NewTag], at target: String) async -> [String] {
        guard let root else { return [] }
        var failures: [String] = []
        for tag in tags {
            do {
                try await git.createTag(name: tag.name, targetOID: target, message: tag.message, in: root)
                publishableTags.insert(tag.name)
            } catch {
                failures.append("\(tag.name): \(error.localizedDescription)")
            }
        }
        return failures
    }

    static func describeTagFailures(_ failures: [String]) -> String {
        "Committed, but \(failures.count == 1 ? "this tag was" : "these tags were") not created:\n\n" + failures.joined(separator: "\n")
    }

    /// Rejects names Git would refuse, and a name given twice.
    static func checkTagNames(_ names: [String]) throws {
        var seen = Set<String>()
        for name in names {
            if let problem = NewTag.problem(with: name) {
                throw ProposalRejection.invalidTag(name: name, problem: problem)
            }
            guard seen.insert(name).inserted else {
                throw ProposalRejection.invalidTag(name: name, problem: "The proposal names it twice.")
            }
        }
    }

    /// Throws unless a commit proposal from `source` may create `name`. Its
    /// own earlier proposal does not count, since the new one replaces it.
    func checkTagIsFree(_ name: String, for source: DraftSource) throws {
        if refs.tags.contains(where: { $0.name == name }) {
            throw ProposalRejection.tagExists(name: name, owner: nil)
        }
        if let owner = commitTagOwner(name, ignoring: source) {
            throw ProposalRejection.tagExists(name: name, owner: owner)
        }
        if let other = tagProposals.first(where: { $0.tag.name == name && $0.source.groupKey != source.groupKey }) {
            throw ProposalRejection.tagExists(name: name, owner: other.source.displayName)
        }
    }

    /// Who creates `name` with a commit you are about to make: a planned
    /// commit's source, the commit field's proposal, or you. Commits from
    /// `source` are left out.
    func commitTagOwner(_ name: String, ignoring source: DraftSource? = nil) -> String? {
        let key = source?.groupKey
        if let draft = commitPlan.drafts.first(where: { $0.source.groupKey != key && $0.tags.contains { $0.name == name } }) {
            return draft.source.displayName
        }
        if let field = fieldProposal, field.tags.contains(where: { $0.name == name }) {
            return field.source.groupKey == key ? nil : field.source.displayName
        }
        return commitTags.contains { $0.name == name } ? "you" : nil
    }
}
