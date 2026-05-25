import SwiftUI

/// Sheet that lets the user review and edit an AI-proposed rewording for a
/// single commit before applying it. Reads `store.aiRewordPreview`; the host
/// view binds presentation to that field.
struct AIRewordSheet: View {
    let store: RepositoryStore
    let preview: AIRewordPreview

    @State private var draft: String

    init(store: RepositoryStore, preview: AIRewordPreview) {
        self.store = store
        self.preview = preview
        _draft = State(initialValue: preview.proposed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Current message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                ScrollView {
                    Text(preview.oldMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 100)
                .background(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Proposed message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 240)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                            .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                    )
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    store.dismissAIRewordPreview()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    var p = preview
                    p.proposed = draft
                    store.aiRewordPreview = p
                    store.applyAIRewordPreview()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 42, height: 42)
                Circle()
                    .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                    .frame(width: 42, height: 42)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .aviShadow(Glass.Elevation.resting.shadow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reword with AI")
                    .font(.system(size: 15, weight: .semibold))
                Text("Commit \(String(preview.oid.prefix(7)))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
