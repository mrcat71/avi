import Foundation
import GitKit

/// Who proposed a draft. Agent drafts carry the session that sent them, so a
/// session can replace its own proposal without touching anyone else's.
public enum DraftSource: Hashable, Sendable {
    case agent(name: String, session: String, title: String?)
    case ai
    case manual

    /// Drafts with the same key are listed, committed, and discarded together.
    public var groupKey: String {
        switch self {
        case .agent(let name, let session, _): return "agent:\(name):\(session)"
        case .ai: return "ai"
        case .manual: return "manual"
        }
    }

    public var displayName: String {
        switch self {
        case .agent(let name, _, _): return name
        case .ai: return "Avi AI"
        case .manual: return "You"
        }
    }

    /// Heading for a group of drafts, e.g. "Claude Code - Add agent bridge".
    public var groupTitle: String {
        if case .agent(let name, _, let title) = self, let title, !title.isEmpty {
            return "\(name) - \(title)"
        }
        return displayName
    }
}

public struct CommitDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var message: String
    public var files: [String]
    public var source: DraftSource
    /// Set once you change the message or move files, so a resend from the
    /// same agent session cannot silently overwrite your edits.
    public var isEdited: Bool

    public init(id: UUID = UUID(), message: String, files: [String], source: DraftSource, isEdited: Bool = false) {
        self.id = id
        self.message = message
        self.files = files
        self.source = source
        self.isEdited = isEdited
    }

    public var subject: String {
        message.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// What stops a draft from being committed right now.
public enum DraftIssue: Equatable, Sendable {
    case emptyMessage
    case noFiles
    case unchanged([String])
}

/// A run of consecutive drafts from one source, shown under one heading.
public struct PlanGroup: Identifiable, Equatable, Sendable {
    public let source: DraftSource
    public var drafts: [CommitDraft]

    /// Derived from the first draft, so it is unique even when one source has
    /// two runs, but never equal to a draft's own id: the header row and that
    /// draft's row sit in the same list, and a shared id made SwiftUI draw one
    /// in place of the other.
    public var id: String {
        "group:" + drafts[0].id.uuidString
    }
}

/// Where selected files go when moved in the plan.
public enum DraftMoveTarget: Equatable, Sendable {
    case draft(UUID)
    case newDraft
    case unassigned
}

/// Where a file goes when moved in Changes. Commit 1 is the index, so `staged`
/// and `unstaged` stage and unstage; planned commits leave the index alone.
public enum ChangeDestination: Equatable, Sendable {
    case staged
    case unstaged
    case draft(UUID)
    case newDraft
}

/// Pending commits for one repository, in commit order. Drafts from several
/// agent sessions, Avi's AI, and you can sit side by side; each file belongs
/// to at most one draft.
public struct CommitPlan: Equatable, Sendable {
    public var drafts: [CommitDraft] = []

    public init(drafts: [CommitDraft] = []) {
        self.drafts = drafts
    }

    public var isEmpty: Bool {
        drafts.isEmpty
    }

    public var isEdited: Bool {
        drafts.contains(where: \.isEdited)
    }

    public var claimedPaths: Set<String> {
        Set(drafts.flatMap(\.files))
    }

    public func draft(id: UUID) -> CommitDraft? {
        drafts.first { $0.id == id }
    }

    public func owner(of path: String) -> CommitDraft? {
        drafts.first { $0.files.contains(path) }
    }

    /// Changed paths no draft claims, in status order.
    public func unassigned(changed: [String]) -> [String] {
        let claimed = claimedPaths
        return changed.filter { !claimed.contains($0) }
    }

    /// Consecutive drafts from one source, in plan order.
    public var groups: [PlanGroup] {
        var result: [PlanGroup] = []
        for draft in drafts {
            if let last = result.last, last.source.groupKey == draft.source.groupKey {
                result[result.count - 1].drafts.append(draft)
            } else {
                result.append(PlanGroup(source: draft.source, drafts: [draft]))
            }
        }
        return result
    }

    public func issues(of draft: CommitDraft, changed: Set<String>) -> [DraftIssue] {
        var issues: [DraftIssue] = []
        if draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyMessage)
        }
        if draft.files.isEmpty {
            issues.append(.noFiles)
        }
        let unchanged = draft.files.filter { !changed.contains($0) }
        if !unchanged.isEmpty {
            issues.append(.unchanged(unchanged))
        }
        return issues
    }

    // MARK: - Editing

    @discardableResult
    public mutating func addDraft(message: String = "", files: [String] = [], source: DraftSource = .manual) -> UUID {
        let moving = Set(files)
        for index in drafts.indices where drafts[index].files.contains(where: moving.contains) {
            drafts[index].files.removeAll(where: moving.contains)
            drafts[index].isEdited = true
        }
        let draft = CommitDraft(message: message, files: files, source: source, isEdited: source == .manual)
        drafts.append(draft)
        return draft.id
    }

    /// Removes a draft; its files go back to Commit 1 if staged, else to Unstaged.
    public mutating func removeDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    public mutating func removeDrafts(ids: Set<UUID>) {
        drafts.removeAll { ids.contains($0.id) }
    }

    public mutating func moveDraft(id: UUID, by offset: Int) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard drafts.indices.contains(target) else { return }
        drafts.swapAt(index, target)
    }

    public mutating func setMessage(_ message: String, for id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }), drafts[index].message != message else { return }
        drafts[index].message = message
        drafts[index].isEdited = true
    }

    /// Moves `paths` to `target`, taking them from whichever drafts hold them.
    /// Returns the id of the draft that received them, if any.
    @discardableResult
    public mutating func move(_ paths: [String], to target: DraftMoveTarget) -> UUID? {
        guard !paths.isEmpty else { return nil }
        let moving = Set(paths)
        if case .draft(let id) = target, draft(id: id) == nil {
            return nil
        }
        for index in drafts.indices where drafts[index].files.contains(where: moving.contains) {
            drafts[index].files.removeAll(where: moving.contains)
            drafts[index].isEdited = true
        }
        switch target {
        case .unassigned:
            return nil
        case .newDraft:
            return addDraft(files: paths)
        case .draft(let id):
            guard let index = drafts.firstIndex(where: { $0.id == id }) else { return nil }
            drafts[index].files.append(contentsOf: paths.filter { !drafts[index].files.contains($0) })
            drafts[index].isEdited = true
            return id
        }
    }

    /// Replaces every draft `source` sent earlier with `replacements`, at the
    /// position of the first old draft, or at the end when it had none.
    public mutating func replaceDrafts(from source: DraftSource, with replacements: [CommitDraft]) {
        let key = source.groupKey
        let position = drafts.firstIndex { $0.source.groupKey == key } ?? drafts.endIndex
        let before = drafts[..<position].filter { $0.source.groupKey != key }
        let after = drafts[position...].filter { $0.source.groupKey != key }
        drafts = before + replacements + after
    }

    /// Folds `id` into its neighbour (`next` or previous): the files join the
    /// neighbour and both messages stay, one after the other, for you to edit.
    /// Returns the surviving draft's id.
    @discardableResult
    public mutating func merge(_ id: UUID, withNext next: Bool) -> UUID? {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return nil }
        let other = next ? index + 1 : index - 1
        guard drafts.indices.contains(other) else { return nil }
        let (first, second) = next ? (index, other) : (other, index)
        var merged = drafts[first]
        merged.files += drafts[second].files.filter { !merged.files.contains($0) }
        let messages = [drafts[first].message, drafts[second].message]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        merged.message = messages.joined(separator: "\n\n")
        merged.isEdited = true
        drafts[first] = merged
        drafts.remove(at: second)
        return merged.id
    }

    /// What an AI revision changed besides the drafts themselves.
    public struct RevisionOutcome: Equatable, Sendable {
        /// Paths the AI named that the revised drafts never held.
        public var dropped: [String] = []
        /// Paths the revised drafts held that the AI left out; back in Commit 1 or Unstaged.
        public var leftOut: [String] = []
        /// Ids of the new drafts, in plan order.
        public var created: [UUID] = []
    }

    /// Swaps the drafts in `ids` for revised commits at the place of the first
    /// one. Only files those drafts held can move. Changes nothing when the
    /// revision has no usable commit.
    @discardableResult
    public mutating func applyRevision(_ groups: [(files: [String], message: String)], replacing ids: [UUID]) -> RevisionOutcome {
        let chosen = Set(ids)
        let replaced = drafts.filter { chosen.contains($0.id) }
        guard let position = drafts.firstIndex(where: { chosen.contains($0.id) }) else { return RevisionOutcome() }
        let scope = replaced.flatMap(\.files)
        let allowed = Set(scope)
        let sources = Set(replaced.map(\.source.groupKey))
        let source = sources.count == 1 ? replaced[0].source : .ai

        var outcome = RevisionOutcome()
        var used = Set<String>()
        var revised: [CommitDraft] = []
        for group in groups {
            var files: [String] = []
            for path in group.files {
                if allowed.contains(path), used.insert(path).inserted {
                    files.append(path)
                } else if !allowed.contains(path), !outcome.dropped.contains(path) {
                    outcome.dropped.append(path)
                }
            }
            let message = group.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !files.isEmpty else { continue }
            revised.append(CommitDraft(message: message, files: files, source: source, isEdited: true))
        }
        guard !revised.isEmpty else { return outcome }
        outcome.leftOut = scope.filter { !used.contains($0) }
        outcome.created = revised.map(\.id)
        drafts.removeAll { chosen.contains($0.id) }
        drafts.insert(contentsOf: revised, at: min(position, drafts.count))
        return outcome
    }

    public func drafts(from source: DraftSource) -> [CommitDraft] {
        drafts.filter { $0.source.groupKey == source.groupKey }
    }

    /// Files the git layer should commit, in plan order.
    public func fileCommitPlan(for ids: [UUID]) -> FileCommitPlan {
        let chosen = Set(ids)
        return FileCommitPlan(commits: drafts.filter { chosen.contains($0.id) }.map {
            FileCommitPlan.Commit(files: $0.files, message: $0.message.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }
}
