import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

final class LocalBranchRowLayoutTests: XCTestCase {
    func testGoneBadgeDoesNotWrapOrClip() throws {
        try MainActor.assumeIsolated {
            try Self.assertBadgeLayouts()
        }
    }

    @MainActor
    private static func assertBadgeLayouts() throws {
        _ = NSApplication.shared
        // No repository is opened and no Git actions are invoked.
        let store = RepositoryStore()
        var referenceSize: CGSize?
        for width in [220.0, 360.0] {
            for density in [Density.compact, .comfortable] {
                for selected in [false, true] {
                    for current in [false, true] {
                        let ref = GitReference(
                            name: "INFRA-14755-audit-logging", fullName: "refs/heads/audit-logging",
                            oid: String(repeating: "a", count: 40), kind: .localBranch,
                            upstream: "origin/audit-logging", isCurrent: current, isUpstreamGone: true
                        )
                        let row = LocalBranchRow(ref: ref, store: store, isSelected: selected, select: {}, checkout: {})
                            .environment(\.aviDensity, density)
                            .environment(\.colorScheme, .dark)
                            .frame(width: width)
                        let renderer = ImageRenderer(content: row)
                        renderer.scale = 2
                        let bitmap = try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
                        let badge = try badgeBounds(in: bitmap)
                        XCTAssertGreaterThan(badge.minY, 0)
                        XCTAssertLessThan(badge.maxY, CGFloat(bitmap.pixelsHigh))
                        XCTAssertLessThan(badge.maxX, CGFloat(bitmap.pixelsWide))
                        if let referenceSize {
                            XCTAssertEqual(badge.width, referenceSize.width, accuracy: 2)
                            XCTAssertEqual(badge.height, referenceSize.height, accuracy: 2)
                        } else {
                            referenceSize = badge.size
                        }
                    }
                }
            }
        }
    }

    func testUpstreamChipSaysTheRemoteWhenTheNameMatches() {
        let cases: [(upstream: String, branch: String, full: String, short: String?)] = [
            ("origin/stable", "stable", "origin", nil),
            ("origin/feature/x", "feature/x", "origin", nil),
            ("upstream/main", "fix", "upstream/main", "upstream"),
            // A branch tracking a local branch has no remote to name.
            ("main", "fix", "main", nil)
        ]
        for item in cases {
            let labels = UpstreamChipLabels(upstream: item.upstream, branch: item.branch)
            XCTAssertEqual(labels.full, item.full, item.upstream)
            XCTAssertEqual(labels.short, item.short, item.upstream)
        }
    }

    /// The screenshot's "o…lt" and empty pill: a long name must hide the
    /// upstream chip entirely, while a short one leaves room to show it.
    func testUpstreamChipShowsWholeOrNotAtAll() throws {
        try MainActor.assumeIsolated {
            let long = "INFRA-15656_infratest_benchmark_nodes"
            let narrowWith = try Self.render(name: long, upstream: "origin/\(long)", width: 220)
            let narrowWithout = try Self.render(name: long, upstream: nil, width: 220)
            XCTAssertEqual(narrowWith, narrowWithout, "A chip that does not fit must not be drawn at all")

            let wideWith = try Self.render(name: "stable", upstream: "origin/stable", width: 220)
            let wideWithout = try Self.render(name: "stable", upstream: nil, width: 220)
            XCTAssertNotEqual(wideWith, wideWithout, "A chip that fits must be drawn")
        }
    }

    /// The row's pixels. Ahead and behind counts are set either way, so the
    /// only possible difference is the upstream chip.
    @MainActor
    private static func render(name: String, upstream: String?, width: CGFloat) throws -> Data {
        _ = NSApplication.shared
        let ref = GitReference(
            name: name, fullName: "refs/heads/\(name)", oid: String(repeating: "b", count: 40), kind: .localBranch,
            upstream: upstream, isCurrent: true, ahead: 1, behind: 1
        )
        let row = LocalBranchRow(ref: ref, store: RepositoryStore(), isSelected: false, select: {}, checkout: {})
            .environment(\.aviDensity, .comfortable)
            .environment(\.colorScheme, .dark)
            .frame(width: width)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        let bitmap = try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private static func badgeBounds(in bitmap: NSBitmapImageRep) throws -> CGRect {
        var bounds: CGRect?
        for y in 0 ..< bitmap.pixelsHigh {
            // Skip the red branch icon in the leading 30 points at 2x scale.
            for x in 60 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.9, color.redComponent > 0.8,
                      color.greenComponent < 0.4, color.blueComponent < 0.5 else { continue }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return try XCTUnwrap(bounds, "The GONE badge must remain visible")
    }
}
