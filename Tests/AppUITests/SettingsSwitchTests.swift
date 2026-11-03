import AppKit
@testable import AppUI
import SwiftUI
import XCTest

final class SettingsSwitchTests: XCTestCase {
    func testCompactDimensionsAndThumbPlacement() throws {
        try MainActor.assumeIsolated {
            for scheme in [ColorScheme.light, .dark] {
                var thumbCenters: [CGFloat] = []
                for isOn in [false, true] {
                    let renderer = ImageRenderer(content:
                        Toggle("Test setting", isOn: .constant(isOn))
                            .labelsHidden()
                            .toggleStyle(SettingsSwitchStyle())
                            .environment(\.colorScheme, scheme)
                            .accentColor(.blue)
                    )
                    renderer.scale = 2
                    let bitmap = try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
                    XCTAssertEqual(bitmap.pixelsWide, 60)
                    XCTAssertEqual(bitmap.pixelsHigh, 48)
                    var thumbPixels: [CGFloat] = []
                    for y in 0 ..< bitmap.pixelsHigh {
                        for x in 0 ..< bitmap.pixelsWide {
                            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                            if color.alphaComponent > 0.9, color.redComponent > 0.95,
                               color.greenComponent > 0.95, color.blueComponent > 0.95 {
                                thumbPixels.append(CGFloat(x))
                            }
                        }
                    }
                    XCTAssertFalse(thumbPixels.isEmpty)
                    thumbCenters.append(thumbPixels.reduce(0, +) / CGFloat(max(1, thumbPixels.count)))
                }
                XCTAssertEqual(thumbCenters[1] - thumbCenters[0], 24, accuracy: 1)
            }
        }
    }

    func testClickUpdatesTheBindingAndDisabledClickDoesNot() throws {
        try XCTSkipUnless(OnScreenTests.enabled, OnScreenTests.skipMessage)
        MainActor.assumeIsolated {
            for disabled in [false, true] {
                let fixture = Fixture(disabled: disabled)
                defer { fixture.close() }
                fixture.click()
                XCTAssertEqual(fixture.state.isOn, !disabled)
                XCTAssertEqual(fixture.state.changes, disabled ? 0 : 1)
                fixture.click()
                XCTAssertFalse(fixture.state.isOn)
                XCTAssertEqual(fixture.state.changes, disabled ? 0 : 2)
            }
        }
    }

    func testSpaceTogglesTheFocusedSwitch() throws {
        try XCTSkipUnless(OnScreenTests.enabled, OnScreenTests.skipMessage)
        MainActor.assumeIsolated {
            let fixture = Fixture()
            defer { fixture.close() }
            fixture.window.selectNextKeyView(nil)
            fixture.space()
            XCTAssertTrue(fixture.state.isOn)
            XCTAssertEqual(fixture.state.changes, 1)
        }
    }

    func testAccessibilityKeepsTheLabelAndToggleState() throws {
        try XCTSkipUnless(OnScreenTests.enabled, OnScreenTests.skipMessage)
        try MainActor.assumeIsolated {
            let native = Fixture(native: true)
            let nativeToggle = native.accessibleToggle()
            let nativeRole: String? = nativeToggle.flatMap { native.attribute("accessibilityRole", of: $0) }
            native.close()
            try XCTSkipIf(nativeToggle == nil, "SwiftUI does not expose even native switches to this test host's accessibility tree.")
            let fixture = Fixture()
            defer { fixture.close() }
            let toggle = try XCTUnwrap(fixture.accessibleToggle())
            let role: String? = fixture.attribute("accessibilityRole", of: toggle)
            XCTAssertEqual(role, nativeRole)
            let off: NSNumber? = fixture.attribute("accessibilityValue", of: toggle)
            XCTAssertEqual(off?.intValue, 0)
            fixture.click()
            let on: NSNumber? = fixture.attribute("accessibilityValue", of: toggle)
            XCTAssertEqual(on?.intValue, 1)
        }
    }

    @MainActor
    final class Fixture {
        @Observable final class State {
            var isOn = false
            var changes = 0
        }

        let state = State()
        let host: NSHostingView<AnyView>
        let window: NSWindow
        /// Numbers the clicks: a mouse-down and its mouse-up share a number,
        /// as they do from the window server.
        private var clicks = 0

        init(disabled: Bool = false, native: Bool = false) {
            _ = NSApplication.shared
            let state = state
            let toggle = Toggle("Test setting", isOn: Binding(get: { state.isOn }, set: {
                state.isOn = $0
                state.changes += 1
            }))
            .labelsHidden()
            let control = native ? AnyView(toggle.toggleStyle(.switch)) : AnyView(toggle.toggleStyle(SettingsSwitchStyle()))
            host = NSHostingView(rootView: AnyView(
                control
                    .disabled(disabled)
                    .frame(width: 180, height: 80)
            ))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
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
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
        }

        /// A click delivered the way the window server delivers one: the
        /// mouse-down and its later mouse-up both wait in the event queue, and
        /// NSApp dispatches them in order. A mouse-down that tracks the mouse
        /// finds its mouse-up waiting, so the click cannot hang (see
        /// FolderRowClickTests).
        func click() {
            clicks += 1
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.postEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 90, y: 40), modifierFlags: [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: clicks, clickCount: 1, pressure: 1)!, atStart: false)
            }
            while let next = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: Date(), inMode: .default, dequeue: true) {
                NSApp.sendEvent(next)
            }
            settle()
        }

        func space() {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                                  isARepeat: false, keyCode: 49)!)
            }
            settle()
        }

        func accessibleElements(in element: Any) -> [NSObject] {
            guard let element = element as? NSObject else { return [] }
            let children: [Any] = attribute("accessibilityChildren", of: element) ?? []
            return [element] + children.flatMap { accessibleElements(in: $0) }
        }

        func accessibleToggle() -> NSObject? {
            accessibleElements(in: host).first {
                let label: String? = attribute("accessibilityLabel", of: $0)
                let title: String? = attribute("accessibilityTitle", of: $0)
                return label == "Test setting" || title == "Test setting"
            }
        }

        /// SwiftUI's virtual accessibility nodes implement the selectors without
        /// formally conforming to the full AppKit accessibility protocol.
        func attribute<T>(_ name: String, of element: NSObject) -> T? {
            let selector = NSSelectorFromString(name)
            guard element.responds(to: selector) else { return nil }
            return element.perform(selector)?.takeUnretainedValue() as? T
        }
    }
}
