import AppKit
@testable import AppUI
import GitKit
import SwiftUI
import XCTest

final class LocalBranchRowInteractionTests: XCTestCase {
    func testDoubleClickSelectsBeforeCheckout() {
        MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.doubleClick()
            XCTAssertEqual(fixture.calls.selection, .branch(name: fixture.ref.name))
            XCTAssertEqual(Array(fixture.calls.events.suffix(2)), ["select", "checkout"])
            XCTAssertEqual(fixture.calls.events.filter { $0 == "checkout" }.count, 1)
        }
    }

    func testDoubleClickStillSelectsWhenCheckoutIsUnavailable() {
        MainActor.assumeIsolated {
            for (current, held) in [(true, false), (false, true)] {
                let fixture = Fixture(isCurrent: current, held: held)
                defer { fixture.close() }
                fixture.doubleClick()
                XCTAssertEqual(fixture.calls.selection, .branch(name: fixture.ref.name))
                XCTAssertFalse(fixture.calls.events.contains("checkout"))
            }
        }
    }

    func testSelectedBackgroundRemainsTranslucentInBothAppearances() throws {
        try MainActor.assumeIsolated {
            _ = NSApplication.shared
            for scheme in [ColorScheme.light, .dark] {
                let ref = GitReference(name: "feature", fullName: "refs/heads/feature",
                                       oid: String(repeating: "a", count: 40), kind: .localBranch)
                let row = LocalBranchRow(ref: ref, store: RepositoryStore(), isSelected: true,
                                         select: {}, checkout: {})
                    .environment(\.colorScheme, scheme)
                    .frame(width: 360)
                let renderer = ImageRenderer(content: row)
                let bitmap = try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
                let fill = try XCTUnwrap(bitmap.colorAt(x: 300, y: bitmap.pixelsHigh / 2))
                XCTAssertEqual(fill.alphaComponent, 0.14, accuracy: 0.01)
            }
        }
    }

    @MainActor
    private final class Fixture {
        final class Calls {
            var events: [String] = []
            var selection: RepositorySelection = .branch(name: "previous")
        }

        let ref: GitReference
        let calls = Calls()
        let host: NSHostingView<AnyView>
        let window: NSWindow

        init(isCurrent: Bool = false, held: Bool = false) {
            _ = NSApplication.shared
            ref = GitReference(name: "feature", fullName: "refs/heads/feature",
                               oid: String(repeating: "a", count: 40), kind: .localBranch,
                               isCurrent: isCurrent)
            let calls = calls
            let ref = ref
            let holder = held ? Worktree(path: URL(fileURLWithPath: "/tmp/avi-other-worktree"), branch: ref.name) : nil
            host = NSHostingView(rootView: AnyView(
                LocalBranchRow(ref: ref, store: RepositoryStore(), heldBy: holder, isSelected: false,
                               select: {
                                   calls.events.append("select")
                                   calls.selection = .branch(name: ref.name)
                               }, checkout: { calls.events.append("checkout") })
                    .frame(width: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            ))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        func close() {
            window.close()
        }

        func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(NSEvent.doubleClickInterval + 0.1))
            host.layoutSubtreeIfNeeded()
        }

        func doubleClick() {
            click(count: 1)
            click(count: 2)
            settle()
        }

        func click(count: Int) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type, location: host.convert(NSPoint(x: 60, y: host.bounds.midY), to: nil),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: count,
                    clickCount: count, pressure: 1
                )!
                NSApp.postEvent(event, atStart: false)
            }
            while let next = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date(),
                                             inMode: .default, dequeue: true) {
                NSApp.sendEvent(next)
            }
        }
    }
}
