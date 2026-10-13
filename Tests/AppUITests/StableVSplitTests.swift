@testable import AppUI
import CoreGraphics
import SwiftUI
import Testing

@MainActor
@Suite("Stable split")
struct StableVSplitTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let wanted: Double
        let total: CGFloat
        let expected: CGFloat

        var testDescription: String {
            "\(wanted) wanted in \(total)"
        }
    }

    /// Top at least 240, bottom at least 190, a 5-point divider between them.
    @Test(arguments: [
        // Room for both: the bottom gets exactly what you left it at.
        Case(wanted: 220, total: 800, expected: 220),
        Case(wanted: 400, total: 800, expected: 400),
        // Too tall for the window: the top keeps its minimum.
        Case(wanted: 700, total: 800, expected: 555),
        // A window too short for both minimums still keeps the bottom's.
        Case(wanted: 220, total: 300, expected: 190),
        // Never under the bottom's own minimum.
        Case(wanted: 50, total: 800, expected: 190)
    ])
    func bottomPaneKeepsItsHeightUnlessTheWindowIsTooShort(_ item: Case) {
        let shown = StableVSplit<EmptyView, EmptyView>.shownBottomHeight(item.wanted, total: item.total, minTop: 240, minBottom: 190)
        #expect(shown == item.expected)
    }
}
