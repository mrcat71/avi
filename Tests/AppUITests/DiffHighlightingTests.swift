@testable import AppUI
import Foundation
@testable import GitKit
import Testing

struct WordDiffTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let old: String
        let new: String
        /// The changed words of each side; nil when the lines are not compared.
        let expected: (old: [String], new: [String])?

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(name: "a renamed variable", old: "let count = items.count", new: "let total = items.count", expected: (["count"], ["total"])),
        Case(name: "neighbouring words read as one change", old: "fetch the old list now", new: "fetch a new set now", expected: (["the old list"], ["a new set"])),
        Case(name: "a word added", old: "return value", new: "return try value", expected: ([], ["try"])),
        Case(name: "punctuation is a word of its own", old: "call(a, b)", new: "call(a; b)", expected: ([","], [";"])),
        Case(name: "the same line changes nothing", old: "same line", new: "same line", expected: ([], [])),
        Case(name: "lines with little in common are not compared", old: "import Foundation", new: "struct Ledger { var rows: [Row] }", expected: nil),
        Case(name: "an empty line is not compared", old: "", new: "something", expected: nil)
    ]

    @Test(arguments: cases)
    func changes(_ testCase: Case) throws {
        let result = WordDiff.changes(old: testCase.old, new: testCase.new)
        guard let expected = testCase.expected else {
            #expect(result == nil)
            return
        }
        let words = try #require(result)
        #expect(words.old.map { (testCase.old as NSString).substring(with: $0) } == expected.old)
        #expect(words.new.map { (testCase.new as NSString).substring(with: $0) } == expected.new)
    }

    @Test func rangesCountUTF16() throws {
        let old = "名前 = \"Zoë 👋\""
        let new = "名前 = \"Zoë 🎉\""
        let words = try #require(WordDiff.changes(old: old, new: new))
        #expect(words.old.map { (old as NSString).substring(with: $0) } == ["👋"])
        #expect(words.new.map { (new as NSString).substring(with: $0) } == ["🎉"])
    }

    /// Rows: 0 header, 1 context, 2 -a, 3 -b, 4 +A, 5 context, 6 +only,
    /// 7 -c, 8 +C, 9 +D.
    @Test func removedLinesPairWithTheAddedLinesAfterThem() {
        let diff = FileDiff(hunks: [
            DiffHunk(header: "@@ -1,5 +1,6 @@", oldStart: 1, oldCount: 5, newStart: 1, newCount: 6, lines: [
                DiffLine(id: 0, kind: .context, text: "keep", oldLineNumber: 1, newLineNumber: 1),
                DiffLine(id: 1, kind: .deletion, text: "a", oldLineNumber: 2, newLineNumber: nil),
                DiffLine(id: 2, kind: .deletion, text: "b", oldLineNumber: 3, newLineNumber: nil),
                DiffLine(id: 3, kind: .addition, text: "A", oldLineNumber: nil, newLineNumber: 2),
                DiffLine(id: 4, kind: .context, text: "keep", oldLineNumber: 4, newLineNumber: 3),
                DiffLine(id: 5, kind: .addition, text: "only", oldLineNumber: nil, newLineNumber: 4),
                DiffLine(id: 6, kind: .deletion, text: "c", oldLineNumber: 5, newLineNumber: nil),
                DiffLine(id: 7, kind: .addition, text: "C", oldLineNumber: nil, newLineNumber: 5),
                DiffLine(id: 8, kind: .addition, text: "D", oldLineNumber: nil, newLineNumber: 6)
            ])
        ], isBinary: false)
        let document = DiffDocument(diff)
        let pairs = document.replacedLinePairs()
        #expect(pairs.map(\.removed) == [2, 7])
        #expect(pairs.map(\.added) == [4, 8])
        #expect(document.lineText(ofRow: 2) == "a")
        #expect(document.lineText(ofRow: 8) == "C")
    }
}

struct SyntaxHighlighterTests {
    @Test(arguments: [
        ("Sources/App.swift", "Swift"),
        ("cmd/main.go", "Go"),
        ("environments/k8s-infra-ah-ams1/main.tf", "Terraform"),
        ("prod.tfvars", "Terraform"),
        ("charts/web/values.yaml", "YAML"),
        ("Dockerfile", "Dockerfile"),
        ("build/Dockerfile.release", "Dockerfile"),
        ("Makefile", "Shell"),
        ("scripts/build.sh", "Shell"),
        (".gitignore", "Config"),
        ("README.md", "Markdown"),
        ("web/App.tsx", "JavaScript")
    ])
    func languageFromThePath(path: String, language: String) {
        #expect(SyntaxHighlighter.forPath(path)?.name == language)
    }

    @Test func unknownFilesStayPlain() {
        #expect(SyntaxHighlighter.forPath("photo.png") == nil)
        #expect(SyntaxHighlighter.forPath("LICENSE") == nil)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let path: String
        let line: String
        /// Each colored piece of the line and its kind, in line order.
        let expected: [(String, SyntaxHighlighter.Kind)]

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(name: "Swift keywords, strings and numbers", path: "a.swift", line: #"let name = "avi" + 42"#,
             expected: [("let", .keyword), (#""avi""#, .string), ("42", .number)]),
        Case(name: "a line comment", path: "a.swift", line: "x() // let it be", expected: [("// let it be", .comment)]),
        Case(name: "slashes in a string start no comment", path: "a.swift", line: #"load("https://github.com") // docs"#,
             expected: [(#""https://github.com""#, .string), ("// docs", .comment)]),
        Case(name: "a hash in a YAML string starts no comment", path: "a.yaml", line: #"image: "web:#1" # pinned"#,
             expected: [("image", .key), (#""web:#1""#, .string), ("# pinned", .comment)]),
        Case(name: "Terraform blocks and keys", path: "main.tf", line: #"resource "aws_s3_bucket" "logs" {"#,
             expected: [("resource", .keyword), (#""aws_s3_bucket""#, .string), (#""logs""#, .string)]),
        Case(name: "shell variables", path: "a.sh", line: #"echo "$HOME" ${PATH}"#,
             expected: [(#""$HOME""#, .string), ("${PATH}", .variable)])
    ]

    @Test(arguments: cases)
    func highlight(_ testCase: Case) throws {
        let highlighter = try #require(SyntaxHighlighter.forPath(testCase.path))
        var inBlockComment = false
        let pieces = highlighter.highlight(testCase.line, inBlockComment: &inBlockComment)
            .sorted { $0.range.location < $1.range.location }
            .map { ((testCase.line as NSString).substring(with: $0.range), $0.kind) }
        #expect(pieces.map(\.0) == testCase.expected.map(\.0))
        #expect(pieces.map(\.1) == testCase.expected.map(\.1))
    }

    @Test func aBlockCommentCarriesAcrossLines() throws {
        let swift = try #require(SyntaxHighlighter.forPath("a.swift"))
        var inBlockComment = false
        let opening = swift.highlight("let x = 1 /* starts", inBlockComment: &inBlockComment)
        #expect(inBlockComment)
        #expect(opening.contains { $0.kind == .comment && $0.range == NSRange(location: 10, length: 9) })

        let middle = swift.highlight("let inside = true", inBlockComment: &inBlockComment)
        #expect(middle.map(\.kind) == [.comment])
        #expect(inBlockComment)

        let closing = swift.highlight("ends */ let y", inBlockComment: &inBlockComment)
        #expect(!inBlockComment)
        #expect(closing.map(\.kind) == [.comment, .keyword])
    }
}
