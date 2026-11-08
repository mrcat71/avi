import AppKit
@testable import AppUI
import Foundation
import Testing

/// The parts of Settings that reach the rest of Avi: prompts, clone
/// destinations, the editor, tool paths, and Git's global identity.
struct SettingsWiringTests {
    private func context(conventional: Bool) -> PromptContext {
        PromptContext(
            stagedDiff: "", branch: "", files: [], repo: "", model: "",
            lowLimit: 50, highLimit: 72, guideLine: 72,
            conventionalCommits: conventional
        )
    }

    @Test(arguments: [true, false])
    func styleFollowsTheConventionalCommitsSwitch(conventional: Bool) {
        let rendered = PromptRenderer.render(template: AIConfig.defaultPromptTemplate, context: context(conventional: conventional))
        #expect(rendered.contains("Conventional Commits") == conventional)
        #expect(rendered.contains("no type or scope prefix") == !conventional)
        #expect(!rendered.contains("${style}"))
    }

    @Test func everyBuiltInPromptAsksForTheStyle() {
        for template in PromptKind.allCases.map(\.defaultTemplate) {
            #expect(template.contains("${style}"))
        }
    }

    @Test func cloneDestinationsAreRememberedPerHostWhileTheFolderExists() throws {
        let suite = "avi-tests-clone-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("avi-clone-dest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let destinations = CloneDestinations(defaults: defaults)
        #expect(destinations.folder(for: "gitlab.example.com") == nil)
        destinations.remember(folder, for: "GitLab.Example.com")
        #expect(destinations.folder(for: "gitlab.example.com") == folder.path)
        #expect(destinations.folder(for: "github.com") == nil)
        #expect(destinations.folder(for: nil) == nil)

        try FileManager.default.removeItem(at: folder)
        #expect(destinations.folder(for: "gitlab.example.com") == nil, "a folder that is gone is not offered")
    }

    @Test func automaticEditorIsTheFirstInstalledOneButNeverXcode() {
        let cursor = URL(fileURLWithPath: "/Applications/Cursor.app")
        let installed: [String: URL] = [
            "com.apple.dt.Xcode": URL(fileURLWithPath: "/Applications/Xcode.app"),
            "com.todesktop.230313mzl4w4u92": cursor
        ]
        #expect(EditorTarget.resolve(configured: "", locate: { installed[$0] }) == .app(cursor))
        #expect(EditorTarget.resolve(configured: "  ", locate: { _ in nil }) == nil)
        #expect(EditorTarget.resolve(configured: "", locate: { $0 == "com.apple.dt.Xcode" ? URL(fileURLWithPath: "/Applications/Xcode.app") : nil }) == nil)
    }

    @Test func aChosenEditorIsAnAppOrACommand() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Avi Test Editor \(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }

        #expect(EditorTarget.resolve(configured: app.path, locate: { _ in nil }) == .app(URL(fileURLWithPath: app.path, isDirectory: true)))
        #expect(EditorTarget.resolve(configured: "/bin/echo", locate: { _ in nil }) == .command(URL(fileURLWithPath: "/bin/echo")))
        #expect(EditorTarget.resolve(configured: "/no/such/editor", locate: { _ in nil }) == nil)
        #expect(EditorTarget.app(app).name.hasPrefix("Avi Test Editor"))
        #expect(EditorTarget.command(URL(fileURLWithPath: "/usr/local/bin/code")).name == "code")
    }

    @Test(arguments: [
        ("", nil as String?, nil as String?),
        ("/bin/echo", "/bin/echo", nil),
        ("/no/such/tool", nil, "Nothing at this path"),
        ("/etc/hosts", nil, "Not an executable file")
    ])
    func toolPathsMustBeExecutables(text: String, executable: String?, problem: String?) {
        #expect(ToolPath.executable(text) == executable)
        #expect(ToolPath.problem(text) == problem)
    }

    @Test func gitsGlobalIdentityIsReadFromItsConfig() {
        let settings = GitGlobalSettings.parse("user.name Andrey Svinarenko\nuser.email a@example.com\ncommit.gpgsign true\n")
        #expect(settings.name == "Andrey Svinarenko")
        #expect(settings.email == "a@example.com")
        #expect(settings.signsCommits)
        #expect(GitGlobalSettings.parse("commit.gpgsign false\n") == GitGlobalSettings(name: nil, email: nil, signsCommits: false))
    }

    @MainActor
    @Test func settingsMenusTickTheChoiceAndRunTheirActions() {
        // A menu item's action goes through the app.
        _ = NSApplication.shared
        var chosen: [Int] = []
        var acted = false
        let items: [SettingsPopupMenu<Int>.Item] = [
            .option(0, "Off"), .divider, .option(5, "Every 5 minutes"), .action("Choose…") { acted = true }
        ]
        let menu = SettingsPopupMenu<Int>.menu(items: items, selection: 5) { chosen.append($0) }
        #expect(menu.items.map(\.title) == ["Off", "", "Every 5 minutes", "Choose…"])
        #expect(menu.items.map(\.state) == [.off, .off, .on, .off])
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 3)
        #expect(chosen == [0])
        #expect(acted)
        #expect(SettingsPopupMenu<Int>.title(of: 7, in: items) == nil)
    }

    @Test func accountsSayWhenTheirTokenWasLastChecked() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var account = ProviderAccount(kind: "gitlab", instanceURL: "https://gitlab.example.com", username: "andrei", keychainItem: "k")
        #expect(ProviderAccountRows.description(of: account, now: now) == "https://gitlab.example.com · Not checked yet")
        account.lastValidatedISO = ISO8601DateFormatter().string(from: now.addingTimeInterval(-2 * 86400))
        #expect(ProviderAccountRows.description(of: account, now: now) == "https://gitlab.example.com · Checked 2 days ago")
    }
}
