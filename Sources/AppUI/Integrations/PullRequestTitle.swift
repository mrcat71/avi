import Foundation

/// Turns a branch name into a pull request title. Branch names use hyphens
/// where a title has spaces, but some hyphens belong to the words: ticket
/// keys such as `INFRA-12345`, and names such as the environment
/// `k8s-infra-ah-ams1`. Those keep their hyphens; every other `-` and `_`
/// becomes a space.
///
/// `feature/INFRA-12345-upgrade-k8s-infra-ah-ams1-ingress` becomes
/// `INFRA-12345 upgrade k8s-infra-ah-ams1 ingress` when the repository has a
/// file or folder named `k8s-infra-ah-ams1`, or the name is in the rules.
enum PullRequestTitle {
    struct Rules: Equatable, Sendable {
        /// Ticket projects matched in any case and written in capitals.
        var ticketPrefixes: [String] = []
        /// Literal names, globs where `*` is one word, or `/regex/`.
        var keepHyphenated: [String] = []
        /// Capitalize the first word that is not a ticket key or a kept name.
        var capitalize = false

        init(ticketPrefixes: [String] = [], keepHyphenated: [String] = [], capitalize: Bool = false) {
            self.ticketPrefixes = ticketPrefixes
            self.keepHyphenated = keepHyphenated
            self.capitalize = capitalize
        }

        init(_ config: PullRequestsConfig) {
            self.init(ticketPrefixes: config.ticketPrefixes, keepHyphenated: config.keepHyphenated, capitalize: config.capitalize)
        }
    }

    /// The title for `branch`. `knownNames` are lowercased hyphenated names
    /// that keep their hyphens, such as file and folder names of the repository.
    static func make(branch: String, rules: Rules = Rules(), knownNames: Set<String> = []) -> String {
        let components = branch.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let last = components.last else { return branch }

        let matchers = rules.keepHyphenated.compactMap(Matcher.init)
        // Folders such as feature/ or a user name are dropped, unless the
        // folder is itself a ticket key or a name to keep.
        var kept: [String] = []
        for folder in components.dropLast() {
            let title = Phrase(folder).title(rules: rules, matchers: matchers, knownNames: knownNames, capitalize: false)
            if title.protectsEverything {
                kept.append(title.text)
            }
        }

        let main = Phrase(last).title(rules: rules, matchers: matchers, knownNames: knownNames, capitalize: rules.capitalize)
        let parts = kept.filter { !main.text.localizedCaseInsensitiveContains($0) } + [main.text]
        let result = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return result.isEmpty ? branch : result
    }

    /// Hyphenated file and folder names in `paths`, lowercased and without
    /// extensions, plus `extra` names such as the repository's own.
    static func knownNames(fromPaths paths: [String], extra: [String] = [], limit: Int = 50000) -> Set<String> {
        var names = Set<String>()
        func add(_ raw: Substring) {
            var name = raw.drop { $0 == "." }
            if let dot = name.firstIndex(of: ".") {
                name = name[..<dot]
            }
            guard name.contains(where: { $0 == "-" || $0 == "_" }),
                  name.contains(where: \.isLetter) || name.contains(where: \.isNumber),
                  name.first != "-", name.last != "-" else { return }
            names.insert(name.lowercased())
        }
        for name in extra {
            add(Substring(name))
        }
        for path in paths {
            for component in path.split(separator: "/") {
                add(component)
                if names.count >= limit {
                    return names
                }
            }
        }
        return names
    }

    // MARK: - Words

    /// A run of words with the separators between them, as written in the branch.
    private struct Phrase {
        var words: [String] = []
        /// `separators[i]` sits between `words[i]` and `words[i + 1]`.
        var separators: [String] = []

        init(_ text: String) {
            var word = ""
            var separator = ""
            for character in text {
                if character == "-" || character == "_" {
                    separator.append(character)
                } else {
                    if !separator.isEmpty {
                        if !word.isEmpty {
                            words.append(word)
                            separators.append(separator)
                        }
                        word = ""
                        separator = ""
                    }
                    word.append(character)
                }
            }
            if !word.isEmpty {
                words.append(word)
            }
            // A separator before the first word or after the last has nothing to join.
            if separators.count >= words.count {
                separators = Array(separators.prefix(max(0, words.count - 1)))
            }
        }

        struct Title {
            let text: String
            /// Every word belongs to a ticket key or a kept name.
            let protectsEverything: Bool
        }

        func title(rules: Rules, matchers: [Matcher], knownNames: Set<String>, capitalize: Bool) -> Title {
            guard !words.isEmpty else { return Title(text: "", protectsEverything: false) }
            var words = words
            // span[i] is the index of the protected run word i belongs to.
            var span = [Int?](repeating: nil, count: words.count)
            var spanCount = 0

            func claim(_ range: ClosedRange<Int>) -> Bool {
                guard range.allSatisfy({ span[$0] == nil }) else { return false }
                for index in range {
                    span[index] = spanCount
                }
                spanCount += 1
                return true
            }

            // Ticket keys: an upper-case project and a number, or a listed
            // project in any case.
            let prefixes = Set(rules.ticketPrefixes.map { $0.uppercased() })
            for index in words.indices.dropLast() where separators[index] == "-" && Self.isNumber(words[index + 1]) {
                let project = words[index]
                if Self.isTicketProject(project) {
                    _ = claim(index ... index + 1)
                } else if prefixes.contains(project.uppercased()) {
                    if claim(index ... index + 1) {
                        words[index] = project.uppercased()
                    }
                }
            }

            // Names from the rules, then names found in the repository, the
            // longest first at each position.
            let joined = joinedOffsets()
            for matcher in matchers {
                for range in matcher.wordRanges(in: joined.text, wordBounds: joined.bounds) {
                    _ = claim(range)
                }
            }
            if !knownNames.isEmpty {
                var start = 0
                while start < words.count {
                    var matched = false
                    if span[start] == nil {
                        for end in stride(from: min(words.count - 1, start + 12), to: start, by: -1) {
                            let candidate = text(from: start, to: end).lowercased()
                            if knownNames.contains(candidate), claim(start ... end) {
                                start = end + 1
                                matched = true
                                break
                            }
                        }
                    }
                    if !matched {
                        start += 1
                    }
                }
            }

            var output = ""
            var capitalized = !capitalize
            for index in words.indices {
                var word = words[index]
                if !capitalized, span[index] == nil {
                    word = word.prefix(1).uppercased() + word.dropFirst()
                    capitalized = true
                }
                if index > 0 {
                    let joinsSpan = span[index] != nil && span[index] == span[index - 1]
                    output += joinsSpan ? separators[index - 1] : " "
                }
                output += word
            }
            return Title(text: output, protectsEverything: span.allSatisfy { $0 != nil })
        }

        /// Words `from` through `to` with the separators between them.
        private func text(from start: Int, to end: Int) -> String {
            var result = words[start]
            for index in start ..< end {
                result += separators[index] + words[index + 1]
            }
            return result
        }

        /// The whole phrase, and where each word starts and ends in it.
        private func joinedOffsets() -> (text: String, bounds: [(start: Int, end: Int)]) {
            var text = ""
            var bounds: [(start: Int, end: Int)] = []
            for index in words.indices {
                if index > 0 {
                    text += separators[index - 1]
                }
                let start = text.utf16.count
                text += words[index]
                bounds.append((start, text.utf16.count))
            }
            return (text, bounds)
        }

        private static func isNumber(_ word: String) -> Bool {
            !word.isEmpty && word.allSatisfy(\.isASCII) && word.allSatisfy(\.isNumber)
        }

        /// `INFRA`, `OPS2`: an upper-case letter, then upper-case letters or digits.
        private static func isTicketProject(_ word: String) -> Bool {
            guard word.count >= 2, let first = word.first, first.isASCII, first.isUppercase else { return false }
            return word.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        }
    }

    /// One `keepHyphenated` entry as a case-insensitive expression that must
    /// start and end on word boundaries.
    private struct Matcher {
        let expression: NSRegularExpression

        init?(_ entry: String) {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let pattern: String
            if trimmed.count > 2, trimmed.hasPrefix("/"), trimmed.hasSuffix("/") {
                pattern = String(trimmed.dropFirst().dropLast())
            } else {
                // `*` stands for one word: letters, digits and dots.
                pattern = trimmed.split(separator: "*", omittingEmptySubsequences: false)
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: "[A-Za-z0-9.]+")
            }
            guard let expression = try? NSRegularExpression(pattern: "(?:\(pattern))", options: [.caseInsensitive]) else {
                return nil
            }
            self.expression = expression
        }

        /// Word index ranges this entry covers in `text`. A match that starts
        /// or ends inside a word does not count.
        func wordRanges(in text: String, wordBounds: [(start: Int, end: Int)]) -> [ClosedRange<Int>] {
            let whole = NSRange(location: 0, length: text.utf16.count)
            return expression.matches(in: text, range: whole).compactMap { match in
                let start = match.range.location
                let end = match.range.location + match.range.length
                guard let first = wordBounds.firstIndex(where: { $0.start == start }),
                      let last = wordBounds.firstIndex(where: { $0.end == end }),
                      first < last else { return nil }
                return first ... last
            }
        }
    }
}
