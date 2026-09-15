import AppKit
@testable import AppUI
import SwiftUI
import XCTest

/// The section header is itself a button, so a trailing control has to win the
/// click instead of collapsing the section underneath it.
final class SectionHeaderTrailingTests: XCTestCase {
    func testTrailingButtonClickDoesNotToggleTheSection() {
        MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }

            fixture.click(atX: fixture.trailingCenterX)

            XCTAssertEqual(fixture.state.trailingClicks, 1)
            XCTAssertTrue(fixture.state.expanded, "Clicking the trailing control must not collapse the section")
        }
    }

    func testClickingTheHeaderItselfStillToggles() {
        MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }

            fixture.click(atX: 60)

            XCTAssertEqual(fixture.state.trailingClicks, 0)
            XCTAssertFalse(fixture.state.expanded)
        }
    }

    @MainActor
    private final class Fixture {
        final class State {
            var expanded = true
            var trailingClicks = 0
        }

        let state = State()
        let host: NSHostingView<AnyView>
        let window: NSWindow
        let width: CGFloat = 260

        /// Matches AviSectionHeader: trailing sits inside DS.Spacing.xl padding,
        /// and the control this app puts there is 16pt wide.
        var trailingCenterX: CGFloat {
            width - DS.Spacing.xl - 8
        }

        init() {
            _ = NSApplication.shared
            let state = state
            host = NSHostingView(rootView: AnyView(
                AviSectionHeader(
                    "Branches",
                    count: 2,
                    isExpanded: Binding(get: { state.expanded }, set: { state.expanded = $0 })
                ) {
                    Button {
                        state.trailingClicks += 1
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: width)
            ))
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: 30),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            settle()
        }

        func close() {
            window.close()
        }

        func click(atX x: CGFloat) {
            let point = NSPoint(x: x, y: host.bounds.midY)
            window.sendEvent(event(.leftMouseDown, at: point))
            window.sendEvent(event(.leftMouseUp, at: point))
            settle()
        }

        private func settle() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            host.layoutSubtreeIfNeeded()
        }

        private func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            )!
        }
    }
}
