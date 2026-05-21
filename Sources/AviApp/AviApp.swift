import AppKit
import AppUI
import SwiftUI

/// Minimal runnable shell so the UI can be launched with `swift run AviApp`
/// (no Xcode project needed for development). A distributable .app bundle is
/// produced from the Xcode shell later.
@main
struct AviApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }

        Settings {
            SettingsRoot()
        }
        .commands {
            CommandMenu("Repository") {
                Button("Open Repository...") {
                    NotificationCenter.default.post(name: .aviOpenRepository, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                Button("Refresh") {
                    NotificationCenter.default.post(name: .aviRefreshRepository, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Stage All") {
                    NotificationCenter.default.post(name: .aviStageAll, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Unstage All") {
                    NotificationCenter.default.post(name: .aviUnstageAll, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Commit") {
                    NotificationCenter.default.post(name: .aviCommit, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Divider()

                Button("Fetch") {
                    NotificationCenter.default.post(name: .aviFetchRepository, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Pull") {
                    NotificationCenter.default.post(name: .aviPullRepository, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Push") {
                    NotificationCenter.default.post(name: .aviPushRepository, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }

            CommandMenu("View") {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .aviOpenCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Command Palette (alt)") {
                    NotificationCenter.default.post(name: .aviOpenCommandPalette, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Go to Local Changes") {
                    NotificationCenter.default.post(name: .aviGoToLocalChanges, object: nil)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Go to All Commits") {
                    NotificationCenter.default.post(name: .aviGoToAllCommits, object: nil)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button("Toggle History Scope") {
                    NotificationCenter.default.post(name: .aviToggleHistoryScope, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A CLI-launched process is an accessory by default; promote it to a
        // normal foreground app so the window appears and takes focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
