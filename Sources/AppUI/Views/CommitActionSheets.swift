import GitKit
import SwiftUI

/// What History's commit menu can do with a commit.
enum CommitMenuAction {
    case newBranch
    case newTag
    case interactiveRebase
    case editCommit
    case reset
    case checkout
    case cherryPick
    case revert
    case savePatch
    case compare
    case copySHA
    case copyShortSHA
    case copySubject
}

/// "Reset '<branch>' to Here…": the three modes Git has, with what each keeps.
struct ResetToCommitSheet: View {
    let store: RepositoryStore
    let commit: CommitSummary

    @Environment(\.dismiss) private var dismiss
    @State private var mode: GitResetMode = .mixed

    var body: some View {
        AviPopup(
            symbol: "arrow.uturn.backward",
            tint: mode == .hard ? DS.Palette.danger : DS.Palette.accent,
            title: "Reset \(target) to \(commit.shortOID)",
            subtitle: commit.subject.isEmpty ? "(no subject)" : commit.subject,
            width: 460
        ) {
            AviPopupField("Mode") {
                Picker("Mode", selection: $mode) {
                    Text("Soft").tag(GitResetMode.soft)
                    Text("Mixed").tag(GitResetMode.mixed)
                    Text("Hard").tag(GitResetMode.hard)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            AviPopupCallout(explanation, tone: mode == .hard ? .danger : .info)
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .keyboardShortcut(.cancelAction)
            Button(mode == .hard ? "Reset and Discard Changes" : "Reset", role: mode == .hard ? .destructive : nil) {
                let mode = mode
                dismiss()
                Task { await store.reset(to: commit, mode: mode) }
            }
            .buttonStyle(.aviProminent)
        }
        .animation(Glass.Motion.snappy, value: mode)
    }

    private var target: String {
        store.branch.flatMap { $0.isDetached ? nil : $0.name }.map { "'\($0)'" } ?? "HEAD"
    }

    private var explanation: String {
        switch mode {
        case .soft:
            return "Moves \(target) only. The changes of the commits after it stay staged, ready to commit again."
        case .mixed:
            return "Moves \(target) and unstages everything. The changes of the commits after it, and your own, stay in the working tree."
        case .hard:
            return "Moves \(target) and makes the working tree match the commit. Uncommitted changes and the commits after it are gone from \(target)."
        }
    }
}

/// "Compare to Local Changes": every file that differs between the commit and
/// the working tree, with its diff.
struct CompareWithWorkingTreeSheet: View {
    let store: RepositoryStore
    let commit: CommitSummary

    @Environment(\.dismiss) private var dismiss
    @State private var files: [CommitFileChange] = []
    @State private var selection: String?
    @State private var diff: FileDiff?
    @State private var diffError: String?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            AviPopupHeader(
                symbol: "arrow.left.arrow.right",
                title: "\(commit.shortOID) compared to local changes",
                subtitle: commit.subject.isEmpty ? "(no subject)" : commit.subject
            ) {
                Button("Done") { dismiss() }
                    .buttonStyle(.aviSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            Divider()
            content
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 560, idealHeight: 700)
        .task(load)
        .task(id: selection) { await loadDiff() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            ContentUnavailableView("Cannot Compare", systemImage: "exclamationmark.triangle", description: Text(loadError))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            ContentUnavailableView(
                "No Differences",
                systemImage: "checkmark.circle",
                description: Text("The working tree matches \(commit.shortOID).")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                List(selection: $selection) {
                    ForEach(files) { file in
                        CommitFileRow(file: file)
                            .tag(file.path)
                    }
                }
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 380)

                Group {
                    if let file = files.first(where: { $0.path == selection }) {
                        FileDiffView(title: file.displayPath, diff: diff, errorMessage: diffError) {
                            await loadDiff()
                        }
                    } else {
                        ContentUnavailableView("No File Selected", systemImage: "doc.text")
                    }
                }
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @Sendable
    private func load() async {
        do {
            files = try await store.changedFilesAgainstWorkingTree(from: commit.oid)
            selection = files.first?.path
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func loadDiff() async {
        guard let file = files.first(where: { $0.path == selection }) else {
            diff = nil
            return
        }
        do {
            diff = try await store.diffAgainstWorkingTree(from: commit.oid, file: file)
            diffError = nil
        } catch {
            diff = nil
            diffError = error.localizedDescription
        }
    }
}
