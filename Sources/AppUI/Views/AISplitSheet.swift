import SwiftUI

/// Multi-step sheet for reviewing an AI-proposed commit split (either of the
/// current staged diff, or of an existing commit).
struct AISplitSheet: View {
    let store: RepositoryStore
    let preview: AISplitPreview

    @State private var groups: [AICommitGroup]

    init(store: RepositoryStore, preview: AISplitPreview) {
        self.store = store
        self.preview = preview
        _groups = State(initialValue: preview.groups)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, _ in
                        groupCard(at: index)
                    }
                }
                .padding(18)
            }

            Divider()
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 460, idealHeight: 540)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 42, height: 42)
                Circle()
                    .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                    .frame(width: 42, height: 42)
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .aviShadow(Glass.Elevation.resting.shadow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Split with AI")
                    .font(.system(size: 15, weight: .semibold))
                Text(sourceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(groups.count) commit\(groups.count == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private var sourceLabel: String {
        switch preview.source {
        case .staged: return "Staged changes will become these commits."
        case .oldCommit(let oid): return "Commit \(String(oid.prefix(7))) will be split into these commits."
        case .commitRange(let oids):
            let count = oids.count
            let oldest = String(oids.first?.prefix(7) ?? "")
            let newest = String(oids.last?.prefix(7) ?? "")
            return "\(count) commits (\(oldest)…\(newest)) will be recomposed into these commits."
        }
    }

    // MARK: - Group cards

    private func groupCard(at index: Int) -> some View {
        let group = groups[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 18)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
                Text("\(group.files.count) file\(group.files.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if groups.count > 1 {
                    Button {
                        groups.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Drop this group (files won't be committed)")
                }
            }

            TextEditor(text: bindingForMessage(at: index))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 140)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
                )

            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.files, id: \.self) { path in
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
                .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
        )
    }

    private func bindingForMessage(at index: Int) -> Binding<String> {
        Binding(
            get: { groups[index].message },
            set: { groups[index].message = $0 }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Cancel", role: .cancel) {
                store.dismissAISplitPreview()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            if !canApply {
                Text("Every group needs a message.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            Button("Apply") {
                var p = preview
                p.groups = groups
                store.aiSplitPreview = p
                store.applyAISplitPreview()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
    }

    private var canApply: Bool {
        !groups.isEmpty && groups.allSatisfy { !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// Loading placeholder shown while the AI is generating the split proposal.
struct AISplitLoadingSheet: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            LottieView(name: "downloading", loopMode: .loop, size: CGSize(width: 96, height: 96))
            Text("Analyzing changes…")
                .font(.system(size: 13, weight: .medium))
            Text("Asking the AI to group the diff into coherent commits.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(28)
        .frame(width: 380)
    }
}
