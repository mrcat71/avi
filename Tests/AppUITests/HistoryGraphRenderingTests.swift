import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

final class HistoryGraphRenderingTests: XCTestCase {
    func testUnmergedTipHasNoLineAboveDot() throws {
        let rows = CommitGraph.assignRows(for: [
            commit("main", parents: ["base"]),
            commit("feature", parents: ["base"]),
            commit("base")
        ])

        try MainActor.assumeIsolated {
            for scheme in [ColorScheme.light, .dark] {
                for selected in [false, true] {
                    let bitmap = try Self.render(rows[1], scheme: scheme, selected: selected)
                    XCTAssertLessThan(try Self.red(in: bitmap, lane: 1, y: 4), 0.1, "No stub above the branch tip")
                    XCTAssertGreaterThan(try Self.red(in: bitmap, lane: 1, y: 20), 0.9, "The dot remains visible")
                    XCTAssertGreaterThan(try Self.red(in: bitmap, lane: 1, y: 36), 0.9, "The parent line remains visible")
                    XCTAssertGreaterThan(try Self.red(in: bitmap, lane: 0, y: 4), 0.9, "Other lanes continue above")
                    XCTAssertGreaterThan(try Self.red(in: bitmap, lane: 0, y: 36), 0.9, "Other lanes continue below")
                }
            }
        }
    }

    func testMergedTipKeepsLineFromMergeCommit() throws {
        let rows = CommitGraph.assignRows(for: [
            commit("merge", parents: ["main", "feature"]),
            commit("main", parents: ["base"]),
            commit("feature", parents: ["base"]),
            commit("base")
        ])

        try MainActor.assumeIsolated {
            let bitmap = try Self.render(rows[2], scheme: .dark, selected: false)
            XCTAssertGreaterThan(try Self.red(in: bitmap, lane: 1, y: 4), 0.9)
            XCTAssertGreaterThan(try Self.red(in: bitmap, lane: 1, y: 36), 0.9)
        }
    }

    @MainActor
    private static func render(_ row: CommitGraphRow, scheme: ColorScheme, selected: Bool) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let view = HistoryGraphView(row: row, isSelected: selected, laneColors: [0: .red, 1: .red])
            .frame(height: 40)
            .environment(\.colorScheme, scheme)
            .background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
    }

    @MainActor
    private static func red(in bitmap: NSBitmapImageRep, lane: Int, y: Int) throws -> CGFloat {
        let x = Int(HistoryGraphView.nodeX(lane: lane, laneWidth: 16) * 2)
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y * 2)?.usingColorSpace(.deviceRGB))
        return color.redComponent
    }

    private func commit(_ oid: String, parents: [String] = []) -> CommitSummary {
        CommitSummary(
            oid: oid, parentOIDs: parents, authorName: "Avi Test", authorEmail: "test@example.com",
            authorDate: Date(timeIntervalSince1970: 0), subject: oid, body: ""
        )
    }
}
