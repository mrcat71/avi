import AppKit
import GitKit
import SwiftUI

struct RepositorySidebarView: View {
    @Binding var selection: RepositorySelection
    let store: RepositoryStore

    @State private var filter = ""
    @State private var branchesExpanded = true
    @State private var remoteBranchesExpanded = true
    @State private var tagsExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    primaryItems

                    sectionFilter

                    branchesSection
                    remoteBranchesSection
                    tagsSection
                }
                .padding(.bottom, 12)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(store.root?.lastPathComponent ?? "Avi")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading)
                .help("Refresh")
                .accessibilityLabel("Refresh repository")
            }

            if let branch = store.branch {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10))
                    Text(branchLabel(branch))
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var primaryItems: some View {
        VStack(spacing: 1) {
            PrimarySidebarRow(
                title: "Local Changes",
                systemImage: "pencil",
                badge: store.entries.count,
                isSelected: selection == .localChanges,
                action: { selection = .localChanges }
            )

            PrimarySidebarRow(
                title: "All Commits",
                systemImage: "clock.arrow.circlepath",
                badge: nil,
                isSelected: isAllCommitsSelected,
                action: { selection = .allCommits }
            )
        }
        .padding(.horizontal, 8)
    }

    private var sectionFilter: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter refs", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 8)
    }

    private var isAllCommitsSelected: Bool {
        switch selection {
        case .allCommits: return true
        default: return false
        }
    }

    @ViewBuilder
    private var branchesSection: some View {
        SidebarSectionHeader(
            title: "Branches",
            count: store.refs.localBranches.count,
            isExpanded: $branchesExpanded
        )

        if branchesExpanded {
            VStack(spacing: 1) {
                ForEach(filteredLocalBranches) { ref in
                    LocalBranchRow(
                        ref: ref,
                        store: store,
                        isSelected: selection == .branch(name: ref.name),
                        select: {
                            selection = .branch(name: ref.name)
                            Task { await store.selectCommit(commitForRef(ref)) }
                        },
                        checkout: {
                            Task { await store.checkout(ref) }
                        }
                    )
                }
                if filteredLocalBranches.isEmpty {
                    EmptySectionRow(
                        text: filter.isEmpty ? "No local branches" : "No matches",
                        action: filter.isEmpty ? nil : { filter = "" }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var remoteBranchesSection: some View {
        SidebarSectionHeader(
            title: "Remote Branches",
            count: store.refs.remoteBranches.count,
            isExpanded: $remoteBranchesExpanded
        )

        if remoteBranchesExpanded {
            VStack(alignment: .leading, spacing: 1) {
                let groups = remoteGroups
                if groups.isEmpty {
                    EmptySectionRow(
                        text: filter.isEmpty ? "No remote branches" : "No matches",
                        action: filter.isEmpty ? nil : { filter = "" }
                    )
                } else {
                    ForEach(groups, id: \.name) { group in
                        RemoteGroupView(
                            name: group.name,
                            refs: group.refs,
                            localBranches: store.refs.localBranches,
                            selection: $selection,
                            store: store
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !store.refs.tags.isEmpty {
            SidebarSectionHeader(
                title: "Tags",
                count: store.refs.tags.count,
                isExpanded: $tagsExpanded
            )

            if tagsExpanded {
                VStack(spacing: 1) {
                    ForEach(filteredTags) { ref in
                        TagRow(
                            ref: ref,
                            isSelected: selection == .tag(name: ref.name),
                            select: {
                                selection = .tag(name: ref.name)
                                Task { await store.selectCommit(commitForRef(ref)) }
                            }
                        )
                    }
                    if filteredTags.isEmpty {
                        EmptySectionRow(
                            text: filter.isEmpty ? "No tags" : "No matches",
                            action: filter.isEmpty ? nil : { filter = "" }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func commitForRef(_ ref: GitReference) -> CommitSummary? {
        store.historyRows.first(where: { $0.commit.oid == ref.oid })?.commit
    }

    private var filteredLocalBranches: [GitReference] {
        let sorted = store.refs.localBranches.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return filtered(sorted)
    }

    private var filteredTags: [GitReference] {
        TagSort.descending(filtered(store.refs.tags))
    }

    private func filtered(_ refs: [GitReference]) -> [GitReference] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return refs }
        return refs.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    private var remoteGroups: [(name: String, refs: [GitReference])] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let source: [GitReference]
        if needle.isEmpty {
            source = store.refs.remoteBranches
        } else {
            source = store.refs.remoteBranches.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        }
        let grouped = Dictionary(grouping: source) { ref in
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

private struct PrimarySidebarRow: View {
    let title: String
    let systemImage: String
    let badge: Int?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.aviDensity) private var density
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(isSelected ? Color.white : .secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(
                        Capsule().fill(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.10))
                    )
                    .foregroundStyle(isSelected ? Color.white : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: DS.rowHeight(for: density))
        .foregroundStyle(isSelected ? Color.white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .help(title)
    }

    private var rowFill: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return DS.Color.rowHover }
        return Color.clear
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        AviSectionHeader(title, count: count, isExpanded: $isExpanded)
    }
}

private struct EmptySectionRow: View {
    let text: String
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            if let action {
                Button("Clear", action: action)
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
    }
}

private struct LocalBranchRow: View {
    let ref: GitReference
    let store: RepositoryStore
    let isSelected: Bool
    let select: () -> Void
    let checkout: () -> Void

    @Environment(\.aviDensity) private var density
    @State private var isHovering = false
    @State private var showingRename = false
    @State private var renameValue = ""
    @State private var showingSetUpstream = false
    @State private var upstreamValue = ""
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ref.isCurrent ? "arrow.triangle.branch" : "arrow.triangle.branch")
                .font(.system(size: 10, weight: ref.isCurrent ? .bold : .regular))
                .frame(width: 12)
                .foregroundStyle(iconColor)

            Text(ref.name)
                .font(.system(size: 12, weight: ref.isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(textColor)

            if let upstream = ref.upstream {
                upstreamChip(upstream: upstream)
            }

            aheadBehindChip

            Spacer(minLength: 4)

            if !ref.isCurrent && (isHovering || isSelected) {
                Button(action: checkout) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Check out \(ref.name)")
            }

            if ref.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: DS.compactRowHeight(for: density))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(tooltip)
        .contextMenu {
            branchContextMenu
        }
        .alert("Rename branch", isPresented: $showingRename) {
            TextField("New name", text: $renameValue)
            Button("Rename") {
                let target = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { return }
                Task { await store.renameBranch(from: ref.name, to: target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rename \(ref.name) to:")
        }
        .alert("Set upstream", isPresented: $showingSetUpstream) {
            TextField("origin/<branch>", text: $upstreamValue)
            Button("Set") {
                let target = upstreamValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { return }
                Task { await store.setUpstream(branch: ref.name, upstream: target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Track which remote branch?")
        }
        .confirmationDialog("Delete branch \(ref.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await store.deleteBranch(named: ref.name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Git will refuse if the branch has unmerged changes.")
        }
    }

    @ViewBuilder
    private var branchContextMenu: some View {
        if !ref.isCurrent {
            Button("Checkout", action: checkout)
        }
        Button("Create Branch From Here") {
            NotificationCenter.default.post(name: .aviCreateBranch, object: ref.name)
        }
        Divider()
        Button("Rename…") {
            renameValue = ref.name
            showingRename = true
        }
        if !ref.isCurrent {
            Button("Delete…", role: .destructive) {
                confirmingDelete = true
            }
        }
        Divider()
        Button("Push") {
            Task { await store.push(branch: ref.name) }
        }
        .disabled(ref.upstream == nil)
        Button("Pull") {
            Task { await store.pull(branch: ref.name) }
        }
        .disabled(ref.upstream == nil)
        Divider()
        Button(ref.upstream == nil ? "Set Upstream…" : "Change Upstream…") {
            upstreamValue = ref.upstream ?? "origin/\(ref.name)"
            showingSetUpstream = true
        }
        if ref.upstream != nil {
            Button("Unset Upstream") {
                Task { await store.unsetUpstream(branch: ref.name) }
            }
        }
        Divider()
        Button("Copy Branch Name") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(ref.name, forType: .string)
        }
    }

    @ViewBuilder
    private func upstreamChip(upstream: String) -> some View {
        let tint = ref.isUpstreamGone ? Color.orange : Color.secondary
        Text(ref.isUpstreamGone ? "\(upstream) gone" : upstream)
            .font(.system(size: 10))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint.opacity(0.15))
            )
            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : tint)
            .layoutPriority(-1)
    }

    @ViewBuilder
    private var aheadBehindChip: some View {
        if let ahead = ref.ahead, ahead > 0 {
            chip(text: "↑\(ahead)", color: .green)
        }
        if let behind = ref.behind, behind > 0 {
            chip(text: "↓\(behind)", color: .blue)
        }
        if ref.upstream != nil && ref.ahead == nil && ref.behind == nil && !ref.isUpstreamGone {
            chip(text: "✓", color: .green)
        }
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.16))
            )
            .foregroundStyle(isSelected ? Color.white : color)
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return ref.isCurrent ? Color.accentColor : .blue
    }

    private var textColor: Color {
        if isSelected { return .white }
        return ref.isCurrent ? Color.accentColor : .primary
    }

    private var rowFill: Color {
        if isSelected { return Color.accentColor }
        if ref.isCurrent { return Color.accentColor.opacity(0.10) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color.clear
    }

    private var tooltip: String {
        var parts: [String] = [ref.isCurrent ? "Current branch" : "Local branch", ref.name]
        if let upstream = ref.upstream {
            parts.append("→ \(upstream)")
        }
        if let ahead = ref.ahead { parts.append("ahead \(ahead)") }
        if let behind = ref.behind { parts.append("behind \(behind)") }
        if ref.isUpstreamGone { parts.append("upstream gone") }
        return parts.joined(separator: " · ")
    }
}

private struct RemoteGroupView: View {
    let name: String
    let refs: [GitReference]
    let localBranches: [GitReference]
    @Binding var selection: RepositorySelection
    let store: RepositoryStore

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(refs.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(refs) { ref in
                    RemoteBranchRow(
                        ref: ref,
                        localBranches: localBranches,
                        isSelected: selection == .remoteBranch(name: ref.name),
                        select: {
                            selection = .remoteBranch(name: ref.name)
                            Task { await store.selectCommit(commitForRef(ref)) }
                        },
                        track: {
                            Task { await store.checkout(ref) }
                        }
                    )
                }
            }
        }
    }

    private func commitForRef(_ ref: GitReference) -> CommitSummary? {
        store.historyRows.first(where: { $0.commit.oid == ref.oid })?.commit
    }
}

private struct RemoteBranchRow: View {
    let ref: GitReference
    let localBranches: [GitReference]
    let isSelected: Bool
    let select: () -> Void
    let track: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .font(.system(size: 10))
                .frame(width: 12)
                .foregroundStyle(isSelected ? .white : .purple)
                .padding(.leading, 14)

            Text(branchName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : .primary)

            Spacer(minLength: 4)

            trackingChip

            if isHovering || isSelected {
                Button(action: track) {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Create local tracking branch")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(tooltip)
        .contextMenu {
            Button("Create Local Branch From Here") {
                NotificationCenter.default.post(name: .aviCreateBranch, object: ref.name)
            }
            Button("Track (Checkout New Branch)", action: track)
            Divider()
            Button("Copy Ref Name") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(ref.name, forType: .string)
            }
        }
    }

    private var branchName: String {
        ref.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? ref.name
    }

    private var trackingLocal: GitReference? {
        localBranches.first { $0.upstream == ref.name }
    }

    @ViewBuilder
    private var trackingChip: some View {
        if let local = trackingLocal {
            Text("tracked by \(local.name)")
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.15))
                )
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.green)
        }
    }

    private var rowFill: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color.clear
    }

    private var tooltip: String {
        var parts: [String] = ["Remote branch", ref.name]
        if let local = trackingLocal {
            parts.append("tracked by \(local.name)")
        } else {
            parts.append("no local branch")
        }
        return parts.joined(separator: " · ")
    }
}

private struct TagRow: View {
    let ref: GitReference
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false
    @State private var showingPopover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10))
                .frame(width: 12)
                .foregroundStyle(isSelected ? .white : .orange)

            Text(ref.name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(isSelected ? Color.white.opacity(0.20) : Color.orange.opacity(0.15))
                )
                .foregroundStyle(isSelected ? Color.white : Color.orange)
                .lineLimit(1)
                .truncationMode(.middle)

            if ref.annotatedMessage != nil {
                Image(systemName: "text.bubble")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.6))
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if isHovering { showingPopover = true }
                }
            } else {
                showingPopover = false
            }
        }
        .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
            TagPopover(ref: ref)
        }
        .contextMenu {
            Button("Checkout (detach)", action: select)
            Divider()
            Button("Copy Tag Name") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(ref.name, forType: .string)
            }
            Button("Copy Commit SHA") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(ref.oid, forType: .string)
            }
        }
    }

    private var rowFill: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color.clear
    }
}

struct TagPopover: View {
    let ref: GitReference

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Type", ref.annotatedMessage != nil ? "Annotated tag" : "Lightweight tag")
            row("Name", ref.name)
            row("Commit", String(ref.oid.prefix(12)))
            if let date = ref.taggerDate {
                row("Date", date.formatted(.dateTime.year().month().day().hour().minute()))
            }
            if let message = ref.annotatedMessage {
                Divider()
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            if let subject = ref.subject {
                Divider()
                Text(subject)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: key == "Commit" ? .monospaced : .default))
                .textSelection(.enabled)
        }
    }
}
