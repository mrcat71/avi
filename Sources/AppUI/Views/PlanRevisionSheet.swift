import SwiftUI

/// Where you tell the AI how to rework planned commits: split one, merge a
/// few, regroup the whole plan, or rewrite the messages.
struct PlanRevisionSheet: View {
    let store: RepositoryStore
    let request: PlanRevisionRequest

    @State private var instructions: String
    @FocusState private var editorFocused: Bool

    init(store: RepositoryStore, request: PlanRevisionRequest) {
        self.store = store
        self.request = request
        _instructions = State(initialValue: request.suggestion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(request.draftIDs.count > 1 ? "Rethink Commits with AI" : "Revise Commit with AI")
                    .font(.system(size: 15, weight: .semibold))
                Text(request.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Text("What should change?")
                .font(.system(size: 12, weight: .medium))
            TextEditor(text: $instructions)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(minHeight: 110)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                )
                .accessibilityLabel("Instructions for the AI")
            Text("For example: put the tests in their own commit. Use the scope \"agents\". Merge the docs into the feature commit. Explain why in each body.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("The AI sees these commits and the changes in their files. Files it leaves out move to Not in Plan.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Cancel", role: .cancel) {
                    store.revisionRequest = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(request.draftIDs.count > 1 ? "Rethink" : "Revise") {
                    store.reviseDrafts(request.draftIDs, instructions: instructions)
                    store.revisionRequest = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Cmd+Return")
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            editorFocused = true
        }
    }
}
