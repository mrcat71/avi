import AppKit
import SwiftUI

struct CommitPanelView: View {
    let store: RepositoryStore

    @Bindable private var config = ConfigStore.shared

    private let summaryWarn = 50
    private let summaryMax = 72

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 6) {
                header

                if let preview = store.aiPendingPreview {
                    AIPreviewCard(preview: preview, store: store, config: config.config.ai)
                }

                if let err = store.aiErrorDetail {
                    AIErrorBanner(detail: err, store: store, config: config.config.ai)
                }

                summaryField
                bodyField

                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
            .task(id: store.amend) {
                await store.prepareAmendIfNeeded()
            }
        }
    }

    private var isFormDisabled: Bool {
        !store.amend && store.entries.isEmpty
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
            Text("Commit")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if config.config.ai.enabled {
                aiMenu
                debugToggleButton
            }
            Text(commitHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// Single AI menu - explicit actions, no auto-magic. The user picks what
    /// they want the AI to do; we do exactly that and nothing else.
    private var aiMenu: some View {
        Menu {
            if store.isGeneratingCommitMessage || store.isAIWorking {
                Button("Cancel") {
                    store.cancelCommitMessageGeneration()
                }
            } else {
                Button {
                    store.generateCommitMessage(config: config.config.ai)
                } label: {
                    Label("Generate Commit Message", systemImage: "character.bubble")
                }
                .disabled(store.entries.isEmpty)

                Button {
                    store.splitStagedWithAI()
                } label: {
                    Label("Split Staged Into Multiple Commits…", systemImage: "rectangle.split.3x1")
                }
                .disabled(store.stagedEntries.count < 2)
            }
        } label: {
            HStack(spacing: 4) {
                if store.isGeneratingCommitMessage || store.isAIWorking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 10, weight: .medium))
                }
                Text("AI")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(Color.accentColor)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("AI commit actions")
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

    private var summaryField: some View {
        HStack(spacing: 0) {
            TextField("feat(scope): short summary", text: summaryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: 28)

            Text("\(summaryCount) / \(summaryMax)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(counterColor)
                .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
        )
    }

    private var bodyField: some View {
        TextEditor(text: bodyBinding)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 50, idealHeight: 64, maxHeight: 100)
            .overlay {
                if store.commitBody.isEmpty {
                    Text("Optional details. Leave a blank line after the summary.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            AmendChip(active: store.amend, enabled: store.canAmend) {
                if store.canAmend {
                    store.amend.toggle()
                }
            }

            Spacer()

            Button {
                Task { await store.commit() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.amend ? "square.and.pencil" : "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(store.amend ? "Amend" : "Commit")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!store.canCommit || store.isLoading)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var summaryBinding: Binding<String> {
        Binding(get: { store.commitSummary }, set: { store.commitSummary = $0 })
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { store.commitBody }, set: { store.commitBody = $0 })
    }

    private var summaryCount: Int {
        store.commitSummary.count
    }

    private var counterColor: Color {
        if summaryCount > summaryMax { return .red }
        if summaryCount > summaryWarn { return .orange }
        return .secondary
    }

    private var commitHint: String {
        if store.amend {
            return store.stagedEntries.isEmpty ? "Amend last commit message" : "Amend with staged changes"
        }
        let count = store.stagedEntries.count
        if count == 0 { return store.entries.isEmpty ? "" : "Stage to commit" }
        return count == 1 ? "1 staged file" : "\(count) staged files"
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
        if active { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.08) }
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
                Image(systemName: "character.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                Text("Generated commit message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text("via \(config.backend) · \(config.model)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
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

                Button("Regenerate") {
                    store.generateCommitMessage(config: config)
                }
                .controlSize(.small)
                .disabled(store.isGeneratingCommitMessage)

                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(preview.combined, forType: .string)
                }
                .controlSize(.small)

                Button("Debug") {
                    store.openAIDebugDrawer()
                }
                .controlSize(.small)

                Spacer()

                Button("Discard", role: .destructive) {
                    store.discardAIPreview()
                }
                .controlSize(.small)
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
