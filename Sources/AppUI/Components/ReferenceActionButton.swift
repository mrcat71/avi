import AppKit
import GitKit
import SwiftUI

/// Inspecting a ref never changes the working tree. Checkout is a separate menu action.
struct ReferenceActionButton<Label: View>: View {
    let ref: GitReference
    let hasLocalChanges: Bool
    let select: () -> Void
    let checkout: (GitReference) -> Void
    /// Remote a tag push targets, shown in the menu so the target is never a guess.
    var pushRemote: String?
    var pushTag: ((GitReference) -> Void)?
    var deleteTag: ((GitReference) -> Void)?
    @ViewBuilder let label: () -> Label

    @State private var pendingTag: GitReference?
    @State private var pendingPush: GitReference?
    @State private var pendingDelete: GitReference?

    var body: some View {
        Button(action: select, label: label)
            .buttonStyle(.plain)
            .accessibilityLabel("Show commit for \(ref.kind == .tag ? "tag" : "branch") \(ref.name)")
            .accessibilityIdentifier("ref.select.\(ref.fullName)")
            .contextMenu {
                Button("Show Commit", action: select)
                Divider()
                Button(checkoutTitle) {
                    if ref.kind == .tag {
                        pendingTag = ref
                    } else {
                        checkout(ref)
                    }
                }
                .disabled(ref.isCurrent)
                if ref.kind == .tag, pushTag != nil || deleteTag != nil {
                    Divider()
                    if let pushRemote, pushTag != nil {
                        Button("Push Tag to '\(pushRemote)'...") { pendingPush = ref }
                    }
                    if deleteTag != nil {
                        Button("Delete Tag...", role: .destructive) { pendingDelete = ref }
                    }
                }
                Divider()
                Button(ref.kind == .tag ? "Copy Tag Name" : "Copy Branch Name") {
                    copy(ref.name)
                }
                Button("Copy Commit SHA") {
                    copy(ref.targetOID)
                }
            }
            .alert("Push Tag?", isPresented: presented($pendingPush), presenting: pendingPush) { tag in
                Button("Cancel", role: .cancel) { pendingPush = nil }
                Button("Push Tag") {
                    pendingPush = nil
                    pushTag?(tag)
                }
            } message: { tag in
                Text("Publishes \"\(tag.name)\" (\(tag.targetOID.prefix(12))) to \(pushRemote ?? "the remote").\n\n"
                    + "Push the branch first if you want that commit to be part of it. Pushing only the tag uploads the commit outside every branch, which is what a release built from this tag would then contain.")
            }
            .alert("Delete Tag?", isPresented: presented($pendingDelete), presenting: pendingDelete) { tag in
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete Tag", role: .destructive) {
                    pendingDelete = nil
                    deleteTag?(tag)
                }
            } message: { tag in
                Text("Removes \"\(tag.name)\" from this repository only. A copy already pushed stays on the remote, so anything released from it keeps working.")
            }
            .alert("Check Out Tag?", isPresented: checkoutPresented, presenting: pendingTag) { tag in
                Button("Cancel", role: .cancel) { pendingTag = nil }
                Button("Check Out Tag") {
                    pendingTag = nil
                    checkout(tag)
                }
            } message: { tag in
                Text("This will update the working files to \"\(tag.name)\" (\(tag.targetOID.prefix(12))) and detach HEAD. New commits will not belong to a branch.\n\n"
                    + (hasLocalChanges
                        ? "You have local changes. Git will stop if switching would overwrite them. Avi will not stash or discard them automatically.\n\n"
                        : "")
                    + "To inspect this tag without changing files, cancel and use Show Commit.")
            }
    }

    private var checkoutTitle: String {
        switch ref.kind {
        case .tag: return "Check Out Tag..."
        case .localBranch: return "Check Out Branch"
        case .remoteBranch: return "Track Branch"
        }
    }

    private var checkoutPresented: Binding<Bool> {
        presented($pendingTag)
    }

    private func presented(_ ref: Binding<GitReference?>) -> Binding<Bool> {
        Binding(
            get: { ref.wrappedValue != nil },
            set: {
                if !$0 {
                    ref.wrappedValue = nil
                }
            }
        )
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
