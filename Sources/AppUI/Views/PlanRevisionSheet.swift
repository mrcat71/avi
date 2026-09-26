import SwiftUI

/// Where you tell the AI how to rework planned commits: split one, merge a
/// few, regroup them all, or rewrite the messages. It also splits changes that
/// are in no planned commit yet into new ones.
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
                Text(heading)
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
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Cancel", role: .cancel) {
                    store.revisionRequest = nil
                }
                .keyboardShortcut(.cancelAction)
                Button(isSplit ? "Split" : (request.draftIDs.count > 1 ? "Rethink" : "Revise")) {
                    if isSplit {
                        store.splitIntoCommits(request.files, instructions: instructions)
                    } else {
                        store.reviseDrafts(request.draftIDs, instructions: instructions)
                    }
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

    private var isSplit: Bool {
        !request.files.isEmpty
    }

    private var heading: String {
        if isSplit {
            return "Split into Commits with AI"
        }
        return request.draftIDs.count > 1 ? "Rethink Commits with AI" : "Revise Commit with AI"
    }

    private var footnote: String {
        if isSplit {
            return "The AI sees the changes in these files and plans commits for them. Files it leaves out stay where they are."
        }
        return "The AI sees these commits and the changes in their files. Files it leaves out go back to Commit 1 or Unstaged."
    }
}
