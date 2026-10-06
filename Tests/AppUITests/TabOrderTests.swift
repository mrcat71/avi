@testable import AppUI
import CoreGraphics
import Foundation
import Testing

@MainActor
@Suite("Tab order")
struct TabOrderTests {
    struct Drag: Sendable, CustomTestStringConvertible {
        let widths: [CGFloat]
        let index: Int
        let offset: CGFloat
        let expectedIndex: Int
        let expectedOffset: CGFloat

        var testDescription: String {
            "tab \(index) of \(widths) moved \(offset)"
        }
    }

    @Test(arguments: [
        // Equal tabs 100 wide, 2 apart: the edge reaches a neighbor's middle at 52.
        Drag(widths: [100, 100, 100, 100], index: 1, offset: 0, expectedIndex: 1, expectedOffset: 0),
        Drag(widths: [100, 100, 100, 100], index: 1, offset: 52, expectedIndex: 1, expectedOffset: 52),
        Drag(widths: [100, 100, 100, 100], index: 1, offset: 53, expectedIndex: 2, expectedOffset: -49),
        Drag(widths: [100, 100, 100, 100], index: 1, offset: -53, expectedIndex: 0, expectedOffset: 49),
        // A fast drag passes several tabs at once and stops at the end.
        Drag(widths: [100, 100, 100, 100], index: 1, offset: 160, expectedIndex: 3, expectedOffset: -44),
        Drag(widths: [100, 100, 100, 100], index: 1, offset: 300, expectedIndex: 3, expectedOffset: 96),
        Drag(widths: [100, 100, 100, 100], index: 0, offset: -500, expectedIndex: 0, expectedOffset: -500),
        // Just past a neighbor, the tab stays put instead of flipping back.
        Drag(widths: [100, 100, 100, 100], index: 2, offset: -49, expectedIndex: 2, expectedOffset: -49),
        // The neighbor's width decides, not the dragged tab's.
        Drag(widths: [80, 200, 60], index: 0, offset: 102, expectedIndex: 0, expectedOffset: 102),
        Drag(widths: [80, 200, 60], index: 0, offset: 103, expectedIndex: 1, expectedOffset: -99),
        Drag(widths: [100], index: 0, offset: 80, expectedIndex: 0, expectedOffset: 80)
    ])
    func draggedTabFindsItsPlace(_ drag: Drag) {
        let target = tabDragTarget(index: drag.index, offset: drag.offset, widths: drag.widths, spacing: 2)
        #expect(target.index == drag.expectedIndex)
        #expect(target.offset == drag.expectedOffset)
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
