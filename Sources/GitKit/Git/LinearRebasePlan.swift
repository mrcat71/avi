import Foundation

/// Builds an explicit replay list without accepting subjects or revision syntax
/// as todo instructions. Merge histories require a different, merge-aware plan.
struct LinearRebasePlan {
    let todo: String

    /// Refuse to replace Git's live todo if HEAD moved or Git would replay a
    /// different sequence. This closes the gap between planning and starting.
    static let sequenceEditorScript = """
    #!/bin/sh
    set -eu
    /usr/bin/awk '
      NR == FNR { expected[++count] = $2; next }
      /^[[:space:]]*#/ || NF == 0 { next }
      { if ($1 != "pick" || $2 != expected[++seen]) bad = 1 }
      END { exit (bad || seen != count) }
    ' "$1" "$2" || {
      printf '%s\\n' 'Avi: replay sequence changed; refusing to replace the rebase plan.' >&2
      exit 1
    }
    /bin/cp "$1" "$2"
    """

    init(parentListing: String, oldest: String, target: String, verb: String) throws {
        guard ["edit", "reword"].contains(verb), Self.isOID(oldest), Self.isOID(target) else {
            throw GitError.invalidInput("Invalid rebase target or action.")
        }
        let commits = parentListing.split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
        guard commits.first?.first == oldest, commits.contains(where: { $0.first == target }) else {
            throw GitError.invalidInput("The selected commits are not in the replay range ending at HEAD.")
        }
        var seen = Set<String>()
        var previous: String?
        var lines: [String] = []
        for commit in commits {
            guard commit.count == 2, commit.allSatisfy(Self.isOID),
                  seen.insert(commit[0]).inserted,
                  previous == nil || commit[1] == previous else {
                throw GitError.invalidInput("Automatic rewriting currently requires a linear history without merge commits.")
            }
            let oid = commit[0]
            lines.append("\(oid == target ? verb : "pick") \(oid)")
            previous = oid
        }
        todo = lines.joined(separator: "\n") + "\n"
    }

    static func isOID(_ value: String) -> Bool {
        (value.utf8.count == 40 || value.utf8.count == 64)
            && value.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
    }
}
