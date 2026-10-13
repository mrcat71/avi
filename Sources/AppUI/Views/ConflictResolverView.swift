import GitKit
import SwiftUI

/// A conflicted file in place of its diff: each conflict with the lines both
/// sides want and buttons to keep one side or both, plus the whole-file
/// choices: one side's version, the merge tool, or marking it resolved.
struct ConflictResolverView: View {
    let store: RepositoryStore
    let file: FileStatus

    /// Runs of unchanged lines you opened, by segment index.
    @State private var expandedRuns: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let conflict = store.selectedConflict, conflict.path == file.path {
                content(conflict.content)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: file.path) { _, _ in
            expandedRuns = []
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(remaining == 0 ? DS.Palette.success : DS.Palette.warning)
                .accessibilityHidden(true)
            Text(file.path)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(statusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(remaining == 0 ? DS.Palette.success : DS.Palette.warning)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            if !isDeletion {
                Menu("Use Whole File") {
                    Button("\(sideName(.current)): \(labels.current)…") { chooseWholeFile(.current) }
                    Button("\(sideName(.incoming)): \(labels.incoming)…") { chooseWholeFile(.incoming) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Resolve the whole file with one side's version")
                mergeToolButton
            }
            markResolvedButton
        }
        .controlSize(.small)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 28)
    }

    private var mergeToolButton: some View {
        let running = store.mergeToolPaths.contains(file.path)
        return Button {
            store.openMergeTool(for: file)
        } label: {
            if running {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("In Merge Tool")
                }
            } else {
                Text("Merge Tool")
            }
        }
        .disabled(running)
        .help(running ? "Waiting for the merge tool to close" : "Open in \(mergeToolName). Settings > External Tools chooses the tool.")
    }

    private var markResolvedButton: some View {
        Button("Mark as Resolved") {
            Task { await store.markResolved([file]) }
        }
        .buttonStyle(.borderedProminent)
        .tint(remaining == 0 ? DS.Palette.success : DS.Palette.accent)
        .help("Stage the file as it is now, so the merge or rebase can go on")
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ content: SelectedConflict.Content) -> some View {
        switch content {
        case let .text(document):
            VStack(alignment: .leading, spacing: 0) {
                sidesNote
                if document.conflicts.isEmpty {
                    resolvedBanner
                }
                ScrollView {
                    ConflictSegmentsView(document: document, expandedRuns: $expandedRuns) { index, conflict, resolution in
                        Task { await store.resolveConflict(at: index, expected: conflict, with: resolution, in: file) }
                    }
                }
            }
            // Resolving merges segments, so the folded runs' indices move.
            .onChange(of: document.conflicts.count) { _, _ in
                expandedRuns = []
            }
        case .unreadable:
            AviEmptyState(
                icon: "exclamationmark.triangle",
                title: "Avi cannot show these conflicts",
                message: "The file is binary, not UTF-8 text, or its conflict markers do not pair up. Use one side's version, or resolve it in your merge tool.",
                iconTint: DS.Palette.warning
            ) {
                wholeFileButton(.current)
                wholeFileButton(.incoming)
                AviButton("Open in Merge Tool", icon: "arrow.triangle.merge", variant: .secondary, size: .small) {
                    store.openMergeTool(for: file)
                }
                .frame(maxWidth: .infinity)
                .disabled(store.mergeToolPaths.contains(file.path))
            }
        case let .deleted(side):
            deletionChoice(side)
        }
    }

    private func wholeFileButton(_ side: ConflictSide) -> some View {
        AviButton("Use \(sideName(side)) Version…", variant: .secondary, size: .small) {
            chooseWholeFile(side)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func deletionChoice(_ deletedBy: ConflictSide?) -> some View {
        if let deletedBy {
            let kept: ConflictSide = deletedBy == .current ? .incoming : .current
            AviEmptyState(
                icon: "trash",
                title: "Deleted in \(sideName(deletedBy)), changed in \(sideName(kept))",
                message: "Keep the file with \(labels.label(for: kept))'s changes, or delete it as \(labels.label(for: deletedBy)) did.",
                iconTint: DS.Palette.warning
            ) {
                AviButton("Keep \(sideName(kept)) Version…", variant: .secondary, size: .small) {
                    chooseWholeFile(kept)
                }
                .frame(maxWidth: .infinity)
                AviButton("Delete the File…", variant: .destructive, size: .small) {
                    chooseWholeFile(deletedBy)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            AviEmptyState(
                icon: "trash",
                title: "Deleted on both sides",
                message: "Both sides deleted the file. Mark it resolved to delete it.",
                iconTint: DS.Palette.warning
            )
        }
    }

    private var sidesNote: some View {
        Text(ConflictSideLabels.note(for: store.operationState, labels: labels))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
    }

    private var resolvedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DS.Palette.success)
                .accessibilityHidden(true)
            Text("No conflicts left in this file. Check the result below, then mark it resolved.")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DS.Palette.success.opacity(0.10))
    }

    // MARK: - Labels

    private var document: ConflictDocument? {
        guard let conflict = store.selectedConflict, conflict.path == file.path, case let .text(document) = conflict.content else { return nil }
        return document
    }

    private var labels: ConflictSideLabels {
        ConflictSideLabels(first: document?.conflicts.first)
    }

    private var remaining: Int? {
        document?.conflicts.count
    }

    private var isDeletion: Bool {
        guard let conflict = store.selectedConflict, conflict.path == file.path, case .deleted = conflict.content else { return false }
        return true
    }

    private var statusLabel: String {
        switch remaining {
        case 0?: return "Resolved, not marked yet"
        case 1?: return "1 conflict"
        case let count?: return "\(count) conflicts"
        case nil: return "Conflicted"
        }
    }

    private var fileName: String {
        (file.path as NSString).lastPathComponent
    }

    private var mergeToolName: String {
        let tools = ConfigStore.shared.config.externalTools
        if tools.mergeTool == MergeToolCatalog.customID {
            return "your merge tool"
        }
        return MergeToolCatalog.preset(id: tools.mergeTool)?.name ?? "Git's merge tool"
    }

    private func sideName(_ side: ConflictSide) -> String {
        side == .current ? "Current" : "Incoming"
    }

    /// Asks first: the other side's changes and your edits go.
    private func chooseWholeFile(_ side: ConflictSide) {
        store.pendingSideChoice = PendingSideChoice(files: [file], side: side)
    }
}

/// The file's lines between the conflicts and the conflicts themselves, for
/// a scroll view. Long runs of unchanged lines fold down to their context.
struct ConflictSegmentsView: View {
    let document: ConflictDocument
    /// Runs of unchanged lines you opened, by segment index.
    @Binding var expandedRuns: Set<Int>
    /// Resolves the conflict at an index among the conflicts, as you saw it.
    let resolve: (Int, ConflictDocument.Conflict, ConflictDocument.Resolution) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(document.segments.enumerated()), id: \.offset) { index, segment in
                self.segment(segment, at: index)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func segment(_ segment: ConflictDocument.Segment, at index: Int) -> some View {
        switch segment {
        case let .common(lines):
            commonLines(lines, at: index)
        case let .conflict(conflict):
            let number = conflictNumber(at: index)
            ConflictCard(
                conflict: conflict,
                number: number,
                total: document.conflicts.count,
                resolve: { resolution in resolve(number - 1, conflict, resolution) }
            )
        }
    }

    /// Unchanged lines around the conflicts; long runs fold to a few lines of
    /// context on each side. Once no conflict is left, the whole file shows.
    @ViewBuilder
    private func commonLines(_ lines: [String], at index: Int) -> some View {
        let context = 3
        let isFirst = index == 0
        let isLast = index == document.segments.count - 1
        let shown = (isFirst ? 0 : context) + (isLast ? 0 : context)
        if document.conflicts.isEmpty || expandedRuns.contains(index) || lines.count <= shown + 2 {
            CodeLines(lines: lines)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !isFirst {
                    CodeLines(lines: Array(lines.prefix(context)))
                }
                Button {
                    expandedRuns.insert(index)
                } label: {
                    Text("⋯ \(lines.count - shown) unchanged lines")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show these lines")
                if !isLast {
                    CodeLines(lines: Array(lines.suffix(context)))
                }
            }
        }
    }

    private func conflictNumber(at segmentIndex: Int) -> Int {
        document.segments.prefix(segmentIndex + 1).count {
            if case .conflict = $0 {
                return true
            }
            return false
        }
    }
}

/// The words of the dialog that confirms taking one side's whole version.
struct SideChoiceText {
    let title: String
    let message: String
    let button: String

    init(_ choice: PendingSideChoice) {
        let side = choice.side == .current ? "Current" : "Incoming"
        let other = choice.side == .current ? "Incoming" : "Current"
        // For a conflict, X is what HEAD's side did and Y the incoming side.
        let deletes = choice.files.allSatisfy { choice.side == .current ? $0.index == .deleted : $0.worktree == .deleted }
        let name = choice.files.count == 1 ? (choice.files[0].path as NSString).lastPathComponent : "\(choice.files.count) files"
        if deletes {
            title = "Delete \(name)?"
            message = "\(side) deleted \(choice.files.count == 1 ? "it" : "them"), so \(choice.files.count == 1 ? "it is" : "they are") deleted and marked resolved. "
                + "The changes \(other) made are lost."
            button = "Delete"
        } else {
            title = "Use the \(side) version of \(name)?"
            message = "\(choice.files.count == 1 ? "The file becomes" : "Each file becomes") \(side)'s version and is marked resolved. "
                + "\(other)'s changes, and any edits you made, are lost."
            button = "Use \(side) Version"
        }
    }
}

/// What each side of a conflict is, in words, from the labels Git wrote on
/// the markers: `HEAD`, a branch, a commit, or a stash's.
struct ConflictSideLabels: Equatable {
    let current: String
    let incoming: String

    init(first conflict: ConflictDocument.Conflict?) {
        current = conflict.map(\.currentLabel).flatMap { $0.isEmpty ? nil : $0 } ?? "HEAD"
        incoming = conflict.map(\.incomingLabel).flatMap { $0.isEmpty ? nil : $0 } ?? "the incoming change"
    }

    func label(for side: ConflictSide) -> String {
        side == .current ? current : incoming
    }

    /// Which side is which: a rebase turns them around from what you might expect.
    static func note(for operation: GitOperationState?, labels: ConflictSideLabels) -> String {
        switch operation {
        case .merge:
            return "Current is \(labels.current), the branch you are on. Incoming is \(labels.incoming), the branch being merged into it."
        case .rebase:
            return "In a rebase, Current is \(labels.current): the branch you are rebasing onto, with your commits replayed so far. "
                + "Incoming is \(labels.incoming), your commit being replayed."
        case .cherryPick:
            return "Current is \(labels.current), your branch. Incoming is \(labels.incoming), the commit being cherry-picked."
        case .revert:
            return "Current is \(labels.current), your branch. Incoming undoes \(labels.incoming)."
        case nil:
            return "Current is \(labels.current). Incoming is \(labels.incoming)."
        }
    }
}

/// One conflict: Current's lines, the base when Git wrote it, Incoming's
/// lines, and a button for each way to resolve it.
private struct ConflictCard: View {
    let conflict: ConflictDocument.Conflict
    let number: Int
    let total: Int
    let resolve: (ConflictDocument.Resolution) -> Void

    @State private var showsBase = false

    /// Each conflict's own markers: in a rebase they name a different commit.
    private var labels: ConflictSideLabels {
        ConflictSideLabels(first: conflict)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Conflict \(number) of \(total)")
                    .font(.system(size: 11, weight: .semibold))
                Text("line \(conflict.startLine)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 6)
                Menu("Use Both") {
                    Button("Current, then Incoming") { resolve(.currentThenIncoming) }
                    Button("Incoming, then Current") { resolve(.incomingThenCurrent) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Keep both sides' lines, one after the other")
                .accessibilityLabel("Use both sides for conflict \(number)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            side(title: "Current", label: labels.current, lines: conflict.current, tint: .green) {
                resolve(.current)
            }
            if let base = conflict.base {
                DisclosureGroup(isExpanded: $showsBase) {
                    CodeLines(lines: base, placeholder: "No lines in the common ancestor")
                } label: {
                    Text("Common ancestor\(conflict.baseLabel.map { $0.isEmpty ? "" : " · \($0)" } ?? "")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }
            side(title: "Incoming", label: labels.incoming, lines: conflict.incoming, tint: .blue) {
                resolve(.incoming)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DS.Palette.warning.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func side(title: String, label: String, lines: [String], tint: Color, use: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(tint)
                    .frame(width: 3, height: 12)
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Button("Use \(title)", action: use)
                    .controlSize(.small)
                    .accessibilityLabel("Use \(title) for conflict \(number)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            CodeLines(lines: lines, placeholder: "No lines on this side")
                .background(tint.opacity(0.08))
        }
    }
}

/// Lines of the file in the diff's monospaced type, selectable.
private struct CodeLines: View {
    let lines: [String]
    var placeholder: String?

    var body: some View {
        if lines.isEmpty, let placeholder {
            Text(placeholder)
                .font(.system(size: 11).italic())
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
