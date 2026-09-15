import AppKit
import GitKit
import SwiftUI

/// Inspecting a ref never changes the working tree. Checkout is a separate menu action.
struct ReferenceActionButton<Label: View>: View {
    let ref: GitReference
    let hasLocalChanges: Bool
    let select: () -> Void
    let checkout: (GitReference) -> Void
    @ViewBuilder let label: () -> Label

    @State private var pendingTag: GitReference?

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
                Divider()
                Button(ref.kind == .tag ? "Copy Tag Name" : "Copy Branch Name") {
                    copy(ref.name)
                }
                Button("Copy Commit SHA") {
                    copy(ref.targetOID)
                }
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
        Binding(
            get: { pendingTag != nil },
            set: {
                if !$0 {
                    pendingTag = nil
                }
            }
        )
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
