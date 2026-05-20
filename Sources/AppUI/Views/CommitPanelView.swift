import SwiftUI

struct CommitPanelView: View {
    let store: RepositoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Commit")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("Amend", isOn: amendBinding)
                    .toggleStyle(.switch)
                    .disabled(!store.canAmend)
            }

            TextEditor(text: messageBinding)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 76, idealHeight: 96, maxHeight: 126)
                .overlay {
                    if store.commitMessage.isEmpty {
                        Text("Summary")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    }
                }
                .padding(4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }

            HStack {
                Text(commitHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    Task { await store.commit() }
                } label: {
                    Label(
                        store.amend ? "Amend" : "Commit",
                        systemImage: store.amend ? "square.and.pencil" : "checkmark.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canCommit || store.isLoading)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .task(id: store.amend) {
            await store.prepareAmendIfNeeded()
        }
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: { store.commitMessage },
            set: { store.commitMessage = $0 }
        )
    }

    private var amendBinding: Binding<Bool> {
        Binding(
            get: { store.amend },
            set: { store.amend = $0 && store.canAmend }
        )
    }

    private var commitHint: String {
        if store.amend {
            return store.stagedEntries.isEmpty ? "Amend message" : "Amend with staged changes"
        }
        let count = store.stagedEntries.count
        return count == 1 ? "1 staged file" : "\(count) staged files"
    }
}
