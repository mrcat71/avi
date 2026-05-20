import GitKit
import SwiftUI

struct RepositorySidebarView: View {
    @Binding var selection: RepositorySelection
    let store: RepositoryStore

    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            primaryItems
            Divider()
            searchField
            refTree
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.root?.lastPathComponent ?? "Avi")
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoading)
                .help("Refresh")
            }

            if let branch = store.branch {
                Label(branchLabel(branch), systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 18)
    }

    private var primaryItems: some View {
        VStack(spacing: 6) {
            sidebarButton(
                title: "Local Changes (\(store.entries.count))",
                systemImage: "doc.badge.gearshape",
                isSelected: selection == .localChanges
            ) {
                selection = .localChanges
            }

            sidebarButton(
                title: "All Commits",
                systemImage: "archivebox",
                isSelected: selection == .allCommits
            ) {
                selection = .allCommits
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $filter)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var refTree: some View {
        List {
            DisclosureGroup("Branches") {
                ForEach(filtered(store.refs.localBranches)) { ref in
                    Button {
                        selection = .allCommits
                        Task { await store.checkout(ref) }
                    } label: {
                        RefSidebarRow(ref: ref)
                    }
                    .buttonStyle(.plain)
                }
            }

            DisclosureGroup("Remotes") {
                ForEach(remoteGroups, id: \.name) { group in
                    DisclosureGroup(group.name) {
                        ForEach(filtered(group.refs)) { ref in
                            Button {
                                selection = .allCommits
                                Task { await store.checkout(ref) }
                            } label: {
                                RefSidebarRow(ref: ref)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if store.remotes.isEmpty {
                    Text("No remotes")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        selection = .remotes
                    } label: {
                        Label("Remote Actions", systemImage: "network")
                    }
                    .buttonStyle(.plain)
                }
            }

            DisclosureGroup("Tags") {
                ForEach(filtered(store.refs.tags)) { ref in
                    Button {
                        selection = .allCommits
                        Task { await store.checkout(ref) }
                    } label: {
                        RefSidebarRow(ref: ref)
                    }
                    .buttonStyle(.plain)
                }
            }

            DisclosureGroup("Stashes") {
                PlaceholderSidebarRow(title: "No stashes loaded", systemImage: "tray")
            }

            DisclosureGroup("Submodules") {
                PlaceholderSidebarRow(title: "No submodules loaded", systemImage: "square.stack.3d.up")
            }

            DisclosureGroup("Operations") {
                PlaceholderSidebarRow(title: "No active operation", systemImage: "checkmark.circle")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sidebarButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func filtered(_ refs: [GitReference]) -> [GitReference] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return refs }
        return refs.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private var remoteGroups: [(name: String, refs: [GitReference])] {
        let grouped = Dictionary(grouping: store.refs.remoteBranches) { ref in
            ref.name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ref.name
        }
        return grouped
            .map { (name: $0.key, refs: $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func branchLabel(_ branch: BranchInfo) -> String {
        if let name = branch.name { return name }
        if branch.isDetached { return "Detached HEAD" }
        return "No commits"
    }
}

private struct PlaceholderSidebarRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}

private struct RefSidebarRow: View {
    let ref: GitReference

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(ref.isCurrent ? Color.accentColor : .secondary)
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if ref.isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14, weight: ref.isCurrent ? .semibold : .regular))
        .padding(.vertical, 4)
    }

    private var displayName: String {
        switch ref.kind {
        case .remoteBranch:
            ref.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? ref.name
        default:
            ref.name
        }
    }

    private var icon: String {
        switch ref.kind {
        case .localBranch: "arrow.triangle.branch"
        case .remoteBranch: "network"
        case .tag: "tag"
        }
    }
}
