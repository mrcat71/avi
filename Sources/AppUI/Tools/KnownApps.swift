import AppKit
import Foundation

/// An app Settings offers for Open in Editor or Open in Terminal.
struct KnownApp: Equatable, Sendable {
    let bundleID: String
    let name: String
}

/// The editors and terminals Settings > External Tools lists when they are
/// installed, in the order Avi prefers them.
enum KnownApps {
    static let editors: [KnownApp] = [
        KnownApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        KnownApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        KnownApp(bundleID: "dev.zed.Zed", name: "Zed"),
        KnownApp(bundleID: "com.exafunction.windsurf", name: "Windsurf"),
        KnownApp(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        KnownApp(bundleID: "com.panic.Nova", name: "Nova"),
        KnownApp(bundleID: "com.barebones.bbedit", name: "BBEdit"),
        KnownApp(bundleID: "com.jetbrains.goland", name: "GoLand"),
        KnownApp(bundleID: "com.jetbrains.intellij", name: "IntelliJ IDEA"),
        KnownApp(bundleID: "com.jetbrains.intellij.ce", name: "IntelliJ IDEA CE"),
        KnownApp(bundleID: "com.jetbrains.pycharm", name: "PyCharm"),
        KnownApp(bundleID: "com.jetbrains.pycharm.ce", name: "PyCharm CE"),
        KnownApp(bundleID: "com.jetbrains.WebStorm", name: "WebStorm"),
        KnownApp(bundleID: "com.jetbrains.rustrover", name: "RustRover"),
        KnownApp(bundleID: "com.jetbrains.CLion", name: "CLion"),
        KnownApp(bundleID: "com.jetbrains.rider", name: "Rider"),
        KnownApp(bundleID: "com.jetbrains.PhpStorm", name: "PhpStorm"),
        KnownApp(bundleID: "com.jetbrains.rubymine", name: "RubyMine"),
        KnownApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")
    ]

    /// Automatic never picks Xcode, which opens a folder as a project.
    static let automaticEditors = editors.filter { $0.bundleID != "com.apple.dt.Xcode" }

    /// Terminals that start in a folder they are asked to open.
    static let terminals: [KnownApp] = [
        KnownApp(bundleID: "com.apple.Terminal", name: "Terminal"),
        KnownApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        KnownApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        KnownApp(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        KnownApp(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        KnownApp(bundleID: "com.superlogical.rex", name: "Rex")
    ]

    /// Where an app is installed, by bundle id.
    typealias Locate = @Sendable (String) -> URL?

    static let locateInstalled: Locate = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }

    /// The apps of `list` that are installed, with where they are.
    static func installed(_ list: [KnownApp], locate: Locate = locateInstalled) -> [(app: KnownApp, url: URL)] {
        list.compactMap { app in locate(app.bundleID).map { (app, $0) } }
    }

    /// An app's name as Finder shows it, without `.app`.
    static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// What Open in Editor opens with: an app, or a command such as `code` that
/// gets the folder or file as its argument.
enum EditorTarget: Equatable {
    case app(URL)
    case command(URL)

    var name: String {
        switch self {
        case let .app(url): return KnownApps.displayName(of: url)
        case let .command(url): return url.lastPathComponent
        }
    }

    /// The editor for Settings' `git.externalEditor`: the app or command it
    /// names, or with none the first installed editor Avi knows. Nil when it
    /// names nothing usable or no editor is installed.
    static func resolve(configured: String, locate: KnownApps.Locate = KnownApps.locateInstalled) -> EditorTarget? {
        let path = (configured.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty else {
            // Stops at the first one: menus ask for it each time they open.
            for app in KnownApps.automaticEditors {
                if let url = locate(app.bundleID) {
                    return .app(url)
                }
            }
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return .app(URL(fileURLWithPath: path, isDirectory: true))
        }
        return FileManager.default.isExecutableFile(atPath: path) ? .command(URL(fileURLWithPath: path)) : nil
    }
}
