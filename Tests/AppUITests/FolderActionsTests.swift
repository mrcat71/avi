@testable import AppUI
import Foundation
import GitKit
import Testing

private let terminal = "/System/Applications/Utilities/Terminal.app"

@MainActor
@Suite("Folder actions")
struct FolderActionsTests {
    @Test(arguments: [
        ("", terminal),
        ("   ", terminal),
        ("/Applications/No Such Terminal.app", terminal),
        (NSTemporaryDirectory(), NSTemporaryDirectory()),
        ("~", NSHomeDirectory())
    ])
    func openInTerminalUsesTheConfiguredAppWhenItExists(configured: String, expected: String) {
        let app = FolderActions.terminalApp(configured: configured)
        #expect(app.standardizedFileURL.path == URL(fileURLWithPath: expected).standardizedFileURL.path)
    }

    @Test func thePaletteCopiesTheTabsPathAndOpensATerminalThere() async {
        let root = URL(fileURLWithPath: "/tmp/avi-folder-actions", isDirectory: true)
        let store = RepositoryStore(git: Fixtures.clean())
        await store.open(root)
        store.stopBackgroundObservation()

        let commands = CommandRegistry.commands(store: store, setSelection: { _ in }, openCreateBranch: {})
        let folderCommands = commands.filter { $0.subtitle == root.path }.map(\.id)

        #expect(folderCommands.contains("repo.copyPath"))
        #expect(folderCommands.contains("repo.openInTerminal"))
    }
}
