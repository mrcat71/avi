import SnapshotTesting
import SwiftUI
import Testing
@testable import AppUI
@testable import GitKit

/// Snapshot tests for the history workspace. Render at a fixed window size
/// against deterministic fixtures so visual regressions surface as image diffs.
///
/// On first run these tests record reference images; subsequent runs compare.
/// To force re-record after intentional UI changes, set environment variable
/// `RECORD_SNAPSHOTS=true` or call `assertSnapshot(record:)` directly.
@Suite struct HistoryViewSnapshotTests {
    @Test @MainActor
    func multibranchHistoryAtComfortableDensity() async throws {
        let provider = Fixtures.multibranch()
        let store = RepositoryStore(git: provider)
        try await loadStore(store, root: URL(fileURLWithPath: "/tmp/avi-snapshot"))

        let view = HistoryWorkspaceView(store: store)
            .frame(width: 900, height: 560)

        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.97))
    }

    @Test @MainActor
    func cleanHistoryEmpty() async throws {
        let provider = Fixtures.clean()
        let store = RepositoryStore(git: provider)
        try await loadStore(store, root: URL(fileURLWithPath: "/tmp/avi-snapshot"))

        let view = HistoryWorkspaceView(store: store)
            .frame(width: 900, height: 480)

        assertSnapshot(of: view, as: .image(perceptualPrecision: 0.97))
    }

    @MainActor
    private func loadStore(_ store: RepositoryStore, root: URL) async throws {
        await store.open(root)
        await store.refresh()
    }
}
