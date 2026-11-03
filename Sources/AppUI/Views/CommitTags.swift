import GitKit
import SwiftUI

/// The tags a commit you are about to make gets, above its message: click
/// one to change it, or remove it with its x.
struct CommitTagsRow: View {
    let store: RepositoryStore
    let target: TagEditRequest.Target

    var body: some View {
        let tags = store.tags(for: target)
        HStack(spacing: 6) {
            if !tags.isEmpty {
                Text("Tag after committing:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(tags, id: \.name) { tag in
                    CommitTagChip(
                        tag: tag,
                        edit: { store.requestTagEdit(for: target, editing: tag) },
                        remove: { store.removeTag(named: tag.name, from: target) }
                    )
                }
            }
            Spacer(minLength: 0)
            Button {
                store.requestTagEdit(for: target)
            } label: {
                Label("Add Tag…", systemImage: "tag")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading || store.isApplyingPlan)
            .help("Add a tag, such as a release version, to this commit")
        }
        .help("Avi creates the tag on this commit right after making it. Push sends the commit and its tag together.")
    }
}

private struct CommitTagChip: View {
    let tag: NewTag
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: edit) {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                        .font(.system(size: 10, weight: .semibold))
                    Text(tag.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tag.message.map { "Annotated tag: \($0)" } ?? "Lightweight tag")
            .accessibilityLabel("Tag \(tag.name)")
            .accessibilityHint("Edit the tag")

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Do not create this tag")
            .accessibilityLabel("Remove tag \(tag.name)")
        }
        .foregroundStyle(Color.accentColor)
        .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.10)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 0.6))
    }
}

/// The first tag a commit in the stack gets, and how many more.
struct CommitTagBadge: View {
    let tags: [NewTag]

    var body: some View {
        if let first = tags.first {
            let names = tags.map(\.name).joined(separator: ", ")
            HStack(spacing: 3) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 8))
                Text(tags.count > 1 ? "\(first.name) +\(tags.count - 1)" : first.name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: 120, alignment: .trailing)
            .help("Tagged \(names) once committed")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tag \(names)")
        }
    }
}

/// Adds a tag to a commit you are about to make, or changes one.
struct CommitTagSheet: View {
    let store: RepositoryStore
    let request: TagEditRequest

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message = ""

    var body: some View {
        AviPopup(
            symbol: "tag.fill",
            tint: DS.Palette.infoOrange,
            title: request.original == nil ? "Tag \(commitName)" : "Edit Tag",
            subtitle: request.original == nil ? "Created right after the commit" : request.original?.name,
            width: 400
        ) {
            AviPopupCallout(
                "Avi creates the tag on this commit right after making it. Push then sends the commit and the tag together, so the tag never reaches the remote before its commit."
            )
            AviPopupField("Name", note: problem, noteTone: .warning) {
                TextField("v1.2.3", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    .accessibilityLabel("Tag name")
            }
            AviPopupField(
                "Message",
                note: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Optional. Without a message the tag is lightweight."
                    : "Annotated tag."
            ) {
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 60, maxHeight: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .accessibilityLabel("Tag message")
            }
        } footer: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.aviSecondary)
                .keyboardShortcut(.cancelAction)
            Button(request.original == nil ? "Add Tag" : "Save", action: save)
                .buttonStyle(.aviProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || problem != nil)
        }
        .onAppear {
            name = request.original?.name ?? ""
            message = request.original?.message ?? ""
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nothing while the field is empty; Add stays off until there is a name.
    private var problem: String? {
        guard !trimmedName.isEmpty else { return nil }
        return store.tagNameProblem(trimmedName, replacing: request.original?.name)
    }

    /// Spaces cannot be in a tag name, so they become dashes as you type.
    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { name = $0.replacingOccurrences(of: " ", with: "-") })
    }

    private var commitName: String {
        switch request.target {
        case .stagedCommit:
            return store.stackCount > 1 ? "Commit 1" : "the Commit"
        case .draft(let id):
            return store.stackNumber(ofDraft: id).map { "Commit \($0)" } ?? "the Commit"
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, problem == nil else { return }
        store.saveTag(NewTag(name: trimmedName, message: message), replacing: request.original, for: request.target)
        dismiss()
    }
}
