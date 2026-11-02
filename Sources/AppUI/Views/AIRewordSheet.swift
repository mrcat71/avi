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
        AviPopup(
            symbol: "wand.and.stars",
            tint: DS.Palette.infoPurple,
            title: "Reword with AI",
            subtitle: "Commit \(String(preview.oid.prefix(7)))",
            width: 560
        ) {
            AviPopupField("Current message") {
                ScrollView {
                    Text(preview.oldMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 44, idealHeight: 80, maxHeight: 100)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
            }

            AviPopupField("Proposed message") {
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, idealHeight: 180, maxHeight: 240)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .accessibilityLabel("Proposed message")
            }
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) {
                store.dismissAIRewordPreview()
            }
            .buttonStyle(.aviSecondary)
            .keyboardShortcut(.cancelAction)
            Button("Apply") {
                var p = preview
                p.proposed = draft
                store.aiRewordPreview = p
                store.applyAIRewordPreview()
            }
            .buttonStyle(.aviProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
