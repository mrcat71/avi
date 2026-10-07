import AppKit
@testable import AppUI
import Foundation
import SwiftUI
import Testing

@MainActor
@Suite("Workspace restoration")
struct WorkspaceRestorationTests {
    @Test func startupViewKeepsRestoringAfterTheFirstTabAppears() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        for name in ["a", "b", "c"] {
            await original.open(fixture.url(name))
        }
        let relaunched = fixture.session()
        _ = NSApplication.shared
        let host = NSHostingView(rootView: RootView(session: relaunched))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let deadline = Date().addingTimeInterval(5)
        while relaunched.selectedRepository?.root != fixture.url("c"), Date() < deadline {
            host.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        #expect(relaunched.repositories.compactMap { $0.root } == [fixture.url("a"), fixture.url("b"), fixture.url("c")])
        #expect(relaunched.selectedRepository?.root == fixture.url("c"))
        #expect(relaunched.errorMessage == nil)
    }

    @Test func relaunchRestoresTabOrderAndSelectedRepository() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        for name in ["a", "b", "c"] {
            await original.open(fixture.url(name))
        }
        original.select(original.repositories[1].id)
        original.moveRepository(original.repositories[2].id, toPlaceOf: original.repositories[0].id)
        let expectedOrder = original.repositories.compactMap { $0.root }

        let relaunched = fixture.session()
        await relaunched.restore()

        #expect(relaunched.repositories.compactMap { $0.root } == expectedOrder)
        #expect(relaunched.selectedRepository?.root == fixture.url("b"))
        #expect(relaunched.errorMessage == nil)
        await relaunched.restore()
        #expect(relaunched.repositories.count == 3)
    }

    @Test func closedTabsStayClosedIncludingAnEmptyWorkspace() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        await original.open(fixture.url("a"))
        await original.open(fixture.url("b"))
        original.close(original.repositories[1].id)

        let relaunched = fixture.session()
        await relaunched.restore()
        #expect(relaunched.repositories.compactMap { $0.root } == [fixture.url("a")])
        relaunched.close(relaunched.repositories[0].id)

        let empty = fixture.session()
        await empty.restore()
        #expect(empty.repositories.isEmpty)
        #expect(empty.selectedRepository == nil)
    }

    @Test func backgroundTabsAreSavedWithoutStealingTheSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        await original.open(fixture.url("a"))
        _ = await original.openInBackground(fixture.url("b"))

        let relaunched = fixture.session()
        await relaunched.restore()

        #expect(relaunched.repositories.compactMap { $0.root } == [fixture.url("a"), fixture.url("b")])
        #expect(relaunched.selectedRepository?.root == fixture.url("a"))
    }

    @Test func unavailableSelectedRepositoryDoesNotBlockOtherTabs() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        for name in ["a", "b", "c"] {
            await original.open(fixture.url(name))
        }
        original.select(original.repositories[1].id)
        fixture.git.repositoryRootHandler = { url in
            if url.lastPathComponent == "b" {
                throw CocoaError(.fileNoSuchFile)
            }
            return url
        }

        let relaunched = fixture.session()
        await relaunched.restore()

        #expect(relaunched.repositories.compactMap { $0.root } == [fixture.url("a"), fixture.url("c")])
        #expect(relaunched.selectedRepository?.root == fixture.url("a"))
        #expect(relaunched.errorMessage?.contains(fixture.url("b").path) == true)
        let nextLaunch = fixture.session()
        await nextLaunch.restore()
        #expect(nextLaunch.errorMessage == nil)
        #expect(nextLaunch.repositories.count == 2)
    }

    @Test func freshInstallAndUnreadableStateLeaveThePickerAvailable() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let fresh = fixture.session()
        await fresh.restore()
        #expect(fresh.repositories.isEmpty)
        #expect(fresh.errorMessage == nil)

        fixture.defaults.set(Data("not JSON".utf8), forKey: "avi.workspaceSession")
        let broken = fixture.session()
        await broken.restore()
        #expect(broken.repositories.isEmpty)
        #expect(broken.errorMessage != nil)
        await broken.open(fixture.url("a"))
        let recovered = fixture.session()
        await recovered.restore()
        #expect(recovered.repositories.count == 1)
    }

    @Test(arguments: [false, true])
    func userActionsWinAndPartialRestoreDoesNotOverwriteSavedTabs(openNewTab: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        for name in ["a", "b", "c"] {
            await original.open(fixture.url(name))
        }
        let saved = fixture.defaults.data(forKey: "avi.workspaceSession")
        let gate = Gate()
        fixture.git.repositoryRootHandler = { url in
            if url.lastPathComponent == "b" {
                await gate.waitOnce()
            }
            return url
        }
        let relaunched = fixture.session()
        let restoration = Task { await relaunched.restore() }
        defer { gate.resume() }
        let deadline = Date().addingTimeInterval(5)
        while !gate.isWaiting, Date() < deadline {
            await Task.yield()
        }
        #expect(gate.isWaiting)
        #expect(fixture.defaults.data(forKey: "avi.workspaceSession") == saved)
        if openNewTab {
            await relaunched.open(fixture.url("new"))
        } else {
            relaunched.select(relaunched.repositories[0].id)
        }
        gate.resume()
        await restoration.value

        let expected = fixture.url(openNewTab ? "new" : "a")
        #expect(relaunched.selectedRepository?.root == expected)
        #expect(relaunched.repositories.count == (openNewTab ? 4 : 3))
        let nextLaunch = fixture.session()
        await nextLaunch.restore()
        #expect(nextLaunch.selectedRepository?.root == expected)
        #expect(nextLaunch.repositories.count == relaunched.repositories.count)
    }

    @Test func cancelledStartupKeepsTheCompleteSavedWorkspace() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        for name in ["a", "b", "c"] {
            await original.open(fixture.url(name))
        }
        let saved = fixture.defaults.data(forKey: "avi.workspaceSession")
        let gate = Gate()
        fixture.git.repositoryRootHandler = { url in
            if url.lastPathComponent == "b" {
                await gate.waitOnce()
            }
            return url
        }
        let relaunched = fixture.session()
        let restoration = Task { await relaunched.restore() }
        defer { gate.resume() }
        let deadline = Date().addingTimeInterval(5)
        while !gate.isWaiting, Date() < deadline {
            await Task.yield()
        }
        #expect(gate.isWaiting)
        restoration.cancel()
        gate.resume()
        await restoration.value

        #expect(fixture.defaults.data(forKey: "avi.workspaceSession") == saved)
        let nextLaunch = fixture.session()
        await nextLaunch.restore()
        #expect(nextLaunch.repositories.count == 3)
        #expect(nextLaunch.selectedRepository?.root == fixture.url("c"))
    }

    @Test func openingARestoringRepositoryDoesNotDuplicateItsTab() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = fixture.session()
        await original.open(fixture.url("a"))
        await original.open(fixture.url("b"))
        let race = OpeningRace()
        fixture.git.repositoryRootHandler = { url in
            if url.lastPathComponent == "b" {
                await race.arrive()
            }
            return url
        }
        let relaunched = fixture.session()
        let restoration = Task { await relaunched.restore() }
        defer { race.restore.resume(); race.explicitOpen.resume() }
        await waitFor(race.restore)
        let opening = Task { await relaunched.open(fixture.url("b")) }
        await waitFor(race.explicitOpen)
        race.restore.resume()
        await restoration.value
        race.explicitOpen.resume()
        await opening.value

        #expect(relaunched.repositories.compactMap { $0.root } == [fixture.url("a"), fixture.url("b")])
        #expect(relaunched.selectedRepository?.root == fixture.url("b"))
    }

    private func waitFor(_ gate: Gate) async {
        let deadline = Date().addingTimeInterval(5)
        while !gate.isWaiting, Date() < deadline {
            await Task.yield()
        }
        #expect(gate.isWaiting)
    }

    @MainActor
    private final class OpeningRace {
        let restore = Gate()
        let explicitOpen = Gate()
        private var calls = 0

        func arrive() async {
            calls += 1
            let call = calls
            if call == 1 {
                await restore.waitOnce()
            }
            if call == 3 {
                await explicitOpen.waitOnce()
            }
        }
    }

    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var hasWaited = false
        var isWaiting: Bool {
            continuation != nil
        }

        func waitOnce() async {
            guard !hasWaited else { return }
            hasWaited = true
            await withCheckedContinuation { continuation = $0 }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private final class Fixture {
        let git = Fixtures.clean()
        let defaults: UserDefaults
        let root: URL
        private let suite = "avi-workspace-tests-\(UUID().uuidString)"
        private var sessions: [WorkspaceSession] = []

        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).resolvingSymlinksInPath()
            for name in ["a", "b", "c", "new"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
        }

        func url(_ name: String) -> URL {
            root.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        }

        func session() -> WorkspaceSession {
            let session = WorkspaceSession(git: git, defaults: defaults)
            sessions.append(session)
            return session
        }

        func close() {
            for session in sessions {
                for repository in session.repositories {
                    repository.stopBackgroundObservation()
                }
            }
            defaults.removePersistentDomain(forName: suite)
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                Issue.record("Unable to clean up workspace fixture: \(error)")
            }
        }
    }
}
