import AppKit
import SwiftUI

struct WelcomeView: View {
    let openRepository: (URL) -> Void
    @State private var recents = RecentRepositories.urls()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Avi")
                .font(.largeTitle.bold())

            Button("Open Repository...", action: openPanel)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            openRepository(url)
                        }
                        .buttonStyle(.link)
                        .help(url.path)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
