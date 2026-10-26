import AppKit
import Foundation
import GitKit

/// The words a change touched. Removed lines are paired with the added
/// lines that replace them, in order, and each pair's words are compared,
/// so a renamed variable stands out from the rest of its line.
enum WordDiff {
    static let maximumLineLength = 4096
    static let maximumComparisonWork = 160_000
    /// Shared by all line pairs, not renewed for every line in a large diff.
    static let documentComparisonWork = 1_000_000

    /// Ranges, in UTF-16 offsets of each string, of the words only `old`
    /// has and of the words only `new` has. Nil when comparison exceeds its
    /// budget or the lines have too little in common to compare meaningfully.
    static func changes(old: String, new: String) -> (old: [NSRange], new: [NSRange])? {
        var remainingWork = maximumComparisonWork
        return changes(old: old, new: new, remainingWork: &remainingWork)
    }

    static func changes(old: String, new: String, remainingWork: inout Int) -> (old: [NSRange], new: [NSRange])? {
        guard !old.isEmpty, !new.isEmpty,
              old.utf16.count <= maximumLineLength, new.utf16.count <= maximumLineLength else { return nil }
        if old == new {
            return ([], [])
        }
        guard remainingWork > 0 else { return nil }
        let a = tokens(old)
        let b = tokens(new)
        let work = a.count * b.count
        guard !a.isEmpty, !b.isEmpty, work <= maximumComparisonWork, work <= remainingWork else { return nil }
        remainingWork -= work

        // Longest common subsequence of tokens, by length table.
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i].text == b[j].text ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var keptA = Set<Int>()
        var keptB = Set<Int>()
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i].text == b[j].text {
                keptA.insert(i)
                keptB.insert(j)
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }

        // Lines that share almost nothing are rewritten, not edited.
        let meaningfulA = a.indices.filter { !a[$0].isSpace }
        let meaningfulB = b.indices.filter { !b[$0].isSpace }
        let common = meaningfulA.filter(keptA.contains).count
        guard common * 4 >= max(meaningfulA.count, meaningfulB.count) else { return nil }

        return (merge(a, changed: a.indices.filter { !keptA.contains($0) }), merge(b, changed: b.indices.filter { !keptB.contains($0) }))
    }

    struct Token {
        let text: Substring
        let range: NSRange
        var isSpace: Bool {
            text.allSatisfy(\.isWhitespace)
        }
    }

    /// Words, runs of spaces, and single punctuation marks.
    static func tokens(_ line: String) -> [Token] {
        var result: [Token] = []
        var index = line.startIndex
        var offset = 0
        while index < line.endIndex {
            let character = line[index]
            var end = line.index(after: index)
            if character.isLetter || character.isNumber || character == "_" {
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" {
                    end = line.index(after: end)
                }
            } else if character.isWhitespace {
                while end < line.endIndex, line[end].isWhitespace {
                    end = line.index(after: end)
                }
            }
            let text = line[index ..< end]
            let length = text.utf16.count
            result.append(Token(text: text, range: NSRange(location: offset, length: length)))
            offset += length
            index = end
        }
        return result
    }

    /// Joins neighbouring changed tokens, and the spaces between them, into
    /// one range each, so a changed phrase reads as one highlight. Spaces
    /// never start or end one.
    private static func merge(_ tokens: [Token], changed: [Int]) -> [NSRange] {
        let changedSet = Set(changed)
        var ranges: [NSRange] = []
        var current: NSRange?
        for (index, token) in tokens.enumerated() where !token.isSpace {
            if changedSet.contains(index) {
                if let open = current {
                    current = NSRange(location: open.location, length: NSMaxRange(token.range) - open.location)
                } else {
                    current = token.range
                }
            } else if let open = current {
                ranges.append(open)
                current = nil
            }
        }
        if let open = current {
            ranges.append(open)
        }
        return ranges
    }
}

extension DiffDocument {
    /// Removed lines paired with the added lines that follow them in a
    /// unified diff, as row indexes.
    func replacedLinePairs() -> [(removed: Int, added: Int)] {
        var pairs: [(Int, Int)] = []
        var removed: [Int] = []
        var added: [Int] = []
        func flush() {
            for index in 0 ..< min(removed.count, added.count) {
                pairs.append((removed[index], added[index]))
            }
            removed = []
            added = []
        }
        for (index, row) in rows.enumerated() {
            switch row.kind {
            case .deletion:
                if !added.isEmpty {
                    flush()
                }
                removed.append(index)
            case .addition:
                added.append(index)
            default:
                flush()
            }
        }
        flush()
        return pairs
    }

    /// The text of row `index` without its "+ " marker and line break.
    func lineText(ofRow index: Int) -> String {
        let range = rows[index].range
        let ns = text as NSString
        guard range.length > 2 else { return "" }
        var line = ns.substring(with: NSRange(location: range.location + 2, length: range.length - 2))
        if line.hasSuffix("\n") {
            line.removeLast()
        }
        return line
    }
}

/// A light syntax colouring for the languages people review most here. It
/// works line by line, so it needs no grammar files, and it keeps track of
/// block comments across the lines of a hunk.
struct SyntaxHighlighter: Sendable {
    static let maximumLineLength = 4096
    static let maximumDocumentLength = 1_000_000

    enum Kind: Sendable {
        case keyword
        case string
        case comment
        case number
        case type
        case key
        case variable
        case heading
    }

    struct Rule: @unchecked Sendable {
        let expression: NSRegularExpression
        let kind: Kind
        /// Color only this capture group.
        var group = 0
    }

    let name: String
    let rules: [Rule]
    /// Block comment delimiters, when the language has them.
    let blockComment: (open: String, close: String)?

    /// The highlighter for a path's extension or name, if Avi knows the language.
    static func forPath(_ path: String) -> SyntaxHighlighter? {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if name == "dockerfile" || name.hasPrefix("dockerfile.") || ext == "dockerfile" || name == "containerfile" {
            return languages["dockerfile"]
        }
        if name == "makefile" || ext == "mk" {
            return languages["shell"]
        }
        switch ext {
        case "swift": return languages["swift"]
        case "go": return languages["go"]
        case "py", "pyi": return languages["python"]
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts": return languages["javascript"]
        case "json", "jsonc", "json5": return languages["json"]
        case "yaml", "yml": return languages["yaml"]
        case "toml": return languages["toml"]
        case "tf", "tfvars", "hcl", "nomad": return languages["hcl"]
        case "sh", "bash", "zsh", "fish", "envrc", "env": return languages["shell"]
        case "md", "markdown", "mdx": return languages["markdown"]
        case "rs": return languages["rust"]
        case "c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "kts", "cs", "scala", "groovy", "gradle": return languages["clike"]
        case "rb", "rake", "gemspec": return languages["ruby"]
        case "sql": return languages["sql"]
        case "xml", "html", "htm", "plist", "svg", "xib", "storyboard": return languages["markup"]
        case "css", "scss", "sass", "less": return languages["css"]
        case "ini", "cfg", "conf", "properties", "editorconfig", "gitconfig": return languages["ini"]
        default:
            if name.hasPrefix(".") || name == "gitignore" {
                return languages["ini"]
            }
            return nil
        }
    }

    /// Colored ranges, in UTF-16 offsets of `line`. `inBlockComment` carries
    /// an open block comment from one line to the next.
    func highlight(_ line: String, inBlockComment: inout Bool) -> [(range: NSRange, kind: Kind)] {
        // Minified/generated lines can make repeated regex searches expensive.
        guard line.utf16.count <= Self.maximumLineLength else {
            inBlockComment = false
            return []
        }
        let ns = line as NSString
        var result: [(NSRange, Kind)] = []
        var covered = IndexSet()
        var start = 0

        if let block = blockComment, inBlockComment {
            let close = ns.range(of: block.close)
            if close.location == NSNotFound {
                return [(NSRange(location: 0, length: ns.length), .comment)]
            }
            let end = NSMaxRange(close)
            result.append((NSRange(location: 0, length: end), .comment))
            covered.insert(integersIn: 0 ..< end)
            inBlockComment = false
            start = end
        }

        if let block = blockComment {
            var searchFrom = start
            while searchFrom < ns.length {
                let open = ns.range(of: block.open, range: NSRange(location: searchFrom, length: ns.length - searchFrom))
                guard open.location != NSNotFound, !covered.contains(open.location) else { break }
                // An opener inside a string does not start a comment.
                if Self.isInsideString(ns, at: open.location) {
                    searchFrom = NSMaxRange(open)
                    continue
                }
                let rest = NSMaxRange(open)
                let close = ns.range(of: block.close, range: NSRange(location: rest, length: ns.length - rest))
                let end = close.location == NSNotFound ? ns.length : NSMaxRange(close)
                result.append((NSRange(location: open.location, length: end - open.location), .comment))
                covered.insert(integersIn: open.location ..< end)
                if close.location == NSNotFound {
                    inBlockComment = true
                    break
                }
                searchFrom = end
            }
        }

        for rule in rules {
            var from = 0
            while from < ns.length,
                  let match = rule.expression.firstMatch(
                      in: line,
                      options: [.withTransparentBounds, .withoutAnchoringBounds],
                      range: NSRange(location: from, length: ns.length - from)
                  ) {
                let range = rule.group == 0 ? match.range : match.range(at: rule.group)
                from = max(NSMaxRange(match.range), match.range.location + 1)
                guard range.location != NSNotFound, range.length > 0 else { continue }
                // A comment marker inside a string, such as the slashes of a
                // URL, starts no comment; one may still follow the string.
                if rule.kind == .comment, Self.isInsideString(ns, at: range.location) {
                    from = range.location + 1
                    continue
                }
                let span = range.location ..< NSMaxRange(range)
                guard !covered.intersects(integersIn: span) else { continue }
                covered.insert(integersIn: span)
                result.append((range, rule.kind))
            }
        }
        return result
    }

    /// Whether `offset` sits inside a double- or single-quoted string, by
    /// counting unescaped quotes before it.
    private static func isInsideString(_ line: NSString, at offset: Int) -> Bool {
        var inDouble = false
        var inSingle = false
        var escaped = false
        for index in 0 ..< offset {
            let character = line.character(at: index)
            if escaped {
                escaped = false
            } else if character == 92 { // backslash
                escaped = true
            } else if character == 34, !inSingle {
                inDouble.toggle()
            } else if character == 39, !inDouble {
                inSingle.toggle()
            }
        }
        return inDouble || inSingle
    }

    // MARK: Colors

    static func color(for kind: Kind) -> NSColor {
        switch kind {
        case .keyword: return dynamic(light: 0xAD3DA4, dark: 0xFC5FA3)
        case .string: return dynamic(light: 0xC41A16, dark: 0xFC6A5D)
        case .comment: return dynamic(light: 0x6E7B88, dark: 0x7F8C98)
        case .number: return dynamic(light: 0x1C00CF, dark: 0xD0BF69)
        case .type: return dynamic(light: 0x0E6A86, dark: 0x5DD8FF)
        case .key: return dynamic(light: 0x326D74, dark: 0x67B7A4)
        case .variable: return dynamic(light: 0x2F6F9F, dark: 0x41A1C0)
        case .heading: return dynamic(light: 0xAD3DA4, dark: 0xFC5FA3)
        }
    }

    /// A color for light and dark appearances, as 0xRRGGBB.
    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    // MARK: Languages

    private static func rule(_ pattern: String, _ kind: Kind, group: Int = 0, caseInsensitive: Bool = false) -> Rule {
        // The patterns are constants written here; one that does not compile is a bug.
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive, .anchorsMatchLines] : [.anchorsMatchLines]
        return Rule(expression: try! NSRegularExpression(pattern: pattern, options: options), kind: kind, group: group)
    }

    private static func keywords(_ words: String) -> String {
        "\\b(?:" + words.split(separator: " ").joined(separator: "|") + ")\\b"
    }

    private static let doubleString = #""(?:[^"\\]|\\.)*"?"#
    private static let singleString = #"'(?:[^'\\]|\\.)*'?"#
    private static let backtickString = #"`(?:[^`\\]|\\.)*`?"#
    private static let number = #"\b(?:0x[0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#
    private static let capitalized = #"\b[A-Z][A-Za-z0-9_]*\b"#

    private static let languages: [String: SyntaxHighlighter] = [
        "swift": SyntaxHighlighter(name: "Swift", rules: [
            rule("//.*$", .comment),
            rule(#""""(?:.|\n)*?"""|"(?:[^"\\]|\\.)*"?"#, .string),
            rule(#"@\w+"#, .keyword),
            rule(keywords("let var func if else guard return struct class enum protocol extension import case switch for in while repeat break continue default where throws throw try await async self Self init deinit nil true false static private fileprivate internal public open override mutating nonmutating some any inout as is defer do catch typealias associatedtype subscript lazy weak unowned final convenience required get set willSet didSet actor nonisolated isolated macro package consuming borrowing"), .keyword),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: ("/*", "*/")),
        "go": SyntaxHighlighter(name: "Go", rules: [
            rule("//.*$", .comment),
            rule(doubleString, .string),
            rule(backtickString, .string),
            rule(#"'(?:[^'\\]|\\.)'"#, .string),
            rule(keywords("package import func var const type struct interface map chan go defer return if else for range switch case default break continue select fallthrough goto nil true false iota"), .keyword),
            rule(keywords("string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr byte rune bool float32 float64 complex64 complex128 error any comparable"), .type),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: ("/*", "*/")),
        "python": SyntaxHighlighter(name: "Python", rules: [
            rule("#.*$", .comment),
            rule(#"[rbfuRBFU]{0,2}(?:"""|''')"#, .string),
            rule(#"[rbfuRBFU]{0,2}"(?:[^"\\]|\\.)*"?"#, .string),
            rule(#"[rbfuRBFU]{0,2}'(?:[^'\\]|\\.)*'?"#, .string),
            rule(#"@\w+(?:\.\w+)*"#, .keyword),
            rule(keywords("def class return if elif else for while in not and or is None True False import from as with try except finally raise yield lambda pass break continue global nonlocal async await self cls match case del assert"), .keyword),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: nil),
        "javascript": SyntaxHighlighter(name: "JavaScript", rules: [
            rule("//.*$", .comment),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(backtickString, .string),
            rule(keywords("const let var function return if else for while do switch case default break continue new this super class extends import export from as async await try catch finally throw typeof instanceof in of null undefined true false interface type enum implements public private protected readonly static yield void declare namespace abstract keyof satisfies get set"), .keyword),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: ("/*", "*/")),
        "json": SyntaxHighlighter(name: "JSON", rules: [
            rule(#"("(?:[^"\\]|\\.)*")\s*:"#, .key, group: 1),
            rule(doubleString, .string),
            rule(keywords("true false null"), .keyword),
            rule(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number)
        ], blockComment: nil),
        "yaml": SyntaxHighlighter(name: "YAML", rules: [
            rule(#"(?:^|\s)(#.*)$"#, .comment, group: 1),
            rule(#"\{\{.*?\}\}"#, .variable),
            rule(#"^\s*(?:-\s+)?([\w./${}-]+)(?=\s*:(?:\s|$))"#, .key, group: 1),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(#"^\s*---\s*$|^\s*\.\.\.\s*$"#, .keyword),
            rule(#"[&*][\w-]+"#, .variable),
            rule(keywords("true false yes no on off null True False Yes No On Off Null"), .keyword),
            rule(number, .number)
        ], blockComment: nil),
        "toml": SyntaxHighlighter(name: "TOML", rules: [
            rule(#"(?:^|\s)(#.*)$"#, .comment, group: 1),
            rule(#"^\s*\[\[?[^\]]+\]\]?"#, .heading),
            rule(#"^\s*([\w."-]+)\s*="#, .key, group: 1),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(keywords("true false"), .keyword),
            rule(number, .number)
        ], blockComment: nil),
        "hcl": SyntaxHighlighter(name: "Terraform", rules: [
            rule(#"(?:#|//).*$"#, .comment),
            rule(#"\$\{[^}]*\}"#, .variable),
            rule(doubleString, .string),
            rule(#"^\s*(resource|data|module|variable|output|locals|provider|terraform|backend|required_providers|dynamic|moved|import|check|removed)\b"#, .keyword, group: 1),
            rule(#"^\s*([\w-]+)\s*="#, .key, group: 1),
            rule(keywords("true false null for in if each count var local module data path self"), .keyword),
            rule(number, .number)
        ], blockComment: ("/*", "*/")),
        "shell": SyntaxHighlighter(name: "Shell", rules: [
            rule(#"(?:^|\s)(#.*)$"#, .comment, group: 1),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(#"\$\{[^}]*\}|\$\(|\$[A-Za-z_][A-Za-z0-9_]*|\$[0-9@#?$!*-]"#, .variable),
            rule(keywords("if then else elif fi for in do done case esac while until function return export local readonly declare set unset shift exit source alias select time trap"), .keyword),
            rule(number, .number)
        ], blockComment: nil),
        "dockerfile": SyntaxHighlighter(name: "Dockerfile", rules: [
            rule(#"^\s*#.*$"#, .comment),
            rule(#"^\s*(FROM|RUN|CMD|COPY|ADD|ENV|ARG|WORKDIR|EXPOSE|ENTRYPOINT|USER|LABEL|VOLUME|HEALTHCHECK|SHELL|ONBUILD|STOPSIGNAL|MAINTAINER)\b"#, .keyword, group: 1, caseInsensitive: true),
            rule(#"\b(AS)\b"#, .keyword, group: 1, caseInsensitive: true),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(#"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*"#, .variable)
        ], blockComment: nil),
        "markdown": SyntaxHighlighter(name: "Markdown", rules: [
            rule(#"^\s{0,3}#{1,6}\s.*$"#, .heading),
            rule(#"`[^`]+`"#, .string),
            rule(#"\[[^\]]+\]\([^)]+\)"#, .variable),
            rule(#"^\s*(?:[-*+]|\d+\.)\s"#, .keyword)
        ], blockComment: ("<!--", "-->")),
        "rust": SyntaxHighlighter(name: "Rust", rules: [
            rule("//.*$", .comment),
            rule(doubleString, .string),
            rule(#"#!?\[[^\]]*\]"#, .keyword),
            rule(keywords("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"), .keyword),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: ("/*", "*/")),
        "clike": SyntaxHighlighter(name: "C", rules: [
            rule("//.*$", .comment),
            rule(doubleString, .string),
            rule(#"'(?:[^'\\]|\\.)'"#, .string),
            rule(#"^\s*#\s*\w+"#, .keyword),
            rule(#"@\w+"#, .keyword),
            rule(keywords("auto break case char const continue default do double else enum extern float for goto if inline int long register return short signed sizeof static struct switch typedef union unsigned void volatile while class public private protected virtual override final new delete this throw try catch namespace using template typename bool true false nullptr null package import extends implements interface abstract fun val var object companion data sealed when is in out suspend"), .keyword),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: ("/*", "*/")),
        "ruby": SyntaxHighlighter(name: "Ruby", rules: [
            rule(#"(?:^|\s)(#.*)$"#, .comment, group: 1),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(#":[A-Za-z_]\w*"#, .variable),
            rule(#"@{1,2}\w+"#, .variable),
            rule(keywords("def end class module if elsif else unless while until for in do return yield begin rescue ensure raise self nil true false and or not then case when require require_relative attr_reader attr_accessor private protected public"), .keyword),
            rule(number, .number),
            rule(capitalized, .type)
        ], blockComment: nil),
        "sql": SyntaxHighlighter(name: "SQL", rules: [
            rule("--.*$", .comment),
            rule(singleString, .string),
            rule(keywords("select from where and or not insert into values update set delete create table alter drop index view join left right inner outer full on as group by order having limit offset union all distinct case when then else end null is in exists between like primary key foreign references default constraint begin commit rollback with returning"), .keyword, caseInsensitive: true),
            rule(number, .number)
        ], blockComment: ("/*", "*/")),
        "markup": SyntaxHighlighter(name: "XML", rules: [
            rule(#"</?[\w:.-]+"#, .keyword),
            rule(#"/?>"#, .keyword),
            rule(#"\s([\w:.-]+)(?==)"#, .key, group: 1),
            rule(doubleString, .string),
            rule(singleString, .string)
        ], blockComment: ("<!--", "-->")),
        "css": SyntaxHighlighter(name: "CSS", rules: [
            rule("//.*$", .comment),
            rule(doubleString, .string),
            rule(singleString, .string),
            rule(#"([\w-]+)(?=\s*:[^:])"#, .key, group: 1),
            rule(#"[.#][\w-]+"#, .type),
            rule(#"@[\w-]+"#, .keyword),
            rule(#"\$[\w-]+|--[\w-]+"#, .variable),
            rule(#"-?\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg)?\b|#[0-9a-fA-F]{3,8}\b"#, .number)
        ], blockComment: ("/*", "*/")),
        "ini": SyntaxHighlighter(name: "Config", rules: [
            rule(#"^\s*[#;].*$"#, .comment),
            rule(#"^\s*\[[^\]]+\]"#, .heading),
            rule(#"^\s*([\w.-]+)\s*[=:]"#, .key, group: 1),
            rule(doubleString, .string)
        ], blockComment: nil)
    ]
}
