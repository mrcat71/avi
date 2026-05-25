import AppKit
import AppUI
import GitKit
import SwiftUI

/// Dispatches between the SwiftUI app and CI-only diagnostic flags before
/// `NSApplication.run()` takes over. `--version` and `--self-test` are used by
/// the release pipeline; everything else falls through to the normal app.
@main
enum AviAppMain {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--version") {
            print(GitKit.version)
            exit(0)
        }
        if args.contains("--self-test") {
            runSelfTest()
            exit(0)
        }
        AviApp.main()
    }

    private static func runSelfTest() {
        // ConfigStore.shared and RepositoryStore are @MainActor-isolated.
        // main() runs synchronously on the main thread before SwiftUI takes
        // over, so assuming isolation here is safe.
        MainActor.assumeIsolated {
            _ = ConfigStore.shared
            let store = RepositoryStore()
            _ = store.id
        }
        print("ok")
    }
}

/// Minimal runnable shell so the UI can be launched with `swift run AviApp`
/// (no Xcode project needed for development). A distributable .app bundle is
/// produced from the Xcode shell later.
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
            CommandGroup(replacing: .appInfo) {
                Button("About Avi") {
                    showAboutPanel()
                }
            }
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
    func applicationDidFinishLaunching(_: Notification) {
        // A CLI-launched process is an accessory by default; promote it to a
        // normal foreground app so the window appears and takes focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Register customisable keyboard shortcuts. No-op when the
        // KeyboardShortcuts library isn't linked (bare-CLI build).
        AviShortcuts.registerAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

/// Custom About panel: replaces the app-icon thumbnail with the wordmark when
/// the resource is bundled. Falls back to the default about panel in dev runs
/// where the wordmark isn't present.
@MainActor
private func showAboutPanel() {
    var options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationVersion: GitKit.version,
        .version: GitKit.version
    ]
    if let wordmark = Branding.wordmarkNSImage {
        options[.applicationIcon] = wordmark
    }
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: options)
}
