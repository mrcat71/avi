@testable import AppUI
@testable import GitKit
import SnapshotTesting
import SwiftUI
import Testing

/// Snapshot tests for the history workspace. Render at a fixed window size
/// against deterministic fixtures so visual regressions surface as image diffs.
///
/// Currently disabled: no reference images are committed yet, so the tests would
/// fail on first run. Re-enable after running locally with
/// `withSnapshotTesting(record: .all)` and committing the resulting
/// `__Snapshots__/` directory.
struct HistoryViewSnapshotTests {
    @Test(.disabled("Reference snapshots not committed; re-enable after capturing baselines locally."))
    @MainActor
    func multibranchHistoryAtComfortableDensity() async throws {
        let provider = Fixtures.multibranch()
        let store = RepositoryStore(git: provider)
        try await loadStore(store, root: URL(fileURLWithPath: "/tmp/avi-snapshot"))
        _ = HistoryWorkspaceView(store: store).frame(width: 900, height: 560)
    }

    @Test(.disabled("Reference snapshots not committed; re-enable after capturing baselines locally."))
    @MainActor
    func cleanHistoryEmpty() async throws {
        let provider = Fixtures.clean()
        let store = RepositoryStore(git: provider)
        try await loadStore(store, root: URL(fileURLWithPath: "/tmp/avi-snapshot"))
        _ = HistoryWorkspaceView(store: store).frame(width: 900, height: 480)
    }

    @MainActor
    private func loadStore(_ store: RepositoryStore, root: URL) async throws {
        await store.open(root)
        await store.refresh()
    }
}
