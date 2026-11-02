import Foundation
import Observation
import SwiftUI

/// A floating card at the top of a window's content, after Rex's notices:
/// update progress, a Git error, anything that happened while you worked.
/// Notices never block the window. One that needs an answer keeps its buttons
/// until you choose; the others close with their close button or by themselves.
struct AviNotice: Identifiable {
    enum Tone: Equatable {
        case info
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .info: return DS.Palette.accent
            case .success: return DS.Palette.success
            case .warning: return DS.Palette.warning
            case .error: return DS.Palette.danger
            }
        }
    }

    enum Progress: Equatable {
        case indeterminate
        /// From 0 to 1.
        case fraction(Double)
    }

    /// A button under the message. Notices take no Return or Escape: the
    /// window under them keeps its keys.
    struct Action: Identifiable {
        enum Role {
            case primary
            case secondary
            case destructive
        }

        let title: String
        var role: Role = .secondary
        let perform: @MainActor () -> Void

        var id: String {
            title
        }
    }

    /// More text behind a disclosure under the message, such as release notes.
    struct Details {
        let title: String
        let content: AnyView
    }

    var id: String
    var tone: Tone = .info
    var symbol: String
    var title: String
    var message: String?
    var details: Details?
    var progress: Progress?
    var actions: [Action] = []
    /// What the close button does; nil leaves the notice without one.
    var onDismiss: (@MainActor () -> Void)?
    /// Closes the notice after this long, counted while the pointer is away.
    var autoDismiss: Duration?
}

/// Notices that belong to the app rather than one window, such as the
/// update's. The window you work in shows them; a window's own notices, its
/// Git errors, come from that window's state.
@MainActor
@Observable
final class AviNoticeCenter {
    static let shared = AviNoticeCenter()

    private(set) var notices: [AviNotice] = []
    /// Bumped to make a notice draw attention to itself again.
    private(set) var attention: [String: Int] = [:]

    init() {}

    /// Shows `notice`, or replaces the one with its id where it stands.
    func show(_ notice: AviNotice) {
        if let index = notices.firstIndex(where: { $0.id == notice.id }) {
            notices[index] = notice
        } else {
            notices.append(notice)
        }
    }

    func dismiss(id: String) {
        notices.removeAll { $0.id == id }
        attention[id] = nil
    }

    func callAttention(to id: String) {
        guard notices.contains(where: { $0.id == id }) else { return }
        attention[id, default: 0] += 1
    }
}

/// Splits an error message into a notice's short title and the rest, so
/// "Could not save the patch: disk full" reads as a title and its reason.
enum ErrorNoticeText {
    static let fallbackTitle = "Git Error"
    private static let maxTitleLength = 72
    private static let maxPrefixLength = 60

    static func split(_ text: String) -> (title: String, message: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (fallbackTitle, nil) }
        let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let firstLine = String(lines[0]).trimmingCharacters(in: .whitespaces)
        let rest = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if let colon = firstLine.range(of: ": ") {
            let prefix = String(firstLine[..<colon.lowerBound])
            if isTitleLike(prefix) {
                let after = String(firstLine[colon.upperBound...])
                return (prefix, joined(after, rest))
            }
        }
        if firstLine.count <= maxTitleLength, !startsWithGitPrefix(firstLine) {
            return (strippingEnd(firstLine), rest.isEmpty ? nil : rest)
        }
        if let stop = firstLine.range(of: ". ") {
            let sentence = String(firstLine[..<stop.lowerBound])
            if sentence.count <= maxTitleLength, isTitleLike(sentence) {
                return (sentence, joined(String(firstLine[stop.upperBound...]), rest))
            }
        }
        return (fallbackTitle, trimmed)
    }

    /// Two words or more, short, and not Git's own `fatal:` or `error:`.
    private static func isTitleLike(_ text: String) -> Bool {
        text.count <= maxPrefixLength
            && text.split(separator: " ").count >= 2
            && !startsWithGitPrefix(text)
    }

    private static func startsWithGitPrefix(_ text: String) -> Bool {
        ["fatal:", "error:", "warning:", "hint:", "remote:", "!"].contains { text.lowercased().hasPrefix($0) }
    }

    private static func strippingEnd(_ text: String) -> String {
        var result = text
        while let last = result.last, last == "." || last == ":" {
            result.removeLast()
        }
        return result
    }

    private static func joined(_ head: String, _ tail: String) -> String? {
        let parts = [head, tail].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

extension AviNotice {
    /// A Git or file error, closed with its close button or Copy.
    static func error(id: String, text: String, onDismiss: @escaping @MainActor () -> Void) -> AviNotice {
        let parts = ErrorNoticeText.split(text)
        return AviNotice(
            id: id,
            tone: .error,
            symbol: "exclamationmark.triangle.fill",
            title: parts.title,
            message: parts.message,
            actions: [
                Action(title: "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            ],
            onDismiss: onDismiss
        )
    }
}
