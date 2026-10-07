@testable import AppUI
import Foundation
import GitKit
import Testing

@Suite("Automatic fetch")
@MainActor
struct AutoFetchTests {
    struct DueCase: Sendable {
        let name: String
        let interval: TimeInterval?
        /// Age of FETCH_HEAD; nil when the repository never fetched.
        let fetchedAgo: TimeInterval?
        let hasRemote: Bool
        let fetches: Bool
    }

    nonisolated static let dueCases: [DueCase] = [
        DueCase(name: "auto-fetch turned off", interval: nil, fetchedAgo: nil, hasRemote: true, fetches: false),
        DueCase(name: "never fetched", interval: 300, fetchedAgo: nil, hasRemote: true, fetches: true),
        DueCase(name: "last fetch older than the interval", interval: 300, fetchedAgo: 600, hasRemote: true, fetches: true),
        DueCase(name: "last fetch within the interval", interval: 300, fetchedAgo: 60, hasRemote: true, fetches: false),
        DueCase(name: "no remote to fetch from", interval: 300, fetchedAgo: nil, hasRemote: false, fetches: false)
    ]

    @Test(arguments: dueCases)
    func fetchesOnlyWhenDue(_ testCase: DueCase) async throws {
        let fake = provider(hasRemote: testCase.hasRemote)
        let store = try await openStore(provider: fake, fetchedAgo: testCase.fetchedAgo)

        await store.autoFetchIfDue(interval: testCase.interval)

        #expect(fake.fetchCalls == (testCase.fetches ? [nil] : []), "\(testCase.name)")
        #expect(!store.isAutoFetching, "\(testCase.name)")
    }

    struct IntervalCase: Sendable {
        let minutes: Int
        let seconds: TimeInterval?
    }

    @Test(arguments: [
        IntervalCase(minutes: 5, seconds: 300),
        IntervalCase(minutes: 0, seconds: nil),
        IntervalCase(minutes: -1, seconds: nil)
    ])
    func intervalComesFromMinutesInTheConfig(_ testCase: IntervalCase) {
        #expect(GitConfig(fetchInterval: testCase.minutes).autoFetchInterval == testCase.seconds)
    }

    @Test func newConfigsFetchEveryFiveMinutes() {
        #expect(GitConfig().autoFetchInterval == 300)
    }

    @Test func aFailureStaysOutOfTheWayUntilTheNextInterval() async throws {
        let fake = provider()
        fake.fetchError = .commandFailed(
            command: "git fetch --all --prune --progress",
            exitCode: 128,
            stderr: "fatal: unable to access 'https://example.com/repo.git/': Could not resolve host: example.com"
        )
        let store = try await openStore(provider: fake)
        let start = Date()

        await store.autoFetchIfDue(interval: 300, now: start)

        // No alert for a fetch nobody asked for; the status bar shows it.
        #expect(store.errorMessage == nil)
        let failure = try #require(store.autoFetchFailure)
        #expect(failure.message.contains("Could not resolve host"))

        await store.autoFetchIfDue(interval: 300, now: start.addingTimeInterval(60))
        #expect(fake.fetchCalls.count == 1)

        fake.fetchError = nil
        await store.autoFetchIfDue(interval: 300, now: start.addingTimeInterval(301))
        #expect(fake.fetchCalls.count == 2)
        #expect(store.autoFetchFailure == nil)
    }

    @Test func aFetchFromAnywhereElseClearsTheFailure() async throws {
        let fake = provider()
        fake.fetchError = .commandFailed(command: "git fetch --all --prune --progress", exitCode: 128, stderr: "fatal: offline")
        let store = try await openStore(provider: fake)
        await store.autoFetchIfDue(interval: 300)
        let failure = try #require(store.autoFetchFailure)

        // Like a fetch from the toolbar or a terminal: FETCH_HEAD gets newer.
        let root = try #require(store.root)
        try touchFetchHead(in: root.appendingPathComponent(".git"), at: failure.date.addingTimeInterval(1))
        await store.refresh()

        #expect(store.autoFetchFailure == nil)
    }

    @Test func aFetchFromTheMainWorktreeCountsInALinkedOne() async throws {
        let fake = provider()
        let commonDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-auto-fetch-common-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: commonDir, withIntermediateDirectories: true)
        try touchFetchHead(in: commonDir, at: Date().addingTimeInterval(-60))
        fake.commonDir = commonDir
        let store = try await openStore(provider: fake)

        #expect(store.lastFetched != nil)
        await store.autoFetchIfDue(interval: 300)
        #expect(fake.fetchCalls.isEmpty)
    }

    @Test func aPullDuringAnAutomaticFetchStillRuns() async throws {
        let fake = provider()
        let gate = FetchGate()
        fake.fetchGate = gate
        let store = try await openStore(provider: fake)

        let automatic = Task { await store.autoFetchIfDue(interval: 300) }
        await Task.yield()
        #expect(store.isAutoFetching)

        let pull = Task { await store.pull() }
        await Task.yield()
        // Started, not refused: Git's command queue puts it behind the fetch.
        #expect(store.isRemoteOperationRunning)

        await gate.open()
        await automatic.value
        await pull.value
        #expect(store.errorMessage == nil)
        #expect(!store.isAutoFetching)
        #expect(fake.fetchCalls.count == 2)
    }

    @Test func noAutomaticFetchStartsDuringARemoteOperation() async throws {
        let fake = provider()
        let gate = FetchGate()
        fake.fetchGate = gate
        let store = try await openStore(provider: fake)

        let fetch = Task { await store.fetch(remote: nil) }
        await Task.yield()
        #expect(store.isRemoteOperationRunning)

        await store.autoFetchIfDue(interval: 300)
        #expect(!store.isAutoFetching)

        await gate.open()
        await fetch.value
        #expect(fake.fetchCalls.count == 1)
    }

    private func provider(hasRemote: Bool = true) -> FakeGitProvider {
        FakeGitProvider(
            status: WorkingCopyStatus(branch: BranchInfo(name: "main", oid: "a1"), entries: []),
            remotes: hasRemote ? [GitRemote(name: "origin")] : []
        )
    }

    private func openStore(provider: FakeGitProvider, fetchedAgo: TimeInterval? = nil) async throws -> RepositoryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avi-auto-fetch-\(UUID().uuidString)", isDirectory: true)
        let gitDir = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        if let fetchedAgo {
            try touchFetchHead(in: gitDir, at: Date().addingTimeInterval(-fetchedAgo))
        }
        let store = RepositoryStore(git: provider)
        await store.open(root)
        store.stopBackgroundObservation()
        return store
    }

    private func touchFetchHead(in gitDir: URL, at date: Date) throws {
        let fetchHead = gitDir.appendingPathComponent("FETCH_HEAD")
        try Data().write(to: fetchHead)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: fetchHead.path)
    }
}
