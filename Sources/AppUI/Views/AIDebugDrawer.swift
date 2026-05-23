import AppKit
import SwiftUI

/// IDE-style bottom drawer that surfaces the latest AI generation trace
/// (command, stdout, stderr, exit code, generated text). Scoped to the
/// commit panel; resizable vertically, dismissable, escape-closable.
struct AIDebugDrawer: View {
    let store: RepositoryStore
    let containerHeight: CGFloat

    static let minHeight: CGFloat = 140
    static let minimizedHeight: CGFloat = 26
    static let heightDefaultsKey = "avi.ai.debug.height"

    @FocusState private var focused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if store.aiDebugMinimized {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 1)
            } else {
                AIDebugResizeHandle(store: store, containerHeight: containerHeight)
            }
            AIDebugDrawerToolbar(store: store)
            if !store.aiDebugMinimized {
                Divider()
                AIDebugBody(
                    run: store.aiDebugLatestRun,
                    preview: store.aiPendingPreview
                )
            }
        }
        .frame(height: store.aiDebugMinimized ? Self.minimizedHeight + 1 : clampedHeight)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .focusable()
        .focused($focused)
        .onAppear {
            focused = true
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI debug drawer")
    }

    private var clampedHeight: CGFloat {
        let maxAllowed = max(Self.minHeight, containerHeight * 0.7)
        return min(max(store.aiDebugDrawerHeight, Self.minHeight), maxAllowed)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // escape
                if store.aiDebugDrawerVisible {
                    Task { @MainActor in store.closeAIDebugDrawer() }
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    static func loadHeight() -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: heightDefaultsKey)
        return stored > 0 ? CGFloat(stored) : 220
    }

    static func saveHeight(_ value: CGFloat) {
        UserDefaults.standard.set(Double(value), forKey: heightDefaultsKey)
    }
}

private struct AIDebugResizeHandle: View {
    let store: RepositoryStore
    let containerHeight: CGFloat

    @State private var dragStartHeight: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 1)
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? store.aiDebugDrawerHeight
                        if dragStartHeight == nil { dragStartHeight = start }
                        let proposed = start - value.translation.height
                        let maxAllowed = max(AIDebugDrawer.minHeight, containerHeight * 0.7)
                        store.aiDebugDrawerHeight = min(max(proposed, AIDebugDrawer.minHeight), maxAllowed)
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                        AIDebugDrawer.saveHeight(store.aiDebugDrawerHeight)
                    }
            )
            .accessibilityLabel("Resize debug drawer")
    }
}

private struct AIDebugDrawerToolbar: View {
    let store: RepositoryStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "ladybug")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("AI Debug")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            statusChip

            Spacer()

            iconButton("doc.on.doc", help: "Copy logs", enabled: store.aiDebugLatestRun != nil) {
                store.copyAIDebugLog()
            }
            iconButton("trash", help: "Clear logs", enabled: store.aiDebugLatestRun != nil) {
                store.clearAIDebugBuffer()
            }
            iconButton(
                store.aiDebugMinimized ? "chevron.up.square" : "chevron.down.square",
                help: store.aiDebugMinimized ? "Expand drawer" : "Minimize drawer"
            ) {
                store.toggleAIDebugMinimized()
            }
            iconButton("xmark", help: "Close drawer") {
                store.closeAIDebugDrawer()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }

    @ViewBuilder
    private var statusChip: some View {
        if let run = store.aiDebugLatestRun {
            let (text, color) = chipStyle(for: run)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .frame(minHeight: 16)
                .background(Capsule().fill(color.opacity(0.16)))
                .foregroundStyle(color)
        } else if store.isGeneratingCommitMessage {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("running")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("idle")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func chipStyle(for run: AIRunResult) -> (String, Color) {
        if run.timedOut { return ("timeout · \(run.durationMS)ms", .orange) }
        if let exit = run.exitCode, exit != 0 { return ("exit \(exit) · \(run.durationMS)ms", .red) }
        return ("ok · \(run.durationMS)ms", .green)
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct AIDebugBody: View {
    let run: AIRunResult?
    let preview: AIPendingPreview?

    var body: some View {
        if let run {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    metaRow(run)
                    AIDebugSection(title: "Command", text: run.commandLine, mono: true)
                    AIDebugSection(title: "Stdout", text: run.stdout, mono: true)
                    AIDebugSection(title: "Stderr", text: run.stderr, mono: true, tint: .red)
                    if let preview {
                        AIDebugSection(title: "Generated", text: preview.combined, mono: false)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No AI runs yet")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Run Generate to populate this drawer.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func metaRow(_ run: AIRunResult) -> some View {
        HStack(spacing: 12) {
            metaPair("provider", run.provider)
            metaPair("model", run.model)
            metaPair("exit", run.exitCode.map(String.init) ?? "—")
            metaPair("duration", "\(run.durationMS)ms")
            if run.timedOut {
                Text("timed out")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 16)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    private func metaPair(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

private struct AIDebugSection: View {
    let title: String
    let text: String
    var mono: Bool = false
    var tint: Color = .primary

    @State private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if text.isEmpty {
                    Text("(empty)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if expanded, !text.isEmpty {
                ScrollView(.vertical) {
                    Text(text)
                        .font(.system(size: 11, design: mono ? .monospaced : .default))
                        .foregroundStyle(tint)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                )
            }
        }
    }
}
