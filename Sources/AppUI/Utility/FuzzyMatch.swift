import Foundation

/// Simple smart-case subsequence scorer for command-palette filtering.
/// Higher scores rank earlier. Returns `nil` when the query has any
/// character that isn't a subsequence of the haystack.
enum FuzzyMatch {
    struct Result: Equatable {
        var score: Int
        /// Indexes in the haystack that matched (in order). Use to bold
        /// matched characters in the UI.
        var matchedIndexes: [String.Index]
    }

    /// Score `haystack` against `needle`. Empty needle returns score 0
    /// (everything matches; caller should treat as "no filter").
    static func score(needle: String, haystack: String) -> Result? {
        if needle.isEmpty { return Result(score: 0, matchedIndexes: []) }
        let smartCase = needle.allSatisfy { !$0.isUppercase }
        let h = smartCase ? haystack.lowercased() : haystack
        let n = smartCase ? needle.lowercased() : needle

        var hIdx = h.startIndex
        var nIdx = n.startIndex
        var matched: [String.Index] = []
        var score = 0
        var streak = 0
        var lastChar: Character = " "

        while nIdx < n.endIndex, hIdx < h.endIndex {
            let nc = n[nIdx]
            let hc = h[hIdx]
            if nc == hc {
                matched.append(haystack.index(haystack.startIndex, offsetBy: h.distance(from: h.startIndex, to: hIdx)))
                streak += 1
                score += 5 + streak * 2
                // Word-start boost: first char or after space/sep.
                if hIdx == h.startIndex || lastChar.isWhitespace || lastChar == "-" || lastChar == "_" || lastChar == "/" {
                    score += 10
                }
                nIdx = n.index(after: nIdx)
            } else {
                streak = 0
                score -= 1
            }
            lastChar = hc
            hIdx = h.index(after: hIdx)
        }

        // Needle must be fully consumed.
        guard nIdx == n.endIndex else { return nil }

        // Shorter haystacks score slightly higher (proxy for relevance).
        score += max(0, 50 - h.count)

        return Result(score: score, matchedIndexes: matched)
    }
}
