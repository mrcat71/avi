import GitKit
import SwiftUI

struct RemotesView: View {
    let store: RepositoryStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Remotes")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.fetch(remote: nil) }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .disabled(store.remotes.isEmpty || store.isRemoteOperationRunning)
                .help("Fetch All")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List {
                if store.remotes.isEmpty {
                    Text("No remotes")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.remotes) { remote in
                        RemoteRowView(remote: remote, store: store)
                    }
                }
            }
        }
    }
}

private struct RemoteRowView: View {
    let remote: GitRemote
    let store: RepositoryStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(.purple)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(remote.name)
                    .font(.body)
                    .lineLimit(1)
                Text(remote.fetchURL ?? remote.pushURL ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                Task { await store.fetch(remote: remote.name) }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRemoteOperationRunning)
            .help("Fetch")
        }
    }
}

struct RemoteDetailView: View {
    let store: RepositoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button {
                    Task { await store.fetch(remote: nil) }
                } label: {
                    Label("Fetch", systemImage: "arrow.down.circle")
                }
                .disabled(store.remotes.isEmpty || store.isRemoteOperationRunning)

                Button {
                    Task { await store.pull() }
                } label: {
                    Label("Pull", systemImage: "arrow.down.to.line")
                }
                .disabled(store.isRemoteOperationRunning || store.branch?.isUnborn != false)

                Button {
                    Task { await store.push() }
                } label: {
                    Label("Push", systemImage: "arrow.up.to.line")
                }
                .disabled(store.isRemoteOperationRunning || store.branch?.isUnborn != false)

                if store.isRemoteOperationRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(currentBranchText, systemImage: "arrow.triangle.branch")
                    .font(.title2.weight(.semibold))

                if let upstream = store.branch?.upstream {
                    Label(upstreamText(upstream), systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                } else if store.branch?.isUnborn == false {
                    Label("No upstream", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                }
            }

            if let output = store.remoteOutput {
                Divider()
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var currentBranchText: String {
        guard let branch = store.branch else { return "Remotes" }
        if let name = branch.name { return name }
        if branch.isDetached { return "Detached HEAD" }
        return "Unborn branch"
    }

    private func upstreamText(_ upstream: String) -> String {
        guard let branch = store.branch else { return upstream }
        var parts = [upstream]
        if branch.ahead > 0 { parts.append("ahead \(branch.ahead)") }
        if branch.behind > 0 { parts.append("behind \(branch.behind)") }
        return parts.joined(separator: ", ")
    }
}
