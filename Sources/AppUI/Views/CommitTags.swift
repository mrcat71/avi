import GitKit
import SwiftUI

/// The tags a commit you are about to make gets, above its message: click
/// one to change it, or remove it with its x.
struct CommitTagsRow: View {
    let store: RepositoryStore
    let target: TagEditRequest.Target

    var body: some View {
        let tags = store.tags(for: target)
        if !tags.isEmpty {
            HStack(spacing: 6) {
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
                Spacer(minLength: 0)
            }
            .help("Avi creates the tag on this commit right after making it. Push sends the commit and its tag together.")
        }
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
        VStack(alignment: .leading, spacing: 14) {
            Text(request.original == nil ? "Tag \(commitName)" : "Edit Tag")
                .font(.system(size: 14, weight: .semibold))

            Text("Avi creates the tag on this commit right after making it. Push then sends the commit and the tag together, so the tag never reaches the remote before its commit.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Name (e.g. v1.2.3)", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                if let problem {
                    Text(problem)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message (optional)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .frame(minHeight: 60, maxHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                    .accessibilityLabel("Tag message")
                Text(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Lightweight tag" : "Annotated tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.original == nil ? "Add Tag" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || problem != nil)
            }
        }
        .padding(18)
        .frame(width: 380)
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
