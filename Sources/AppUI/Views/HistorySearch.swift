import GitKit
import SwiftUI

/// Matches History rows against the search field. Every word of the query has
/// to appear in the subject, body, author, or email, or start the commit SHA.
/// Matching ignores case and diacritics.
enum HistorySearch {
    /// The query's words, lowercased. Empty means there is nothing to search for.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
    }

    static func matches(_ commit: CommitSummary, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        let fields = [commit.subject, commit.body, commit.authorName, commit.authorEmail]
        return terms.allSatisfy { term in
            isSHAPrefix(term, of: commit.oid) || fields.contains { contains($0, term) }
        }
    }

    /// Four or more hex digits that start the SHA, as Git abbreviates it.
    static func isSHAPrefix(_ term: String, of oid: String) -> Bool {
        term.count >= 4 && term.allSatisfy(\.isHexDigit) && oid.lowercased().hasPrefix(term)
    }

    /// The ranges of `text` that hold a search word, sorted and merged where
    /// they touch, ready for highlighting.
    static func highlightRanges(in text: String, terms: [String]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let found = text.range(of: term, options: options, range: searchStart ..< text.endIndex) {
                ranges.append(found)
                searchStart = found.upperBound
            }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Where Return (+1) or Shift-Return (-1) goes from the selected row: the
    /// next match after it, or before it, wrapping around. `matches` holds row
    /// indexes in display order.
    static func nextMatch(after selected: Int?, in matches: [Int], step: Int) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let selected else {
            return step >= 0 ? matches.first : matches.last
        }
        if step >= 0 {
            return matches.first { $0 > selected } ?? matches.first
        }
        return matches.last { $0 < selected } ?? matches.last
    }

    /// `text` with every search word highlighted.
    static func highlighted(_ text: String, terms: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in highlightRanges(in: text, terms: terms) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower ..< upper].backgroundColor = DS.Palette.searchHighlight
        }
        return attributed
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private static func contains(_ field: String, _ term: String) -> Bool {
        field.range(of: term, options: options) != nil
    }
}

/// The History header's search: a magnifier that expands into a field.
/// Return and Down go to the next match, Shift-Return and Up to the previous
/// one, Escape clears the search and closes the field.
struct HistorySearchField: View {
    @Binding var query: String
    @Binding var isExpanded: Bool
    var isFocused: FocusState<Bool>.Binding
    /// Position of the selected commit among the matches, when it is one.
    let position: Int?
    let matchCount: Int
    let step: (Int) -> Void

    @Environment(\.aviDensity) private var density

    var body: some View {
        Group {
            if isExpanded {
                field
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            } else {
                Button(action: expand) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: DS.IconScale.md, weight: .medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search commits")
                .accessibilityLabel("Search commits")
                .transition(.opacity)
            }
        }
        .animation(Glass.Motion.snappy, value: isExpanded)
    }

    private var field: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DS.IconScale.sm, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
            TextField("Message, author, or SHA", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(isFocused)
                .onSubmit { step(1) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    step(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    step(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    step(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .accessibilityLabel("Search commits")
            if !query.isEmpty {
                Text(counter)
                    .font(DS.Font.label(density))
                    .monospacedDigit()
                    .foregroundStyle(matchCount == 0 ? DS.Palette.warning : DS.Palette.textTertiary)
                    .accessibilityLabel(accessibilityCounter)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DS.IconScale.md))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 250, height: 22)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? DS.Palette.accent.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: 0.8)
        )
    }

    private var counter: String {
        if matchCount == 0 {
            return "0"
        }
        if let position {
            return "\(position)/\(matchCount)"
        }
        return "\(matchCount)"
    }

    private var accessibilityCounter: String {
        if matchCount == 0 {
            return "No matches"
        }
        if let position {
            return "Match \(position) of \(matchCount)"
        }
        return matchCount == 1 ? "1 match" : "\(matchCount) matches"
    }

    private func expand() {
        isExpanded = true
        isFocused.wrappedValue = true
    }

    private func close() {
        query = ""
        isFocused.wrappedValue = false
        isExpanded = false
    }
}
