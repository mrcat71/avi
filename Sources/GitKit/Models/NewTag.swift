import Foundation

/// A tag to create: annotated when it has a message, lightweight without one.
public struct NewTag: Sendable, Equatable, Hashable, Codable {
    public var name: String
    public var message: String?

    public init(name: String, message: String? = nil) {
        self.name = name
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.message = trimmed.isEmpty ? nil : trimmed
    }

    public var isAnnotated: Bool {
        message != nil
    }

    /// Why Git would refuse `name` as a tag name, or nil when it takes it.
    /// Follows `git check-ref-format` for `refs/tags/<name>`, plus `git tag`'s
    /// own rule against a leading dash.
    public static func problem(with name: String) -> String? {
        if name.isEmpty {
            return "A tag needs a name."
        }
        if name.hasPrefix("-") {
            return "A tag name cannot start with a dash."
        }
        if name == "@" {
            return "A tag cannot be named @."
        }
        if let scalar = name.unicodeScalars.first(where: isForbidden) {
            let shown = scalar == " " ? "a space" : scalar.value < 0x20 || scalar.value == 0x7F ? "a control character" : "\"\(scalar)\""
            return "A tag name cannot contain \(shown)."
        }
        if name.contains("..") {
            return "A tag name cannot contain \"..\"."
        }
        if name.contains("@{") {
            return "A tag name cannot contain \"@{\"."
        }
        if name.hasPrefix("/") || name.hasSuffix("/") || name.contains("//") {
            return "A tag name cannot start or end with \"/\" or contain \"//\"."
        }
        if name.hasSuffix(".") {
            return "A tag name cannot end with a dot."
        }
        for part in name.split(separator: "/") {
            if part.hasPrefix(".") {
                return "No part of a tag name can start with a dot."
            }
            if part.hasSuffix(".lock") {
                return "No part of a tag name can end with \".lock\"."
            }
        }
        return nil
    }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F || " ~^:?*[\\".unicodeScalars.contains(scalar)
    }
}

/// A local tag on a commit the remote does not have yet.
public struct UnpushedTag: Sendable, Equatable, Hashable {
    public let name: String
    /// Git treats annotated tags as meant for publishing, lightweight ones as
    /// private labels; `push --follow-tags` sends only the annotated kind.
    public let isAnnotated: Bool

    public init(name: String, isAnnotated: Bool) {
        self.name = name
        self.isAnnotated = isAnnotated
    }
}
