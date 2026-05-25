import SwiftUI

/// Fork-style confirmation sheet for `git push`. Surfaces the current branch
/// (read-only), lets the user pick the target remote, and exposes "push all
/// tags" + "force push" (mapped to `--force-with-lease` for safety) toggles.
struct PushSheet: View {
    let store: RepositoryStore
    let dismiss: () -> Void

    @State private var selectedRemote: String = ""
    @State private var pushAllTags: Bool = true
    @State private var forcePush: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            formRow(label: "Branch") {
                branchPill
            }

            formRow(label: "To") {
                remotePicker
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Push all tags", isOn: $pushAllTags)
                    .toggleStyle(.checkbox)
                Toggle("Force push", isOn: $forcePush)
                    .toggleStyle(.checkbox)
                if forcePush {
                    Text("Uses `--force-with-lease` to avoid clobbering unseen remote work.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 130)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Push", action: performPush)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(currentBranchName == nil || availableRemotes.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear(perform: configureDefaultRemote)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.85), Color.blue.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 42, height: 42)
                Circle()
                    .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                    .frame(width: 42, height: 42)
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .aviShadow(Glass.Elevation.resting.shadow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Push")
                    .font(.system(size: 15, weight: .semibold))
                Text("Push your local changes to remote repository")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Rows

    private func formRow(label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(label):")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 110, alignment: .trailing)
            content()
        }
    }

    private var branchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(currentBranchName ?? "(detached HEAD)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private var remotePicker: some View {
        Picker("", selection: $selectedRemote) {
            ForEach(availableRemotes, id: \.self) { remote in
                Text(label(for: remote)).tag(remote)
            }
            if availableRemotes.isEmpty {
                Text("(no remotes)").tag("")
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(for remote: String) -> String {
        if remote == upstreamRemote, let branch = currentBranchName {
            return "default (\(remote)/\(branch))"
        }
        return remote
    }

    // MARK: - Derived state

    private var currentBranchName: String? {
        store.branch?.name
    }

    private var availableRemotes: [String] {
        let names = store.remotes.map(\.name)
        if names.isEmpty, let upstreamRemote {
            return [upstreamRemote]
        }
        return names
    }

    private var upstreamRemote: String? {
        guard let upstream = store.branch?.upstream,
              let head = upstream.split(separator: "/", maxSplits: 1).first
        else { return nil }
        return String(head)
    }

    private func configureDefaultRemote() {
        if !selectedRemote.isEmpty { return }
        if let upstreamRemote, availableRemotes.contains(upstreamRemote) {
            selectedRemote = upstreamRemote
        } else if let first = availableRemotes.first {
            selectedRemote = first
        }
    }

    // MARK: - Action

    private func performPush() {
        let branch = currentBranchName
        let remote = selectedRemote.isEmpty ? nil : selectedRemote
        let force = forcePush
        let tags = pushAllTags
        dismiss()
        Task {
            await store.push(branch: branch, remote: remote, force: force, pushTags: tags)
        }
    }
}
