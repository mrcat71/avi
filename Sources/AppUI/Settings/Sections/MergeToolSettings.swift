import GitKit
import SwiftUI

/// Settings > External Tools > Merge Tool: which app opens a conflicted file
/// from Changes. Avi resolves conflicts by itself too; this is for when you
/// want a three-way merge in your own tool.
struct MergeToolSettings: View {
    @Bindable var store: ConfigStore

    /// Where each preset found on this Mac is, by id, once looked up.
    @State private var paths: [String: String]?
    /// Git's own `merge.tool`, for the default choice's label.
    @State private var gitMergeTool: String?

    var body: some View {
        SettingsGroup("Merge Tool") {
            SettingsFormRow("Open conflicts in", description: "For Merge Tool in Changes") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Merge tool", selection: choice) {
                        Text(gitDefaultLabel).tag("")
                        Divider()
                        ForEach(choices) { preset in
                            Text(isInstalled(preset) ? preset.name : "\(preset.name) (not found)").tag(preset.id)
                        }
                        Divider()
                        Text("Custom Command").tag(MergeToolCatalog.customID)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)

                    detail
                }
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var detail: some View {
        let selected = store.config.externalTools.mergeTool
        if selected == MergeToolCatalog.customID {
            TextField(#"'/path/to/tool' "$LOCAL" "$REMOTE" "$BASE" "$MERGED""#, text: binding(\.mergeToolCommand))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 420)
            note("A shell command. $LOCAL is Current's version, $REMOTE Incoming's, $BASE their common ancestor, and $MERGED the file to write. "
                + "Avi waits for it to exit, and Git marks the file resolved if $MERGED changed.")
        } else if let preset = MergeToolCatalog.preset(id: selected) {
            if let path = paths?[preset.id] {
                note("Found at \(path)")
            } else if paths != nil {
                note("Not found where Avi looks. Set its path below.")
            }
            TextField("Override path…", text: binding(\.mergeToolPath))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: 420)
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

    private var choice: Binding<String> {
        binding(\.mergeTool)
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result = try? await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "config", "--global", "--get", "merge.tool"],
            workingDirectory: home
        )
        let value = result.flatMap { $0.exitCode == 0 ? $0.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
        gitMergeTool = value?.isEmpty == false ? value : nil
    }
}
