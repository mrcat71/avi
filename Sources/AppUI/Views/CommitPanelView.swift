import SwiftUI

struct CommitPanelView: View {
    let store: RepositoryStore

    @Bindable private var config = ConfigStore.shared

    private let summaryWarn = 50
    private let summaryMax = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let err = store.aiError {
                aiErrorBanner(err)
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
        .task(id: store.amend) {
            await store.prepareAmendIfNeeded()
        }
    }

    private func aiErrorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                store.dismissAIError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss AI error")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.12))
        )
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
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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
                generateButton
            }
            Text(commitHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var generateButton: some View {
        if store.isGeneratingCommitMessage {
            Button {
                store.cancelCommitMessageGeneration()
            } label: {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                store.generateCommitMessage(config: config.config.ai)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .medium))
                    Text(store.aiLastGenerated == nil ? "Generate" : "Regenerate")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.entries.isEmpty)
            .help(generateHelp)
            .accessibilityLabel("Generate commit message with AI")
        }
    }

    private var generateHelp: String {
        if !config.config.ai.enabled { return "AI generation is disabled. Enable it in Settings → AI Commit Messages." }
        if store.stagedEntries.isEmpty { return "Stage files first. Generation reads the staged diff." }
        return "Generate a commit message from staged changes via \(config.config.ai.backend == "openai" ? "OpenAI API" : "custom command")."
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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
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
