import AppKit
import Foundation
import GitKit

/// A merge tool Avi can open a conflicted file in. Git runs it through
/// `git mergetool`: by Git's own name for the tools Git knows, which keeps
/// Git's arguments for them, and through a command of ours for the rest.
struct MergeToolPreset: Identifiable, Equatable, Sendable {
    enum Launch: Equatable, Sendable {
        /// A tool Git knows by this name. Avi only tells Git where it is.
        case git(String)
        /// What follows the executable, using `$BASE`, `$LOCAL`, `$REMOTE`,
        /// and `$MERGED`; and whether its exit status says if it merged.
        case command(arguments: String, trustExitCode: Bool)
    }

    /// An app that carries the tool, and the executable inside it.
    struct Bundle: Equatable, Sendable {
        let id: String
        let executable: String
    }

    let id: String
    let name: String
    let launch: Launch
    let bundles: [Bundle]
    /// Absolute paths a command-line install puts it at.
    var paths: [String] = []
}

enum MergeToolCatalog {
    /// `externalTools.mergeTool` value for a command you write yourself.
    static let customID = "custom"

    /// JetBrains IDEs merge with `<ide> merge local remote base output`. Git
    /// writes the three versions to a temporary folder, so only the output,
    /// relative to the repository, needs an absolute path for the IDE.
    private static func jetBrains(_ id: String, _ name: String, _ bundles: [String], executable: String) -> MergeToolPreset {
        MergeToolPreset(
            id: id,
            name: name,
            launch: .command(arguments: #"merge "$LOCAL" "$REMOTE" "$BASE" "$PWD/$MERGED""#, trustExitCode: false),
            bundles: bundles.map { MergeToolPreset.Bundle(id: $0, executable: "Contents/MacOS/\(executable)") }
        )
    }

    static let presets: [MergeToolPreset] = [
        MergeToolPreset(
            id: "filemerge", name: "FileMerge", launch: .git("opendiff"),
            bundles: [.init(id: "com.apple.FileMerge", executable: "")]
        ),
        MergeToolPreset(
            id: "vscode", name: "Visual Studio Code", launch: .git("vscode"),
            bundles: [.init(id: "com.microsoft.VSCode", executable: "Contents/Resources/app/bin/code")]
        ),
        MergeToolPreset(
            id: "cursor", name: "Cursor",
            launch: .command(arguments: #"--wait --merge "$REMOTE" "$LOCAL" "$BASE" "$MERGED""#, trustExitCode: false),
            bundles: [.init(id: "com.todesktop.230313mzl4w4u92", executable: "Contents/Resources/app/bin/cursor")]
        ),
        MergeToolPreset(
            id: "smerge", name: "Sublime Merge", launch: .git("smerge"),
            bundles: [.init(id: "com.sublimemerge", executable: "Contents/SharedSupport/bin/smerge")]
        ),
        MergeToolPreset(
            id: "kaleidoscope", name: "Kaleidoscope",
            launch: .command(arguments: #"--merge --output "$MERGED" --base "$BASE" -- "$LOCAL" --snapshot "$REMOTE" --snapshot"#, trustExitCode: true),
            bundles: [
                .init(id: "app.kaleidoscope.v4", executable: "Contents/Resources/bin/ksdiff"),
                .init(id: "com.kaleidoscopeapp.v3", executable: "Contents/Resources/bin/ksdiff")
            ],
            paths: ["/usr/local/bin/ksdiff", "/opt/homebrew/bin/ksdiff"]
        ),
        MergeToolPreset(
            id: "bc", name: "Beyond Compare", launch: .git("bc"),
            bundles: [.init(id: "com.ScooterSoftware.BeyondCompare", executable: "Contents/MacOS/bcomp")],
            paths: ["/usr/local/bin/bcomp", "/opt/homebrew/bin/bcomp"]
        ),
        MergeToolPreset(
            id: "p4merge", name: "P4Merge", launch: .git("p4merge"),
            bundles: [.init(id: "com.perforce.p4merge", executable: "Contents/MacOS/p4merge")]
        ),
        MergeToolPreset(
            id: "meld", name: "Meld", launch: .git("meld"),
            bundles: [.init(id: "org.gnome.meld", executable: "Contents/MacOS/Meld")],
            paths: ["/opt/homebrew/bin/meld", "/usr/local/bin/meld"]
        ),
        MergeToolPreset(
            id: "kdiff3", name: "KDiff3", launch: .git("kdiff3"),
            bundles: [.init(id: "org.kde.kdiff3", executable: "Contents/MacOS/kdiff3")],
            paths: ["/opt/homebrew/bin/kdiff3", "/usr/local/bin/kdiff3"]
        ),
        jetBrains("goland", "GoLand", ["com.jetbrains.goland"], executable: "goland"),
        jetBrains("idea", "IntelliJ IDEA", ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], executable: "idea"),
        jetBrains("pycharm", "PyCharm", ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], executable: "pycharm"),
        jetBrains("webstorm", "WebStorm", ["com.jetbrains.WebStorm"], executable: "webstorm"),
        jetBrains("phpstorm", "PhpStorm", ["com.jetbrains.PhpStorm"], executable: "phpstorm"),
        jetBrains("rubymine", "RubyMine", ["com.jetbrains.rubymine"], executable: "rubymine"),
        jetBrains("clion", "CLion", ["com.jetbrains.CLion"], executable: "clion"),
        jetBrains("rider", "Rider", ["com.jetbrains.rider"], executable: "rider"),
        jetBrains("rustrover", "RustRover", ["com.jetbrains.rustrover"], executable: "rustrover")
    ]

    static func preset(id: String) -> MergeToolPreset? {
        presets.first { $0.id == id }
    }

    /// The preset's executable on this Mac, or nil when it is not installed.
    /// FileMerge runs through `/usr/bin/opendiff`, which needs Xcode.
    static func executable(of preset: MergeToolPreset, fileManager: FileManager = .default) -> String? {
        for bundle in preset.bundles {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle.id) else { continue }
            let path = bundle.executable.isEmpty ? "/usr/bin/opendiff" : app.appendingPathComponent(bundle.executable).path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return preset.paths.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Why a configured tool cannot start.
    struct Unavailable: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    /// How `git mergetool` runs the tool `config` names; nil leaves the
    /// choice to Git's `merge.tool`.
    static func launch(for config: ExternalToolsConfig, executable find: (MergeToolPreset) -> String? = { executable(of: $0) }) throws -> MergeToolLaunch? {
        let id = config.mergeTool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        if id == customID {
            let command = config.mergeToolCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw Unavailable(message: "The custom merge tool has no command. Write one in Settings > External Tools > Merge Tool.")
            }
            return MergeToolLaunch(name: "avi-custom", command: command, trustExitCode: false)
        }
        guard let preset = preset(id: id) else {
            throw Unavailable(message: "Avi does not know the merge tool '\(id)'. Choose another in Settings > External Tools > Merge Tool.")
        }
        let override = config.mergeToolPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = override.isEmpty ? find(preset) : (override as NSString).expandingTildeInPath else {
            throw Unavailable(message: "\(preset.name) is not installed where Avi looks for it. "
                + "Set its path in Settings > External Tools > Merge Tool, or choose another tool.")
        }
        switch preset.launch {
        case let .git(name):
            return MergeToolLaunch(name: name, path: path)
        case let .command(arguments, trustExitCode):
            return MergeToolLaunch(name: "avi-\(preset.id)", command: "\(shellQuoted(path)) \(arguments)", trustExitCode: trustExitCode)
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
