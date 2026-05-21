import AppKit
import SwiftUI

struct WelcomeView: View {
    let openRepository: (URL) -> Void
    @State private var recents = RecentRepositories.urls()

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            VStack(spacing: DS.Spacing.md) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(DS.Palette.accent)
                Text("Avi")
                    .font(.system(size: 24, weight: .semibold))
                Text("A modern git client")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            AviButton("Open Repository", icon: "folder", variant: .primary, size: .medium, action: openPanel)

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Recent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.bottom, DS.Spacing.xs)
                    ForEach(recents, id: \.self) { url in
                        RecentRow(url: url) { openRepository(url) }
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, DS.Spacing.md)
            }
        }
        .padding(DS.Spacing.xxl + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.surface)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openRepository(url)
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "folder")
                    .font(.system(size: DS.IconScale.md))
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(url.deletingLastPathComponent().path)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, DS.Spacing.lg - 2)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isHovering ? DS.Palette.rowHoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(url.path)
        .accessibilityLabel("Open \(url.lastPathComponent)")
    }
}
