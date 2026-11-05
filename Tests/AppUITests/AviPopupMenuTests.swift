import AppKit
@testable import AppUI
import SwiftUI
import XCTest

/// `AviPopupMenu` replaces the menu pickers in Push. A menu picker grows to
/// its longest option, and Into lists every branch on the remote, so one
/// long branch name made the sheet's content wider than its window and cut
/// off both edges.
final class AviPopupMenuTests: XCTestCase {
    func testPillKeepsToItsMaximumWidth() {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let long = "renovate/" + String(repeating: "lockfile-maintenance-", count: 8)
            let cap: CGFloat = 240
            let longWidth = Self.width(of: AviPopupMenu("Into", options: ["main", long], selection: .constant(long), maxWidth: cap))
            XCTAssertGreaterThanOrEqual(longWidth, cap, "a long value fills the pill up to its cap")
            XCTAssertLessThanOrEqual(longWidth, cap + 44, "a long value never takes more than the cap and the chevron")

            let shortWidth = Self.width(of: AviPopupMenu("Into", options: ["main", long], selection: .constant("main"), maxWidth: cap))
            XCTAssertLessThan(shortWidth, 100, "a short value keeps the pill short")
        }
    }

    func testMenuTicksTheChosenOptionAndChoosesTheClickedOne() {
        MainActor.assumeIsolated {
            let chosen = Chosen()
            let menu = AviPopupMenu.menu(options: ["main", "release/2026-10"], selection: "main") { chosen.values.append($0) }
            XCTAssertEqual(menu.items.map(\.title), ["main", "release/2026-10"])
            XCTAssertEqual(menu.items.map(\.state), [.on, .off])
            menu.performActionForItem(at: 1)
            XCTAssertEqual(chosen.values, ["release/2026-10"])
        }
    }

    @MainActor
    private static func width(of view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.width
    }

    @MainActor
    private final class Chosen {
        var values: [String] = []
    }
}
