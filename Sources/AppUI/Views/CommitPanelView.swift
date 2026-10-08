import AppKit
import SwiftUI

/// Bottom-right pane for Commit 1, the staged files: message, AI help, amend,
/// and Commit, or Commit All once planned commits follow it.
struct CommitPanelView: View {
    let store: RepositoryStore

    @Bindable private var config = ConfigStore.shared
    @Environment(\.aviDensity) private var density

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    header

                    if store.isGeneratingCommitMessage {
                        generatingBanner
                    }

                    if let preview = store.aiPendingPreview {
                        AIPreviewCard(preview: preview, store: store, config: config.config.ai)
                    }

                    if let err = store.aiErrorDetail {
                        AIErrorBanner(detail: err, store: store, config: config.config.ai)
                    }

                    if let proposal = store.fieldProposal, proposal.inField {
                        FieldProposalBanner(proposal: proposal, store: store)
                    }

                    CommitMessageEditor(summary: summaryBinding, messageBody: bodyBinding) {
                        actionRow
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .disabled(isFormDisabled)
            .opacity(isFormDisabled ? 0.55 : 1)
            .overlay {
                if isFormDisabled {
                    cleanOverlay
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.aiDebugDrawerVisible {
                    AIDebugDrawer(store: store, containerHeight: proxy.size.height)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Glass.Motion.snappy, value: store.aiDebugDrawerVisible)
            .animation(Glass.Motion.snappy, value: store.aiDebugMinimized)
            .animation(Glass.Motion.snappy, value: store.isGeneratingCommitMessage)
            .task(id: store.amend) {
                await store.prepareAmendIfNeeded()
            }
        }
    }

    private var isFormDisabled: Bool {
        // A merge with every conflict resolved still needs its commit.
        !store.amend && store.entries.isEmpty && store.operationState != .merge
    }

    @ViewBuilder
    private var cleanOverlay: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.green)
            Text("Nothing to commit")
                .font(.system(size: 11, weight: .semibold))
            Text("Stage changes to write a message.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
        )
        .allowsHitTesting(false)
        .opacity(1.0 / 0.55)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(store.stackCount > 1 ? "Commit 1 of \(store.stackCount)" : "Commit")
                .aviLabel(density)
            if store.stackCount > 1 {
                Text("staged")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if config.config.ai.enabled {
                debugToggleButton
            }
            if store.stackCount > 1 {
                Button {
                    if let next = store.stackOrder.dropFirst().first {
                        store.selectStackEntry(next)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Next commit")
                .accessibilityLabel("Next commit")
            }
        }
    }

    /// Prominent in-panel indicator so the user can see AI generation is running,
    /// and for how long, without opening the debug drawer. Styled like AIPreviewCard.
    private var generatingBanner: some View {
        HStack(spacing: 6) {
            AviWorkingIndicator(title: "Writing commit message")
            Spacer()
            Button("Cancel") {
                store.cancelCommitMessageGeneration()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    /// Generate writes a message for the staged changes in one click; the menu
    /// beside it holds Split into Commits. Explicit actions, no auto-magic.
    private var generateControl: some View {
        let busy = store.isGeneratingCommitMessage || store.isAIWorking
        let nothingStaged = store.stagedCommitEntries.isEmpty
        return HStack(spacing: 0) {
            Button {
                store.generateCommitMessage(config: config.config.ai)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Generate")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.leading, 9)
                .padding(.trailing, 7)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(nothingStaged || busy ? DS.Palette.textTertiary : DS.Palette.accent)
            .disabled(nothingStaged || busy)
            .help(nothingStaged ? "Stage files first: the AI writes a message for the staged changes" : "Write a message for the staged changes")
            .accessibilityLabel("Generate commit message")

            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 1, height: 12)

            Menu {
                Button {
                    store.generateCommitMessage(config: config.config.ai)
                } label: {
                    Label("Generate Commit Message", systemImage: "sparkles")
                }
                .disabled(nothingStaged || busy)

                // Both work on what you staged; stage the changes first.
                Button {
                    let paths = store.splittablePaths
                    store.requestSplit(of: paths, title: "Commit 1: " + RepositoryStore.splitTitle(paths))
                } label: {
                    Label("Split into Commits…", systemImage: "rectangle.split.3x1")
                }
                .disabled(store.stagedCommitEntries.count < 2 || store.isRevisingPlan || store.isApplyingPlan || busy)
                .help("Ask the AI to split the staged files into several commits")
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More AI commit actions")
            .accessibilityLabel("More AI commit actions")
        }
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6))
    }

    private var debugToggleButton: some View {
        Button {
            store.toggleAIDebugDrawer()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ladybug")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.aiDebugDrawerVisible ? Color.accentColor : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                if store.aiDebugHasUnreadError {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .offset(x: -3, y: 3)
                }
            }
        }
        .buttonStyle(.plain)
        .help(store.aiDebugDrawerVisible ? "Hide AI debug drawer" : "Show AI debug drawer")
        .accessibilityLabel("Toggle AI debug drawer")
    }

    /// Along the bottom of the message card: how to commit, then the commit itself.
    private var actionRow: some View {
        HStack(spacing: 8) {
            AmendChip(active: store.amend, enabled: store.canAmend) {
                if store.canAmend {
                    store.amend.toggle()
                }
            }

            if config.config.ai.enabled {
                generateControl
            }

            Spacer(minLength: 6)

            if store.stackCount > 1 {
                if let progress = store.planProgress {
                    ProgressView()
                        .controlSize(.small)
                    Text("Committing \(min(progress.completed + 1, progress.total)) of \(progress.total)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let blocker = store.stackBlocker {
                    Text(blocker)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Button(store.amend ? "Amend Only This" : "Commit This") {
                    Task { await store.commit() }
                }
                .controlSize(.small)
                .disabled(!store.canCommit || store.isLoading || store.isApplyingPlan)
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .help("Commit only the staged files and move to the next commit (Option+Cmd+Return)")

                Button {
                    Task { await store.commitStack() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Commit All (\(store.stackCount))")
                            .font(.system(size: 12, weight: .semibold))
                        Text("⌘↩")
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.65)
                    }
                }
                .accessibilityLabel("Commit All (\(store.stackCount))")
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.canCommitStack)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Create every commit in order, Commit 1 first (Cmd+Return)")
            } else {
                if let reason = commitBlockedReason {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Button {
                    Task { await store.commit() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: store.amend ? "square.and.pencil" : "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text(commitTitle)
                            .font(.system(size: 12, weight: .semibold))
                        Text("⌘↩")
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.65)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!store.canCommit || store.isLoading)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("\(commitTitle) (Cmd+Return)")
                .accessibilityLabel(commitTitle)
            }
        }
    }

    /// Says exactly what the button does: how many staged files it commits,
    /// or whether amend takes new files or only rewrites the message.
    private var commitTitle: String {
        let count = store.stagedCommitEntries.count
        let files = count == 1 ? "1 File" : "\(count) Files"
        if store.amend {
            return count == 0 ? "Amend Message" : "Amend with \(files)"
        }
        return count == 0 ? "Commit" : "Commit \(files)"
    }

    /// Why Commit is off, next to it, so a disabled button never goes unexplained.
    private var commitBlockedReason: String? {
        // While the AI writes the summary, there is nothing to ask for.
        guard !store.canCommit, !store.isLoading, !store.isGeneratingCommitMessage else { return nil }
        let hasContent = (store.amend && store.canAmend) || !store.stagedCommitEntries.isEmpty || store.canConcludeMerge
        if !hasContent {
            return "Stage files to commit"
        }
        if store.commitSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write a summary"
        }
        return nil
    }

    private var summaryBinding: Binding<String> {
        Binding(get: { store.commitSummary }, set: { store.commitSummary = $0 })
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { store.commitBody }, set: { store.commitBody = $0 })
    }
}

private struct AmendChip: View {
    let active: Bool
    let enabled: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                Text("Amend")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule().fill(background)
            )
            .overlay(
                Capsule().stroke(stroke, lineWidth: active ? 0 : 1)
            )
            .foregroundStyle(foreground)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .help(enabled ? (active ? "Amending last commit. Click to disable." : "Amend last commit instead of creating a new one.") : "No previous commit to amend.")
    }

    private var background: Color {
        if active {
            return Color.accentColor
        }
        if isHovering {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }

    private var stroke: Color {
        Color.primary.opacity(0.15)
    }

    private var foreground: Color {
        active ? Color.white : .primary
    }
}

// MARK: - AI preview card

private struct AIPreviewCard: View {
    let preview: AIPendingPreview
    let store: RepositoryStore
    let config: AIConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: preview.proposedBy == nil ? "character.bubble" : "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                Text(preview.proposedBy.map { "Proposed by \($0)" } ?? "Generated commit message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if preview.proposedBy == nil {
                    Text("via \(config.backend) · \(config.model)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.subject.isEmpty ? "(no subject)" : preview.subject)
                    .font(.system(size: 12, weight: .semibold))
                    .textSelection(.enabled)
                if !preview.body.isEmpty {
                    Text(preview.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 6) {
                Button("Replace") {
                    store.acceptAIPreview(.replace)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Append as body") {
                    store.acceptAIPreview(.appendAsBody)
                }
                .controlSize(.small)

                if preview.proposedBy == nil {
                    Button("Regenerate") {
                        store.generateCommitMessage(config: config)
                    }
                    .controlSize(.small)
                    .disabled(store.isGeneratingCommitMessage)
                }

                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(preview.combined, forType: .string)
                }
                .controlSize(.small)

                if preview.proposedBy == nil {
                    Button("Debug") {
                        store.openAIDebugDrawer()
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Discard", role: .destructive) {
                    store.discardAIPreview()
                }
                .controlSize(.small)
                .help(preview.proposedBy == nil ? "Discard this message" : "Discard the proposal and unstage the files Avi staged for it")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Compact one-line error banner. The full diagnostic (command, stdout, stderr)
/// lives in the bottom drawer; this banner only surfaces the headline so the
/// commit form stays usable.
private struct AIErrorBanner: View {
    let detail: AIErrorDetail
    let store: RepositoryStore
    let config: AIConfig

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(detail.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(detail.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Retry") {
                store.generateCommitMessage(config: config)
            }
            .controlSize(.small)
            .disabled(store.isGeneratingCommitMessage)

            if detail.runResult != nil {
                Button("Show details") {
                    store.openAIDebugDrawer()
                }
                .controlSize(.small)
            }

            Button {
                store.dismissAIError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss AI error")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        )
    }
}

/// Shown while an agent's proposal fills the commit field: who sent it, what
/// it staged, and anything else staged that will ride along.
private struct FieldProposalBanner: View {
    let proposal: FieldProposal
    let store: RepositoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                Text("Proposed by \(proposal.source.displayName)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(filesLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Withdraw") {
                    Task { await store.discardFieldProposal() }
                }
                .controlSize(.small)
                .help("Clear the message and unstage the files Avi staged for this proposal")
            }
            let extra = store.stagedOutsideFieldProposal
            if !extra.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("\(extra.count) other staged file\(extra.count == 1 ? "" : "s") will be committed too")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help(extra.joined(separator: "\n"))
                    Spacer()
                    Button("Unstage Them") {
                        Task { await store.unstageOutsideFieldProposal() }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var filesLabel: String {
        let count = proposal.files.count
        if count == 0 {
            return "message only"
        }
        return count == 1 ? "1 file staged" : "\(count) files staged"
    }
}
