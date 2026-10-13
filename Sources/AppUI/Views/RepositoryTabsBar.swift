import AppKit
import GitKit
import SwiftUI

/// The repository tabs above the workspace, one per repository: the
/// worktrees of a repository share its tab. Resting the pointer on a tab with
/// several worktrees lists them, and clicking one switches the tab to it.
struct RepositoryTabsBar: View {
    let session: WorkspaceSession
    let openRepositoryPicker: () -> Void

    /// The tab being dragged. The tabs it passes move aside as it goes, so the
    /// order is already final when you let go.
    private struct TabDrag {
        let id: RepositoryTab.ID
        /// The tab's frame in the rows when the drag began.
        let start: CGRect
        /// How far the tab is drawn from its place, to stay under the pointer.
        var offset: CGSize
    }

    static let tabHeight: CGFloat = 24
    private static let tabSpacing: CGFloat = 2
    private static let rowSpacing: CGFloat = 2
    private static let rowsPadding: CGFloat = 4
    /// Rows shown at most; more tabs than fit in them scroll.
    private static let maxRows = 3
    private static let maxRowsHeight = CGFloat(maxRows) * tabHeight + CGFloat(maxRows - 1) * rowSpacing + 2 * rowsPadding

    @State private var tabSizes: [RepositoryTab.ID: CGSize] = [:]
    /// The width the rows wrap in.
    @State private var rowsWidth: CGFloat = 0
    @State private var drag: TabDrag?
    /// Turns false on its own when a drag ends or is cancelled, which also
    /// settles a tab whose gesture never reported its end.
    @GestureState private var isDraggingTab = false
    /// The worktree list that opens under a tab.
    @State private var hoverPanel = HoverPanel()

    /// One row while the tabs fit in it; more tabs wrap onto further rows, and
    /// past three rows they scroll. Sized by layout rather than measured,
    /// because switching repositories rebuilds the bar.
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            MaxHeightLayout(maxHeight: Self.maxRowsHeight) {
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            rows
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        // The tab you switch to, such as a repository opened
                        // again, comes into view.
                        .onChange(of: session.selectedTabID, initial: true) { _, id in
                            if let id {
                                proxy.scrollTo(id)
                            }
                        }
                    }
                    .frame(height: Self.maxRowsHeight)
                }
            }

            Button(action: openRepositoryPicker) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open another repository")
            .padding(.top, Self.rowsPadding + (Self.tabHeight - 22) / 2)
        }
        .padding(.horizontal, 8)
        .background(DS.Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Glass.edgeStroke)
                .frame(height: 0.6)
        }
        .onChange(of: isDraggingTab) { _, dragging in
            if !dragging {
                endDrag()
            }
        }
        // Switching worktrees or repositories rebuilds the bar.
        .onDisappear {
            hoverPanel.hide()
        }
    }

    private var rows: some View {
        TabRowsLayout(spacing: Self.tabSpacing, rowSpacing: Self.rowSpacing) {
            ForEach(session.tabs) { tab in
                self.tab(tab)
                    .id(tab.id)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowsWidth = $0 }
        .padding(.vertical, Self.rowsPadding)
    }

    private func tab(_ tab: RepositoryTab) -> some View {
        let isDragged = drag?.id == tab.id
        return RepositoryTabButton(
            tab: tab,
            isSelected: tab.id == session.selectedTabID,
            hoverPanel: hoverPanel,
            select: { session.selectTab(tab.id) },
            close: { session.closeTab(tab.id) },
            worktreeList: { [session] in
                AnyView(TabWorktreeList(session: session, tabID: tab.id, pointerInside: { [hoverPanel] inside in
                    hoverPanel.pointerInPanel(inside)
                }, open: { [hoverPanel] url in
                    hoverPanel.hide()
                    Task { await session.open(url) }
                }))
            }
        )
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tabSizes[tab.id] = $0 }
        .offset(isDragged ? drag?.offset ?? .zero : .zero)
        .zIndex(isDragged ? 1 : 0)
        // The dragged tab takes its new place at once while its offset keeps it
        // under the pointer; only the tabs it passes slide aside.
        .transaction { transaction in
            if isDragged {
                transaction.animation = nil
            }
        }
        // High priority, so a drag that starts on the tab's buttons moves the
        // tab instead of selecting or closing it when you let go.
        .highPriorityGesture(dragGesture(for: tab.id))
        .contextMenu { tabMenu(for: tab) }
    }

    /// Measured in window coordinates: the tab itself moves with the pointer.
    private func dragGesture(for id: RepositoryTab.ID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($isDraggingTab) { _, dragging, _ in dragging = true }
            .onChanged { value in dragTab(id, by: value.translation) }
            .onEnded { _ in endDrag() }
    }

    /// The rows as `TabRowsLayout` lays them out, so the dragged tab's new
    /// place is known before the rows move there.
    private func rowFrames(for sizes: [CGSize]) -> [CGRect] {
        tabRowFrames(sizes: sizes, spacing: Self.tabSpacing, rowSpacing: Self.rowSpacing, width: rowsWidth)
    }

    private func dragTab(_ id: RepositoryTab.ID, by translation: CGSize) {
        hoverPanel.hide()
        let tabs = session.tabs
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var sizes = tabs.map { tabSizes[$0.id] ?? .zero }
        let start = drag.flatMap { $0.id == id ? $0.start : nil } ?? rowFrames(for: sizes)[index]
        let drawn = start.offsetBy(dx: translation.width, dy: translation.height)
        let target = tabDropIndex(
            dragged: index,
            drawnAt: drawn,
            sizes: sizes,
            spacing: Self.tabSpacing,
            rowSpacing: Self.rowSpacing,
            width: rowsWidth
        )
        sizes.insert(sizes.remove(at: index), at: target)
        let place = rowFrames(for: sizes)[target]
        drag = TabDrag(id: id, start: start, offset: CGSize(width: drawn.minX - place.minX, height: drawn.minY - place.minY))
        if target != index {
            withAnimation(.easeOut(duration: 0.15)) {
                session.moveTab(id, toPlaceOf: tabs[target].id)
            }
        }
    }

    private func endDrag() {
        guard drag != nil else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            drag = nil
        }
    }

    /// Hands the tab's folder to a terminal or Finder, switches worktrees,
    /// and makes the same moves as dragging, for the keyboard and VoiceOver.
    @ViewBuilder
    private func tabMenu(for tab: RepositoryTab) -> some View {
        let tabs = session.tabs
        let index = tabs.firstIndex { $0.id == tab.id }
        if let root = tab.active.root {
            Button("Copy Path") {
                FolderActions.copyPath(root)
            }
            Button("Open in Terminal") {
                FolderActions.openInTerminal(root)
            }
            Button("Reveal in Finder") {
                FolderActions.revealInFinder(root)
            }
            Divider()
        }
        if tab.worktrees.count > 1 {
            Section("Worktrees") {
                ForEach(tab.worktrees) { worktree in
                    Button {
                        Task { await session.open(worktree.path) }
                    } label: {
                        if tab.isActive(worktree) {
                            Label(TabWorktreeList.title(of: worktree), systemImage: "checkmark")
                        } else {
                            Text(TabWorktreeList.title(of: worktree))
                        }
                    }
                    .disabled(worktree.isPrunable)
                }
            }
            Divider()
        }
        Button("Move Tab Left") {
            if let index, index > 0 {
                session.moveTab(tab.id, toPlaceOf: tabs[index - 1].id)
            }
        }
        .disabled((index ?? 0) == 0)
        Button("Move Tab Right") {
            if let index, index + 1 < tabs.count {
                session.moveTab(tab.id, toPlaceOf: tabs[index + 1].id)
            }
        }
        .disabled(index.map { $0 + 1 >= tabs.count } ?? true)
        Divider()
        if tab.members.count > 1, let name = tab.active.root?.lastPathComponent {
            Button("Close \(name)") {
                session.close(tab.active.id)
            }
        }
        Button("Close Tab") {
            session.closeTab(tab.id)
        }
    }
}

private struct RepositoryTabButton: View {
    let tab: RepositoryTab
    let isSelected: Bool
    let hoverPanel: HoverPanel
    let select: () -> Void
    let close: () -> Void
    /// The list of the repository's worktrees, for the panel under the tab.
    let worktreeList: () -> AnyView

    @State private var isHovering = false
    @State private var anchor = AnchorBox()

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Button(action: select) {
                    HStack(spacing: 6) {
                        indicator
                        Text(tab.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                        if hasWorktrees {
                            worktreeCount
                        }
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 2)
                    .frame(height: RepositoryTabsBar.tabHeight, alignment: .leading)
                    .frame(minWidth: 110, maxWidth: 180)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The worktree list says all of it; a tooltip would cover it.
                .help(ifAny: hasWorktrees ? nil : tabDetail)
                .accessibilityHint(hasWorktrees ? "Its right-click menu switches between the repository's worktrees" : "")

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering || isSelected ? 1 : 0)
                .help(tab.members.count > 1 ? "Close the repository and its open worktrees" : "Close repository")
                .accessibilityLabel("Close repository")
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.06) : (isHovering ? Color.primary.opacity(0.04) : Color.clear))
            )
            .background(AnchorView { anchor.view = $0 })
            .onHover { hovering in
                isHovering = hovering
                guard hasWorktrees else { return }
                if hovering, let view = anchor.view {
                    hoverPanel.pointerEntered(tab.id, anchor: view, content: worktreeList)
                } else if !hovering {
                    hoverPanel.pointerExited()
                }
            }

            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if tab.hasUnseenProposal {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
                .help("An agent sent commits to review")
                .accessibilityLabel("New proposal")
        } else if tab.changeCount > 0 {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .help("\(tab.changeCount) uncommitted change\(tab.changeCount == 1 ? "" : "s")")
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
    }

    private var worktreeCount: some View {
        HStack(spacing: 2) {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 9))
            Text("\(tab.worktrees.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tab.worktrees.count) worktrees")
    }

    private var hasWorktrees: Bool {
        tab.worktrees.count > 1
    }

    /// The branch, then the folder, which for an agent's worktree says more
    /// than its generated name.
    private var tabDetail: String {
        guard let path = tab.active.root?.path else { return headDetail }
        return "\(headDetail)\n\(path)"
    }

    private var headDetail: String {
        let repository = tab.active
        if let name = repository.branch?.name {
            let changes = repository.entries.count
            return changes == 0 ? name : "\(name), \(changes) changes"
        }
        if repository.branch?.isDetached == true {
            return "Detached HEAD"
        }
        return "Loading"
    }
}

private extension View {
    @ViewBuilder
    func help(ifAny text: String?) -> some View {
        if let text {
            help(text)
        } else {
            self
        }
    }
}

/// Holds the tab's NSView for anchoring the worktree list under it.
@MainActor
private final class AnchorBox {
    weak var view: NSView?
}

/// The worktrees of a repository, under its tab: which one the tab shows,
/// each one's branch, and what waits in it. Clicking one switches to it.
struct TabWorktreeList: View {
    let session: WorkspaceSession
    let tabID: RepositoryTab.ID
    let pointerInside: (Bool) -> Void
    let open: (URL) -> Void

    @State private var hovered: Worktree.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let tab = session.tabs.first(where: { $0.id == tabID }) {
                HStack(spacing: 6) {
                    Text(tab.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(tab.worktrees.count) worktrees")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 3)
                ForEach(tab.worktrees) { worktree in
                    row(worktree, in: tab)
                }
            }
        }
        .padding(6)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
        )
        .onHover(perform: pointerInside)
    }

    private func row(_ worktree: Worktree, in tab: RepositoryTab) -> some View {
        let isActive = tab.isActive(worktree)
        let member = tab.member(for: worktree)
        let changes = member?.entries.count ?? tab.active.worktreeChanges[worktree.id] ?? 0
        return Button {
            open(worktree.path)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isActive ? "checkmark" : "square.split.2x1")
                    .font(.system(size: 10, weight: isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(worktree.path.lastPathComponent)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if worktree.id == tab.active.worktrees.first?.id {
                            Text("main")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                                .fixedSize()
                        }
                        if worktree.isPrunable {
                            Text("folder missing")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.red)
                                .fixedSize()
                        }
                    }
                    Text(Self.headLabel(of: worktree))
                        .font(.system(size: 10, design: worktree.isDetached ? .monospaced : .default))
                        .foregroundStyle(worktree.isDetached ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if member?.hasUnseenProposal == true {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("New proposal")
                }
                if changes > 0 {
                    Text("\(changes)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.16)))
                        .foregroundStyle(.orange)
                        .fixedSize()
                        .accessibilityLabel(changes == 1 ? "1 uncommitted change" : "\(changes) uncommitted changes")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered == worktree.id && !worktree.isPrunable
                        ? Color.primary.opacity(0.08)
                        : (isActive ? Color.accentColor.opacity(0.12) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(worktree.isPrunable)
        .onHover { inside in
            if inside {
                hovered = worktree.id
            } else if hovered == worktree.id {
                hovered = nil
            }
        }
        .help(worktree.path.path)
        .accessibilityLabel("\(Self.title(of: worktree))\(isActive ? ", shown" : "")")
    }

    /// The worktree's folder and what it has checked out, for menus.
    static func title(of worktree: Worktree) -> String {
        "\(worktree.path.lastPathComponent) · \(headLabel(of: worktree))"
    }

    static func headLabel(of worktree: Worktree) -> String {
        if let branch = worktree.branch {
            return branch
        }
        return worktree.headOID.map { "detached \($0.prefix(8))" } ?? "detached"
    }
}
