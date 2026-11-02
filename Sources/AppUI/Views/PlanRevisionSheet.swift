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
        AviPopup(
            symbol: isSplit ? "rectangle.split.3x1" : "wand.and.stars",
            tint: DS.Palette.infoPurple,
            title: heading,
            subtitle: request.title,
            width: 480
        ) {
            AviPopupField("What should change?", note: "For example: put the tests in their own commit. Use the scope \"agents\". Merge the docs into the feature commit. Explain why in each body.") {
                TextEditor(text: $instructions)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .accessibilityLabel("Instructions for the AI")
            }
        } footer: {
            AviPopupFooterNote(footnote)
            Button("Cancel", role: .cancel) {
                store.revisionRequest = nil
            }
            .buttonStyle(.aviSecondary)
            .keyboardShortcut(.cancelAction)
            Button(isSplit ? "Split" : (request.draftIDs.count > 1 ? "Rethink" : "Revise")) {
                if isSplit {
                    store.splitIntoCommits(request.files, instructions: instructions)
                } else {
                    store.reviseDrafts(request.draftIDs, instructions: instructions)
                }
                store.revisionRequest = nil
            }
            .buttonStyle(.aviProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Cmd+Return")
        }
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
