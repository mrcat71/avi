import AppKit
@testable import AppUI
import SwiftUI
import XCTest

/// `aviKeyboardShortcut(_:)` puts the pill's key on an AppKit button in the
/// pill's own window. A sheet presented from inside a split view's pane got
/// its SwiftUI shortcuts routed to the window behind it, so Return and Escape
/// did nothing in Push; these press that AppKit button directly, the way the
/// sheet's window does, without SwiftUI's routing.
final class AviKeyboardShortcutTests: XCTestCase {
    func testDefaultActionTakesReturnAndKeypadEnter() throws {
        try MainActor.assumeIsolated {
            let presses = Presses()
            let fixture = Fixture {
                Button("Push") { presses.count += 1 }
                    .buttonStyle(.aviProminent)
                    .aviKeyboardShortcut(.defaultAction)
            }
            defer { fixture.close() }

            let key = try XCTUnwrap(fixture.keyButton(for: "\r"), "the pill has an AppKit button for Return")
            XCTAssertEqual(key.keyEquivalentModifierMask, [])
            XCTAssertTrue(key.performKeyEquivalent(with: fixture.key("\r", code: 36)))
            XCTAssertTrue(key.performKeyEquivalent(with: fixture.key("\u{3}", code: 76, flags: .numericPad)))
            XCTAssertEqual(presses.count, 2)
        }
    }

    func testCancelActionTakesEscape() throws {
        try MainActor.assumeIsolated {
            let presses = Presses()
            let fixture = Fixture {
                HStack {
                    Button("Cancel", role: .cancel) { presses.cancelled += 1 }
                        .buttonStyle(.aviSecondary)
                        .aviKeyboardShortcut(.cancelAction)
                    Button("Push") { presses.count += 1 }
                        .buttonStyle(.aviProminent)
                        .aviKeyboardShortcut(.defaultAction)
                }
            }
            defer { fixture.close() }

            let escape = try XCTUnwrap(fixture.keyButton(for: "\u{1b}"), "Cancel has an AppKit button for Escape")
            XCTAssertTrue(escape.performKeyEquivalent(with: fixture.key("\u{1b}", code: 53)))
            XCTAssertEqual(presses.cancelled, 1)
            XCTAssertEqual(presses.count, 0, "Escape cancels without pushing")
        }
    }

    func testModifiersCarryOver() throws {
        try MainActor.assumeIsolated {
            let presses = Presses()
            let fixture = Fixture {
                Button("Start Rebase") { presses.count += 1 }
                    .buttonStyle(.aviProminent)
                    .aviKeyboardShortcut(.return, modifiers: .command)
            }
            defer { fixture.close() }

            let key = try XCTUnwrap(fixture.keyButton(for: "\r"))
            XCTAssertEqual(key.keyEquivalentModifierMask, [.command])
            XCTAssertFalse(key.performKeyEquivalent(with: fixture.key("\r", code: 36)), "Return alone is not Cmd+Return")
            XCTAssertTrue(key.performKeyEquivalent(with: fixture.key("\r", code: 36, flags: .command)))
            XCTAssertEqual(presses.count, 1)
        }
    }

    func testDisabledPillIgnoresItsKey() throws {
        try MainActor.assumeIsolated {
            let presses = Presses()
            let fixture = Fixture {
                Button("Push") { presses.count += 1 }
                    .buttonStyle(.aviProminent)
                    .aviKeyboardShortcut(.defaultAction)
                    .disabled(true)
            }
            defer { fixture.close() }

            let key = try XCTUnwrap(fixture.keyButton(for: "\r"))
            XCTAssertFalse(key.performKeyEquivalent(with: fixture.key("\r", code: 36)))
            XCTAssertEqual(presses.count, 0)
        }
    }

    /// Settings and notice buttons use the same pill and must take no keys.
    func testPillWithoutShortcutHasNoKey() {
        MainActor.assumeIsolated {
            let fixture = Fixture {
                HStack {
                    Button("Open") {}
                        .buttonStyle(.aviProminent)
                    Button("Dismiss") {}
                        .buttonStyle(AviPopupButtonStyle(size: .small))
                }
            }
            defer { fixture.close() }

            XCTAssertTrue(fixture.keyButtons().isEmpty)
        }
    }

    func testKeyButtonStaysOutOfTheWay() throws {
        try MainActor.assumeIsolated {
            let fixture = Fixture {
                Button("Push") {}
                    .buttonStyle(.aviProminent)
                    .aviKeyboardShortcut(.defaultAction)
            }
            defer { fixture.close() }

            let key = try XCTUnwrap(fixture.keyButton(for: "\r"))
            XCTAssertTrue(key.isTransparent, "draws nothing over the pill")
            XCTAssertTrue(key.refusesFirstResponder, "Tab never lands on it")
            XCTAssertFalse(key.isAccessibilityElement(), "VoiceOver reads the pill, not this")
            XCTAssertNil(key.hitTest(NSPoint(x: key.bounds.midX, y: key.bounds.midY)), "clicks go to the pill")
        }
    }

    @MainActor
    private final class Presses {
        var count = 0
        var cancelled = 0
    }

    /// Hosts `content` in a window that never goes on screen.
    @MainActor
    private final class Fixture {
        let window: NSWindow

        init(@ViewBuilder content: () -> some View) {
            _ = NSApplication.shared
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: content().padding(20))
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }

        func keyButtons() -> [NSButton] {
            guard let content = window.contentView else { return [] }
            return buttons(in: content).filter { !$0.keyEquivalent.isEmpty }
        }

        func keyButton(for key: String) -> NSButton? {
            keyButtons().first { $0.keyEquivalent == key }
        }

        private func buttons(in view: NSView) -> [NSButton] {
            var found = (view as? NSButton).map { [$0] } ?? []
            for subview in view.subviews {
                found += buttons(in: subview)
            }
            return found
        }

        func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code
            )!
        }

        func close() {
            window.close()
        }
    }
}
