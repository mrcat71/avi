import GitKit
import SwiftUI

struct RefsView: View {
    let store: RepositoryStore
    @State private var showingCreateBranch = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Branches")
                    .font(.headline)
                Spacer()
                Button {
                    showingCreateBranch = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create Branch")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                if !store.refs.localBranches.isEmpty {
                    Section("Local") {
                        ForEach(store.refs.localBranches) { ref in
                            RefRowView(ref: ref, store: store)
                        }
                    }
                }

                if !store.refs.remoteBranches.isEmpty {
                    Section("Remote") {
                        ForEach(store.refs.remoteBranches) { ref in
                            RefRowView(ref: ref, store: store)
                        }
                    }
                }

                if !store.refs.tags.isEmpty {
                    Section("Tags") {
                        ForEach(store.refs.tags) { ref in
                            RefRowView(ref: ref, store: store)
                        }
                    }
                }

                if store.refs == .empty && !store.isRefsLoading {
                    Text("No refs")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if store.refs == .empty && store.isRefsLoading {
                    ProgressView()
                }
            }
        }
        .sheet(isPresented: $showingCreateBranch) {
            CreateBranchSheet(store: store)
        }
    }
}

private struct RefRowView: View {
    let ref: GitReference
    let store: RepositoryStore
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(ref.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if ref.isCurrent {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                Task { await store.checkout(ref) }
            } label: {
                Image(systemName: checkoutIcon)
            }
            .buttonStyle(.borderless)
            .disabled(ref.isCurrent)
            .help(checkoutHelp)

            if ref.kind == .localBranch && !ref.isCurrent {
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete Branch")
            }
        }
        .confirmationDialog(
            "Delete branch \(ref.name)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.deleteBranch(named: ref.name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Git will refuse if the branch has unmerged changes.")
        }
    }

    private var icon: String {
        switch ref.kind {
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "network"
        case .tag: "tag"
        }
    }

    private var color: Color {
        switch ref.kind {
        case .localBranch: .blue
        case .remoteBranch: .purple
        case .tag: .orange
        }
    }

    private var checkoutIcon: String {
        switch ref.kind {
        case .localBranch: "arrow.turn.down.right"
        case .remoteBranch: "plus.square.on.square"
        case .tag: "arrow.down.to.line"
        }
    }

    private var checkoutHelp: String {
        switch ref.kind {
        case .localBranch: "Checkout"
        case .remoteBranch: "Track"
        case .tag: "Detach"
        }
    }

    private var detailText: String {
        if let upstream = ref.upstream {
            return upstream
        }
        if let subject = ref.subject {
            return subject
        }
        return String(ref.oid.prefix(12))
    }
}

private struct CreateBranchSheet: View {
    let store: RepositoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var checkout = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Branch")
                .font(.title3.weight(.semibold))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            Toggle("Checkout", isOn: $checkout)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Create") {
                    create()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func create() {
        let branchName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else { return }
        Task {
            await store.createBranch(named: branchName, checkout: checkout)
            dismiss()
        }
    }
}
