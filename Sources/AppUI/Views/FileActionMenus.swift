import AppKit
import GitKit
import SwiftUI
import UniformTypeIdentifiers

/// "Open With": the apps that can open the file, its default app first.
struct OpenWithMenu: View {
    let store: RepositoryStore
    let file: FileStatus

    var body: some View {
        Menu("Open With") {
            let apps = applications
            ForEach(apps, id: \.self) { app in
                Button {
                    store.open(file, withApplicationAt: app)
                } label: {
                    Label {
                        Text(app == defaultApplication ? "\(name(of: app)) (default)" : name(of: app))
                    } icon: {
                        Image(nsImage: icon(of: app))
                    }
                }
            }
            if !apps.isEmpty {
                Divider()
            }
            Button("Other…", action: chooseApplication)
        }
    }

    private var fileURL: URL? {
        store.absoluteURL(for: file)
    }

    private var defaultApplication: URL? {
        fileURL.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    private var applications: [URL] {
        guard let fileURL else { return [] }
        let others = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            .filter { $0 != defaultApplication }
            .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
        var seen = Set<String>()
        return ([defaultApplication].compactMap(\.self) + others).filter { seen.insert(name(of: $0)).inserted }
    }

    private func name(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    private func icon(of app: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: app.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App to Open \((file.path as NSString).lastPathComponent)"
        panel.prompt = "Open"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let app = panel.url {
            store.open(file, withApplicationAt: app)
        }
    }
}

/// "Ignore": patterns for the file, its extension, or a folder above it,
/// added to `.gitignore` or, under Ignore Locally, to `.git/info/exclude`.
struct IgnoreMenu: View {
    let store: RepositoryStore
    let files: [FileStatus]

    var body: some View {
        Menu("Ignore") {
            choices(locally: false)
            Divider()
            Menu("Ignore Locally") {
                Text("In .git/info/exclude, never committed")
                choices(locally: true)
            }
            if files.contains(where: { !$0.isUntracked }) {
                Divider()
                Text("Git keeps tracking files it already tracks")
            }
        }
    }

    @ViewBuilder
    private func choices(locally: Bool) -> some View {
        if files.count == 1, let file = files.first {
            if let pattern = try? GitIgnore.pattern(forPath: file.path, isDirectory: false) {
                Button("Ignore '\((file.path as NSString).lastPathComponent)'") { add([pattern], locally: locally) }
            }
            if let pattern = GitIgnore.extensionPattern(forPath: file.path) {
                Button("Ignore All '\(pattern)' Files") { add([pattern], locally: locally) }
            }
            ForEach(GitIgnore.parentFolders(of: file.path), id: \.self) { folder in
                if let pattern = try? GitIgnore.pattern(forPath: folder, isDirectory: true) {
                    Button("Ignore Folder '\(folder)/'") { add([pattern], locally: locally) }
                }
            }
        } else {
            let patterns = files.compactMap { try? GitIgnore.pattern(forPath: $0.path, isDirectory: false) }
            Button("Ignore \(files.count) Files") { add(patterns, locally: locally) }
                .disabled(patterns.isEmpty)
            if let shared = sharedExtensionPattern {
                Button("Ignore All '\(shared)' Files") { add([shared], locally: locally) }
            }
        }
    }

    /// `*.ext` when every chosen file has the same extension.
    private var sharedExtensionPattern: String? {
        let patterns = Set(files.map { GitIgnore.extensionPattern(forPath: $0.path) })
        guard patterns.count == 1, let pattern = patterns.first else { return nil }
        return pattern
    }

    private func add(_ patterns: [String], locally: Bool) {
        Task {
            for pattern in patterns {
                await store.ignore(pattern: pattern, locally: locally)
            }
        }
    }
}

/// "Stash N Files…": a message for the stash, then only those files go.
struct StashFilesSheet: View {
    let store: RepositoryStore
    let request: FileStashRequest

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.files.count == 1 ? "Stash 1 File" : "Stash \(request.files.count) Files")
                .font(.system(size: 14, weight: .semibold))
            Text("Saves the staged and unstaged changes of \(request.files.count == 1 ? "this file" : "these files") in a new stash and removes them from the working tree. Everything else stays as it is.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(fileList)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .truncationMode(.middle)
            TextField("Message (optional)", text: $message)
                .textFieldStyle(.roundedBorder)
                .onSubmit(stash)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Stash", action: stash)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private var fileList: String {
        let shown = request.files.prefix(5).map(\.path).joined(separator: "\n")
        let hidden = request.files.count - min(request.files.count, 5)
        return hidden > 0 ? "\(shown)\nand \(hidden) more" : shown
    }

    private func stash() {
        let files = request.files
        let text = message
        dismiss()
        Task { await store.stash(files, message: text) }
    }
}

/// "Save as Patch…": asks where, then writes the patch there.
@MainActor
enum PatchSaver {
    static func save(_ files: [FileStatus], staged: Bool, store: RepositoryStore) {
        guard !files.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Save as Patch"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .plainText]
        panel.nameFieldStringValue = files.count == 1
            ? "\((files[0].path as NSString).lastPathComponent).patch"
            : "\(store.root?.lastPathComponent ?? "changes").patch"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await store.savePatch(for: files, staged: staged, to: url) }
        }
    }
}
