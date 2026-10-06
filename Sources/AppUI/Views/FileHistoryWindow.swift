import AppKit
import GitKit
import SwiftUI

/// Opens a file's History or Blame/Timeline window. Codable so SwiftUI can
/// bring back the same window instead of opening a second one.
public struct FileHistoryRequest: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case history
        case blame
    }

    public let repository: URL
    public let path: String
    public let mode: Mode

    public init(repository: URL, path: String, mode: Mode) {
        self.repository = repository
        self.path = path
        self.mode = mode
    }
}

/// Loads a file's history and the diff or blame of the selected version.
@MainActor
@Observable
final class FileHistoryModel {
    /// The "Working Copy" row in Blame mode: the file as it is on disk.
    static let workingCopy = "working-copy"
    static let limit = 500

    let repository: URL
    let path: String
    var mode: FileHistoryRequest.Mode
    private let git: GitProviding

    private(set) var entries: [FileHistoryEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var diff: FileDiff?
    private(set) var blame: [BlameLine] = []
    private(set) var detailError: String?
    private(set) var isLoadingDetail = false
    var selection: String?
    private var detailRequest = UUID()

    init(request: FileHistoryRequest, git: GitProviding = CLIGitProvider()) {
        repository = request.repository
        path = request.path
        mode = request.mode
        self.git = git
    }

    var selectedEntry: FileHistoryEntry? {
        entries.first { $0.id == selection }
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            entries = try await git.fileHistory(path: path, limit: Self.limit, in: repository)
            if selection == nil || (selection != Self.workingCopy && selectedEntry == nil) {
                selection = mode == .blame ? Self.workingCopy : entries.first?.id
            }
            await loadDetail()
        } catch {
            entries = []
            loadError = error.localizedDescription
        }
    }

    func setMode(_ mode: FileHistoryRequest.Mode) async {
        self.mode = mode
        if mode == .history, selection == Self.workingCopy {
            selection = entries.first?.id
        }
        await loadDetail()
    }

    func select(_ id: String?) async {
        guard selection != id else { return }
        selection = id
        await loadDetail()
    }

    /// Blame's way through time: jump to the commit behind a line.
    func reveal(commit oid: String) async {
        guard entries.contains(where: { $0.id == oid }) else { return }
        await select(oid)
    }

    func loadDetail() async {
        let request = UUID()
        detailRequest = request
        detailError = nil
        isLoadingDetail = true
        defer {
            if detailRequest == request {
                isLoadingDetail = false
            }
        }
        do {
            switch mode {
            case .history:
                guard let entry = selectedEntry else {
                    diff = nil
                    return
                }
                let result = try await git.diff(
                    commitOID: entry.commit.oid,
                    path: entry.path,
                    oldPath: entry.oldPath,
                    options: DiffPreferences.shared.gitOptions,
                    in: repository
                )
                guard detailRequest == request else { return }
                diff = result
            case .blame:
                let result: [BlameLine]
                if let entry = selectedEntry {
                    result = try await git.blame(path: entry.path, revision: entry.commit.oid, in: repository)
                } else {
                    result = try await git.blame(path: path, revision: nil, in: repository)
                }
                guard detailRequest == request else { return }
                blame = result
            }
        } catch {
            guard detailRequest == request else { return }
            diff = nil
            blame = []
            detailError = error.localizedDescription
        }
    }
}

/// History and Blame/Timeline for one file: the commits that changed it on
/// the left, the selected commit's change or the blamed file on the right.
public struct FileHistoryWindow: View {
    @State private var model: FileHistoryModel

    public init(request: FileHistoryRequest) {
        _model = State(initialValue: FileHistoryModel(request: request))
    }

    public var body: some View {
        HSplitView {
            timeline
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 460)
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 480)
        .navigationTitle(title)
        .navigationSubtitle(model.path)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: Binding(
                    get: { model.mode },
                    set: { mode in Task { await model.setMode(mode) } }
                )) {
                    Text("History").tag(FileHistoryRequest.Mode.history)
                    Text("Blame").tag(FileHistoryRequest.Mode.blame)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload the history")
                .disabled(model.isLoading)
            }
        }
        .task {
            await model.load()
        }
    }

    private var title: String {
        let name = (model.path as NSString).lastPathComponent
        return model.mode == .history ? "History of \(name)" : "Blame of \(name)"
    }

    private var timeline: some View {
        List(selection: Binding(
            get: { model.selection },
            set: { id in Task { await model.select(id) } }
        )) {
            if model.mode == .blame {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working Copy")
                        .font(.system(size: 12, weight: .semibold))
                    Text("The file as it is now, uncommitted lines included")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(FileHistoryModel.workingCopy)
            }
            ForEach(model.entries) { entry in
                TimelineRow(entry: entry, currentPath: model.path)
                    .tag(entry.id)
            }
        }
        .overlay {
            if model.isLoading, model.entries.isEmpty {
                ProgressView()
            } else if let error = model.loadError {
                ContentUnavailableView("Cannot Load History", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.entries.isEmpty, model.mode == .history {
                ContentUnavailableView("No Commits Yet", systemImage: "clock", description: Text("No commit has changed this file."))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let error = model.detailError {
            ContentUnavailableView("Cannot Show This Version", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if model.mode == .history {
            if let entry = model.selectedEntry {
                VStack(alignment: .leading, spacing: 0) {
                    CommitSummaryHeader(commit: entry.commit)
                    Divider()
                    if let diff = model.diff {
                        FileDiffView(title: entry.oldPath.map { "\($0) → \(entry.path)" } ?? entry.path, diff: diff) {
                            await model.loadDetail()
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else if !model.isLoading {
                ContentUnavailableView("No Commit Selected", systemImage: "clock", description: Text("Select a commit to see how it changed the file."))
            }
        } else if model.isLoadingDetail, model.blame.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            BlameView(lines: model.blame) { oid in
                Task { await model.reveal(commit: oid) }
            }
        }
    }
}

private struct TimelineRow: View {
    let entry: FileHistoryEntry
    let currentPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.commit.subject.isEmpty ? "(no subject)" : entry.commit.subject)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(entry.commit.authorName)
                Text(entry.commit.authorDate, format: .dateTime.year().month().day())
                Text(String(entry.commit.oid.prefix(8)))
                    .font(.system(size: 10, design: .monospaced))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if entry.path != currentPath || entry.oldPath != nil {
                Text(entry.oldPath.map { "Renamed from \($0)" } ?? "As \(entry.path)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .help(entry.commit.body.isEmpty ? entry.commit.subject : entry.commit.subject + "\n\n" + entry.commit.body)
    }
}

private struct CommitSummaryHeader: View {
    let commit: CommitSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(commit.subject.isEmpty ? "(no subject)" : commit.subject)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(commit.authorName)
                Text(commit.authorDate, format: .dateTime.year().month().day().hour().minute())
                Text(commit.shortOID)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The blamed file: each run of lines from one commit opens with who changed
/// it, when, and why. Clicking a run shows that commit in the timeline.
struct BlameView: View {
    let lines: [BlameLine]
    let onSelectCommit: (String) -> Void

    var body: some View {
        if lines.isEmpty {
            ContentUnavailableView("Empty File", systemImage: "doc")
        } else {
            let starts = runStarts
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        BlameLineRow(
                            line: line,
                            startsRun: starts.contains(index),
                            shaded: runIndex(of: index, starts: starts).isMultiple(of: 2),
                            onSelectCommit: onSelectCommit
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    /// Line indexes where the commit changes from the line above.
    private var runStarts: [Int] {
        lines.indices.filter { $0 == 0 || lines[$0].commit.oid != lines[$0 - 1].commit.oid }
    }

    private func runIndex(of index: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= index {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

private struct BlameLineRow: View {
    let line: BlameLine
    let startsRun: Bool
    let shaded: Bool
    let onSelectCommit: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            gutter
                .frame(width: 260, alignment: .leading)
                .background(shaded ? Color.primary.opacity(0.05) : Color.clear)
            Text("\(line.lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, 8)
            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize()
                .textSelection(.enabled)
        }
        .frame(height: 18)
    }

    @ViewBuilder
    private var gutter: some View {
        if startsRun {
            Button {
                onSelectCommit(line.commit.oid)
            } label: {
                HStack(spacing: 6) {
                    Text(line.commit.isUncommitted ? "Not committed" : line.commit.shortOID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(line.commit.isUncommitted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    if !line.commit.isUncommitted {
                        Text(line.commit.author)
                            .font(.system(size: 10, weight: .medium))
                        if let date = line.commit.authorDate {
                            Text(date, format: .dateTime.year().month().day())
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Text(line.commit.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(line.commit.isUncommitted)
            .help(line.commit.isUncommitted ? "Changed in the working copy" : "\(line.commit.summary)\n\(line.commit.author) · \(line.commit.oid)")
        } else {
            Color.clear
        }
    }
}
