import GitKit
import SwiftUI

/// Settings > External Tools > Merge tool: which app opens a conflicted file
/// from Changes. Avi resolves conflicts by itself too; this is for when you
/// want a three-way merge in your own tool.
struct MergeToolRow: View {
    @Bindable var store: ConfigStore

    /// Where each preset found on this Mac is, by id, once looked up.
    @State private var paths: [String: String]?
    /// Git's own `merge.tool`, for the default choice's label.
    @State private var gitMergeTool: String?

    var body: some View {
        SettingsFormRow("Merge tool", description: "For Merge Tool on a conflicted file in Changes.") {
            SettingsPopupMenu("Merge tool", selection: binding(\.mergeTool), items: items, fallbackTitle: store.config.externalTools.mergeTool)
        } detail: {
            detail
                .padding(.top, 6)
        }
        .task {
            await load()
        }
    }

    private var items: [SettingsPopupMenu<String>.Item] {
        [.option("", gitDefaultLabel), .divider]
            + choices.map { .option($0.id, isInstalled($0) ? $0.name : "\($0.name) (not found)") }
            + [.divider, .option(MergeToolCatalog.customID, "Custom Command")]
    }

    @ViewBuilder
    private var detail: some View {
        let selected = store.config.externalTools.mergeTool
        if selected == MergeToolCatalog.customID {
            VStack(alignment: .leading, spacing: 4) {
                SettingsTextField(
                    "Merge command",
                    text: binding(\.mergeToolCommand),
                    prompt: #"'/path/to/tool' "$LOCAL" "$REMOTE" "$BASE" "$MERGED""#,
                    monospaced: true,
                    maxWidth: 420
                )
                note("A shell command. $LOCAL is Current's version, $REMOTE Incoming's, $BASE their common ancestor, "
                    + "and $MERGED the file to write. Avi waits for it to exit, and Git marks the file resolved if $MERGED changed.")
            }
        } else if let preset = MergeToolCatalog.preset(id: selected) {
            VStack(alignment: .leading, spacing: 4) {
                if let path = paths?[preset.id] {
                    note("Found at \(path)")
                } else if paths != nil {
                    note("Not found where Avi looks. Set its path below.")
                }
                SettingsTextField("Merge tool path", text: binding(\.mergeToolPath), prompt: "Path to use instead", monospaced: true, maxWidth: 420)
            }
        } else {
            note(gitMergeTool == nil
                ? "Git's merge.tool is not set, so Git uses the first tool it finds, such as FileMerge."
                : "Uses the merge tool your Git config names.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 420, alignment: .leading)
    }

    private var gitDefaultLabel: String {
        gitMergeTool.map { "Git's merge.tool (\($0))" } ?? "Git's merge.tool"
    }

    /// Installed tools, plus the chosen one if it is not, so the choice shows.
    private var choices: [MergeToolPreset] {
        let selected = store.config.externalTools.mergeTool
        let found = MergeToolCatalog.presets.filter(isInstalled)
        guard let chosen = MergeToolCatalog.preset(id: selected), !found.contains(chosen) else { return found }
        return found + [chosen]
    }

    private func isInstalled(_ preset: MergeToolPreset) -> Bool {
        paths?[preset.id] != nil
    }

    private func binding(_ key: WritableKeyPath<ExternalToolsConfig, String>) -> Binding<String> {
        Binding(
            get: { store.config.externalTools[keyPath: key] },
            set: { value in store.update { $0.externalTools[keyPath: key] = value } }
        )
    }

    private func load() async {
        paths = await Task.detached(priority: .userInitiated) {
            MergeToolCatalog.presets.reduce(into: [String: String]()) { found, preset in
                found[preset.id] = MergeToolCatalog.executable(of: preset)
            }
        }.value
        let git = GitCommandOptions.invocation(["config", "--global", "--get", "merge.tool"])
        let result = try? await ProcessRunner.run(
            executable: git.executable,
            arguments: git.arguments,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        let value = result.flatMap { $0.exitCode == 0 ? $0.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
        gitMergeTool = value?.isEmpty == false ? value : nil
    }
}
