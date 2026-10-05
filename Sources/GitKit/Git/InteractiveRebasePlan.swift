import Foundation

/// What an interactive rebase does with one commit.
public enum RebaseTodoAction: Sendable, Equatable {
    case pick
    /// Keep the changes and replace the message.
    case reword(String)
    /// Stop after applying the commit so you can amend it, then continue.
    case edit
    /// Fold into the commit above it, keeping both messages.
    case squash
    /// Fold into the commit above it, keeping only that commit's message.
    case fixup
    case drop
}

public struct RebaseTodoItem: Sendable, Equatable, Identifiable {
    public var id: String {
        oid
    }

    public let oid: String
    public var action: RebaseTodoAction

    public init(oid: String, action: RebaseTodoAction = .pick) {
        self.oid = oid
        self.action = action
    }
}

/// A checked interactive rebase: every commit Git will replay, in the order
/// and with the action you chose. Commit IDs only, never subjects or revision
/// syntax, so nothing from a commit message can become a todo instruction.
public struct InteractiveRebasePlan: Sendable, Equatable {
    /// Git's replay order, oldest first, as `rebaseCandidates` listed it.
    public let original: [String]
    public let items: [RebaseTodoItem]

    public init(original: [String], items: [RebaseTodoItem]) throws {
        guard !original.isEmpty else {
            throw GitError.invalidInput("There are no commits to rebase.")
        }
        guard original.allSatisfy(LinearRebasePlan.isOID), Set(original).count == original.count,
              items.count == original.count, Set(items.map(\.oid)) == Set(original)
        else {
            throw GitError.invalidInput("The rebase plan must list every commit exactly once.")
        }
        var keptOne = false
        for item in items {
            switch item.action {
            case .squash, .fixup:
                guard keptOne else {
                    throw GitError.invalidInput("The first commit you keep cannot be squashed or fixed up: there is no commit above it to fold it into.")
                }
            case .reword(let message):
                guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GitError.invalidInput("A reworded commit needs a message.")
                }
                keptOne = true
            case .pick, .edit:
                keptOne = true
            case .drop:
                break
            }
        }
        self.original = original
        self.items = items
    }

    /// The todo Git runs. A reword is a pick followed by a message-only amend
    /// that reads its message from `rebase-merge/avi-messages/<oid>`. The
    /// sequence editor copies the messages there, Git deletes them with the
    /// rest of its rebase state, and the amend still works when you continue
    /// the rebase from a terminal.
    public var todo: String {
        items.map { item in
            switch item.action {
            case .pick: return "pick \(item.oid)"
            case .reword: return "pick \(item.oid)\nexec \(Self.amendCommand(for: item.oid))"
            case .edit: return "edit \(item.oid)"
            case .squash: return "squash \(item.oid)"
            case .fixup: return "fixup \(item.oid)"
            case .drop: return "drop \(item.oid)"
            }
        }
        .joined(separator: "\n") + "\n"
    }

    /// New messages for reworded commits, keyed by commit ID.
    public var messages: [String: String] {
        items.reduce(into: [:]) { result, item in
            if case .reword(let message) = item.action {
                result[item.oid] = message
            }
        }
    }

    /// The commit IDs Git must list, one per line, in its own order.
    var expectedListing: String {
        original.joined(separator: "\n") + "\n"
    }

    static func amendCommand(for oid: String) -> String {
        "git commit --amend --only --allow-empty -F \"$(git rev-parse --path-format=absolute --git-path rebase-merge/avi-messages/\(oid))\""
    }

    /// Run by Git as the sequence editor with four arguments: the expected
    /// commit IDs, the replacement todo, the folder of new messages, and Git's
    /// live todo. It refuses when Git would replay anything else, such as after
    /// HEAD moved, so a stale plan can never drop newer commits.
    static let sequenceEditorScript = """
    #!/bin/sh
    set -eu
    /usr/bin/awk '
      NR == FNR { if (NF) expected[++count] = $1; next }
      /^[[:space:]]*#/ || NF == 0 { next }
      { if ($1 != "pick" || $2 != expected[++seen]) bad = 1 }
      END { exit (bad || seen != count) }
    ' "$1" "$4" || {
      printf '%s\\n' 'Avi: the commits to rebase changed; refusing to start the rebase.' >&2
      exit 1
    }
    if [ -d "$3" ]; then
      /bin/cp -R "$3" "$(dirname "$4")/avi-messages"
    fi
    /bin/cp "$2" "$4"
    """
}
