import Foundation

/// Minimal TOML parser + writer covering the subset Avi needs:
/// dotted tables, arrays of tables, strings (double-quoted), integers,
/// doubles, booleans, and arrays of homogeneous values. No inline tables,
/// no multi-line literal strings, no datetime. Comments begin with `#`.
enum MiniTOML {
    // MARK: - Public API

    static func encode(_ root: [String: Any]) -> String {
        var output = ""
        writeTable(name: "", table: root, into: &output)
        return output
    }

    static func parse(_ text: String) throws -> [String: Any] {
        var parser = Parser(text: text)
        return try parser.parseDocument()
    }

    // MARK: - Encoding

    private static func writeTable(name: String, table: [String: Any], into out: inout String) {
        // Sort keys so the file is stable across runs.
        let allKeys = table.keys.sorted()
        let scalarKeys = allKeys.filter { !(table[$0] is [String: Any] || table[$0] is [[String: Any]]) }
        let tableKeys = allKeys.filter { table[$0] is [String: Any] }
        let arrayOfTableKeys = allKeys.filter { table[$0] is [[String: Any]] }

        if !name.isEmpty, !scalarKeys.isEmpty || (tableKeys.isEmpty && arrayOfTableKeys.isEmpty) {
            out += "[\(name)]\n"
        }

        for key in scalarKeys {
            let value = table[key]!
            out += "\(encodeKey(key)) = \(encodeValue(value))\n"
        }

        if !scalarKeys.isEmpty, !tableKeys.isEmpty || !arrayOfTableKeys.isEmpty {
            out += "\n"
        }

        for key in tableKeys {
            let nested = table[key] as! [String: Any]
            let fullName = name.isEmpty ? encodeKey(key) : "\(name).\(encodeKey(key))"
            writeTable(name: fullName, table: nested, into: &out)
            out += "\n"
        }

        for key in arrayOfTableKeys {
            let array = table[key] as! [[String: Any]]
            let fullName = name.isEmpty ? encodeKey(key) : "\(name).\(encodeKey(key))"
            for element in array {
                out += "[[\(fullName)]]\n"
                writeTable(name: "", table: element, into: &out)
                out += "\n"
            }
        }
    }

    private static func encodeKey(_ key: String) -> String {
        let bareCharSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        let isBare = !key.isEmpty && key.unicodeScalars.allSatisfy { bareCharSet.contains($0) }
        if isBare { return key }
        return "\"\(escapeString(key))\""
    }

    private static func encodeValue(_ value: Any) -> String {
        switch value {
        case let s as String:
            return "\"\(escapeString(s))\""
        case let b as Bool:
            return b ? "true" : "false"
        case let i as Int:
            return String(i)
        case let i as Int64:
            return String(i)
        case let d as Double:
            if d.isFinite {
                return d.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(d)).0" : String(d)
            }
            return "0.0"
        case let arr as [Any]:
            return "[" + arr.map(encodeValue).joined(separator: ", ") + "]"
        case is NSNull:
            return "\"\""
        default:
            // For nested dicts at scalar positions we shouldn't get here;
            // fall back to a quoted description.
            return "\"\(escapeString(String(describing: value)))\""
        }
    }

    private static func escapeString(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for char in s {
            switch char {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(char)
            }
        }
        return out
    }

    // MARK: - Parsing

    enum ParseError: Error, CustomStringConvertible {
        case unexpected(String, line: Int)
        var description: String {
            switch self {
            case .unexpected(let msg, let line): return "TOML parse error at line \(line): \(msg)"
            }
        }
    }

    private struct Parser {
        let text: String
        var index: String.Index
        var line: Int = 1

        init(text: String) {
            self.text = text
            index = text.startIndex
        }

        mutating func parseDocument() throws -> [String: Any] {
            var root: [String: Any] = [:]
            // currentPath is the dotted table key we are currently writing scalars into.
            var currentPath: [String] = []
            // If we are in an array-of-tables entry, track which one.
            var currentAOT: (path: [String], index: Int)? = nil

            while index < text.endIndex {
                skipWhitespaceAndComments()
                guard index < text.endIndex else { break }
                let c = text[index]
                if c == "[" {
                    advance()
                    if index < text.endIndex, text[index] == "[" {
                        advance()
                        let path = try parseDottedKey()
                        try expect("]")
                        try expect("]")
                        skipToEndOfLine()
                        // append a new dict under the path
                        var array = (getNested(root: root, path: path) as? [Any]) ?? []
                        array.append([String: Any]())
                        setNested(root: &root, path: path, value: array)
                        currentPath = path
                        currentAOT = (path, array.count - 1)
                    } else {
                        let path = try parseDottedKey()
                        try expect("]")
                        skipToEndOfLine()
                        currentPath = path
                        currentAOT = nil
                        ensureTable(root: &root, path: path)
                    }
                } else if c == "\n" {
                    advance()
                    line += 1
                } else {
                    let key = try parseKey()
                    skipSpaces()
                    try expect("=")
                    skipSpaces()
                    let value = try parseValue()
                    skipToEndOfLine()
                    if let aot = currentAOT {
                        guard var arr = getNested(root: root, path: aot.path) as? [Any], aot.index < arr.count, var dict = arr[aot.index] as? [String: Any] else {
                            throw ParseError.unexpected("invalid AOT state", line: line)
                        }
                        dict[key] = value
                        arr[aot.index] = dict
                        setNested(root: &root, path: aot.path, value: arr)
                    } else {
                        ensureTable(root: &root, path: currentPath)
                        setLeafKey(root: &root, path: currentPath, key: key, value: value)
                    }
                }
            }

            return root
        }

        mutating func advance() {
            if index < text.endIndex {
                index = text.index(after: index)
            }
        }

        mutating func skipSpaces() {
            while index < text.endIndex, let scalar = text[index].unicodeScalars.first, scalar == " " || scalar == "\t" {
                advance()
            }
        }

        mutating func skipWhitespaceAndComments() {
            while index < text.endIndex {
                let c = text[index]
                if c == " " || c == "\t" {
                    advance()
                } else if c == "\n" {
                    line += 1
                    advance()
                } else if c == "\r" {
                    advance()
                } else if c == "#" {
                    while index < text.endIndex, text[index] != "\n" {
                        advance()
                    }
                } else {
                    return
                }
            }
        }

        mutating func skipToEndOfLine() {
            while index < text.endIndex, text[index] != "\n" {
                advance()
            }
            if index < text.endIndex {
                advance()
                line += 1
            }
        }

        mutating func expect(_ ch: Character) throws {
            skipSpaces()
            guard index < text.endIndex, text[index] == ch else {
                throw ParseError.unexpected("expected '\(ch)'", line: line)
            }
            advance()
        }

        mutating func parseKey() throws -> String {
            skipSpaces()
            guard index < text.endIndex else {
                throw ParseError.unexpected("unexpected end of file while reading key", line: line)
            }
            if text[index] == "\"" {
                return try parseQuotedString()
            }
            let start = index
            let bareCharSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
            while index < text.endIndex, let scalar = text[index].unicodeScalars.first, bareCharSet.contains(scalar) {
                advance()
            }
            let key = String(text[start ..< index])
            if key.isEmpty {
                throw ParseError.unexpected("empty key", line: line)
            }
            return key
        }

        mutating func parseDottedKey() throws -> [String] {
            var parts: [String] = []
            while true {
                let part = try parseKey()
                parts.append(part)
                skipSpaces()
                if index < text.endIndex, text[index] == "." {
                    advance()
                    continue
                }
                break
            }
            return parts
        }

        mutating func parseValue() throws -> Any {
            skipSpaces()
            guard index < text.endIndex else {
                throw ParseError.unexpected("expected value", line: line)
            }
            let c = text[index]
            if c == "\"" {
                return try parseQuotedString()
            }
            if c == "[" {
                return try parseArray()
            }
            if c == "t" || c == "f" {
                return try parseBool()
            }
            // number
            return try parseNumber()
        }

        mutating func parseQuotedString() throws -> String {
            try expect("\"")
            var out = ""
            while index < text.endIndex {
                let c = text[index]
                if c == "\"" {
                    advance()
                    return out
                }
                if c == "\\" {
                    advance()
                    guard index < text.endIndex else { break }
                    let next = text[index]
                    switch next {
                    case "n": out += "\n"
                    case "r": out += "\r"
                    case "t": out += "\t"
                    case "\"": out += "\""
                    case "\\": out += "\\"
                    default:
                        out.append(next)
                    }
                    advance()
                } else if c == "\n" {
                    throw ParseError.unexpected("unterminated string", line: line)
                } else {
                    out.append(c)
                    advance()
                }
            }
            throw ParseError.unexpected("unterminated string", line: line)
        }

        mutating func parseBool() throws -> Bool {
            if text[index...].hasPrefix("true") {
                index = text.index(index, offsetBy: 4)
                return true
            }
            if text[index...].hasPrefix("false") {
                index = text.index(index, offsetBy: 5)
                return false
            }
            throw ParseError.unexpected("expected bool", line: line)
        }

        mutating func parseNumber() throws -> Any {
            let start = index
            if text[index] == "-" || text[index] == "+" {
                advance()
            }
            while index < text.endIndex, let scalar = text[index].unicodeScalars.first,
                  CharacterSet.decimalDigits.contains(scalar) || scalar == "_" || scalar == "." || scalar == "e" || scalar == "E" || scalar == "-" || scalar == "+" {
                advance()
            }
            let raw = String(text[start ..< index]).replacingOccurrences(of: "_", with: "")
            if raw.contains(".") || raw.lowercased().contains("e") {
                if let d = Double(raw) { return d }
            }
            if let i = Int(raw) { return i }
            throw ParseError.unexpected("invalid number '\(raw)'", line: line)
        }

        mutating func parseArray() throws -> [Any] {
            try expect("[")
            var out: [Any] = []
            while true {
                skipWhitespaceAndComments()
                if index < text.endIndex, text[index] == "]" {
                    advance()
                    return out
                }
                let v = try parseValue()
                out.append(v)
                skipWhitespaceAndComments()
                if index < text.endIndex, text[index] == "," {
                    advance()
                    continue
                }
                if index < text.endIndex, text[index] == "]" {
                    advance()
                    return out
                }
                throw ParseError.unexpected("expected ',' or ']' in array", line: line)
            }
        }

        // MARK: - Path helpers (operate on a mutable [String:Any] tree)

        func getNested(root: [String: Any], path: [String]) -> Any? {
            var current: Any = root
            for part in path {
                guard let table = current as? [String: Any], let next = table[part] else { return nil }
                current = next
            }
            return current
        }

        func ensureTable(root: inout [String: Any], path: [String]) {
            guard !path.isEmpty else { return }
            ensureTablePart(root: &root, path: path, depth: 0)
        }

        private func ensureTablePart(root: inout [String: Any], path: [String], depth: Int) {
            guard depth < path.count else { return }
            let key = path[depth]
            var next = (root[key] as? [String: Any]) ?? [:]
            ensureTablePart(root: &next, path: path, depth: depth + 1)
            root[key] = next
        }

        func setNested(root: inout [String: Any], path: [String], value: Any) {
            guard !path.isEmpty else { return }
            setNestedPart(root: &root, path: path, depth: 0, value: value)
        }

        private func setNestedPart(root: inout [String: Any], path: [String], depth: Int, value: Any) {
            let key = path[depth]
            if depth == path.count - 1 {
                root[key] = value
                return
            }
            var next = (root[key] as? [String: Any]) ?? [:]
            setNestedPart(root: &next, path: path, depth: depth + 1, value: value)
            root[key] = next
        }

        func setLeafKey(root: inout [String: Any], path: [String], key: String, value: Any) {
            if path.isEmpty {
                root[key] = value
                return
            }
            setLeafKeyPart(root: &root, path: path, depth: 0, key: key, value: value)
        }

        private func setLeafKeyPart(root: inout [String: Any], path: [String], depth: Int, key: String, value: Any) {
            let pkey = path[depth]
            var next = (root[pkey] as? [String: Any]) ?? [:]
            if depth == path.count - 1 {
                next[key] = value
            } else {
                setLeafKeyPart(root: &next, path: path, depth: depth + 1, key: key, value: value)
            }
            root[pkey] = next
        }
    }
}
