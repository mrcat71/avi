import AppKit
@testable import AppUI
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@MainActor
@Suite("Tab order")
struct TabOrderTests {
    struct Rows: Sendable, CustomTestStringConvertible {
        let widths: [CGFloat]
        let width: CGFloat
        /// Each tab's origin as (x, row).
        let expected: [Place]

        var testDescription: String {
            "\(widths) in \(width)"
        }
    }

    struct Place: Equatable, Sendable {
        let x: CGFloat
        let row: Int
    }

    @Test(arguments: [
        // Tabs that fit keep one row; 2 apart, rows 24 high and 2 apart.
        Rows(widths: [100, 100, 100], width: 310, expected: [Place(x: 0, row: 0), Place(x: 102, row: 0), Place(x: 204, row: 0)]),
        Rows(widths: [100, 100, 100], width: 300, expected: [Place(x: 0, row: 0), Place(x: 102, row: 0), Place(x: 0, row: 1)]),
        Rows(widths: [100, 100, 100, 100, 100], width: 210, expected: [
            Place(x: 0, row: 0), Place(x: 102, row: 0), Place(x: 0, row: 1), Place(x: 102, row: 1), Place(x: 0, row: 2)
        ]),
        // A tab wider than a row takes a row of its own.
        Rows(widths: [400, 100], width: 300, expected: [Place(x: 0, row: 0), Place(x: 0, row: 1)]),
        Rows(widths: [], width: 300, expected: [])
    ])
    func tabsWrapOnlyOnceTheyNoLongerFit(_ rows: Rows) {
        let frames = tabRowFrames(sizes: rows.widths.map { CGSize(width: $0, height: 24) }, spacing: 2, rowSpacing: 2, width: rows.width)
        #expect(frames.map { Place(x: $0.minX, row: Int($0.minY / 26)) } == rows.expected)
        #expect(frames.map(\.width) == rows.widths)
    }

    struct Drag: Sendable, CustomTestStringConvertible {
        let widths: [CGFloat]
        var width: CGFloat = 1000
        let index: Int
        let dx: CGFloat
        var dy: CGFloat = 0
        let expected: Int

        var testDescription: String {
            "tab \(index) of \(widths) in \(width) moved (\(dx), \(dy))"
        }
    }

    @Test(arguments: [
        // Equal tabs 100 wide, 2 apart: the edge reaches a neighbor's middle at 52.
        Drag(widths: [100, 100, 100, 100], index: 1, dx: 0, expected: 1),
        Drag(widths: [100, 100, 100, 100], index: 1, dx: 51, expected: 1),
        Drag(widths: [100, 100, 100, 100], index: 1, dx: 52, expected: 2),
        Drag(widths: [100, 100, 100, 100], index: 1, dx: -52, expected: 0),
        // A fast drag passes several tabs at once and stops at the end.
        Drag(widths: [100, 100, 100, 100], index: 1, dx: 160, expected: 3),
        Drag(widths: [100, 100, 100, 100], index: 1, dx: 300, expected: 3),
        Drag(widths: [100, 100, 100, 100], index: 0, dx: -500, expected: 0),
        // The neighbor's width decides, not the dragged tab's.
        Drag(widths: [80, 200, 60], index: 0, dx: 100, expected: 0),
        Drag(widths: [80, 200, 60], index: 0, dx: 102, expected: 1),
        Drag(widths: [100], index: 0, dx: 80, expected: 0),
        // Rows of three: down a row is the next row's first place, then along it.
        Drag(widths: [100, 100, 100, 100, 100], width: 310, index: 0, dx: 0, dy: 26, expected: 3),
        Drag(widths: [100, 100, 100, 100, 100], width: 310, index: 0, dx: 102, dy: 26, expected: 4),
        Drag(widths: [100, 100, 100, 100, 100], width: 310, index: 4, dx: -102, dy: -26, expected: 0),
        // Below the rows, the nearest place in the last row.
        Drag(widths: [100, 100, 100, 100, 100], width: 310, index: 4, dx: 0, dy: 200, expected: 4)
    ])
    func draggedTabTakesTheNearestPlace(_ drag: Drag) {
        let sizes = drag.widths.map { CGSize(width: $0, height: 24) }
        let start = tabRowFrames(sizes: sizes, spacing: 2, rowSpacing: 2, width: drag.width)[drag.index]
        let target = tabDropIndex(
            dragged: drag.index,
            drawnAt: start.offsetBy(dx: drag.dx, dy: drag.dy),
            sizes: sizes,
            spacing: 2,
            rowSpacing: 2,
            width: drag.width
        )
        #expect(target == drag.expected)
    }

    /// The tab that just passed a neighbor stays there until the pointer
    /// moves on, whatever order the rows are in now.
    @Test func aPlaceTakenDoesNotFlipBack() {
        let sizes = [80, 200, 60].map { CGSize(width: $0, height: 24) }
        let drawn = CGRect(x: 102, y: 0, width: 80, height: 24)
        let passed = tabDropIndex(dragged: 0, drawnAt: drawn, sizes: sizes, spacing: 2, rowSpacing: 2, width: 1000)
        #expect(passed == 1)
        let reordered = [sizes[1], sizes[0], sizes[2]]
        #expect(tabDropIndex(dragged: 1, drawnAt: drawn, sizes: reordered, spacing: 2, rowSpacing: 2, width: 1000) == 1)
    }

    /// Tabs named long enough to reach the widest tab, 198 points, so 3 fit in
    /// a row of an 800-point bar.
    @Test(arguments: [(1, 32.0, false), (3, 32.0, false), (4, 58.0, false), (9, 84.0, false), (10, 84.0, true)])
    func theBarKeepsOneRowUntilTabsNeedMoreAndScrollsPastThree(count: Int, height: CGFloat, scrolls: Bool) async throws {
        let suite = "avi-tab-bar-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = WorkspaceSession(git: Fixtures.clean(), defaults: defaults)
        for number in 0 ..< count {
            await session.open(URL(fileURLWithPath: "/tmp/avi-tab-with-a-rather-long-repository-name-\(number)", isDirectory: true))
        }
        for store in session.repositories {
            store.stopBackgroundObservation()
        }
        session.select(session.repositories.first?.id)
        let bar = RepositoryTabsBar(session: session, openRepositoryPicker: {})
        let controller = NSHostingController(rootView: bar)
        let size = controller.sizeThatFits(in: CGSize(width: 800, height: 1000))
        #expect(size.height == height)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: size.height), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 800, height: size.height))
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        #expect(containsScrollView(controller.view) == scrolls)
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains { containsScrollView($0) }
    }

    @Test func movedTabTakesTheTargetsPlaceAndKeepsTheSelection() async {
        let session = WorkspaceSession(git: Fixtures.clean())
        for name in ["a", "b", "c"] {
            await session.open(URL(fileURLWithPath: "/tmp/avi-tab-\(name)", isDirectory: true))
        }
        let ids = session.repositories.map(\.id)
        let order = { session.repositories.map { $0.root?.lastPathComponent ?? "?" } }
        #expect(order() == ["avi-tab-a", "avi-tab-b", "avi-tab-c"])
        session.select(ids[1])

        session.moveRepository(ids[0], toPlaceOf: ids[2])
        #expect(order() == ["avi-tab-b", "avi-tab-c", "avi-tab-a"])
        session.moveRepository(ids[0], toPlaceOf: ids[1])
        #expect(order() == ["avi-tab-a", "avi-tab-b", "avi-tab-c"])
        #expect(session.selectedRepositoryID == ids[1])

        session.moveRepository(ids[0], toPlaceOf: ids[0])
        session.moveRepository(ids[0], toPlaceOf: UUID())
        #expect(order() == ["avi-tab-a", "avi-tab-b", "avi-tab-c"])

        for id in ids {
            session.close(id)
        }
    }
}
