import SwiftUI

/// The card at the top of the GitHub and GitLab settings panes. Makes it
/// obvious that provider auth is optional and which features it unlocks.
struct ProviderInfoBanner: View {
    let section: SettingsSection
    let features: String

    var body: some View {
        SettingsGroup {
            SettingsHeroRow(
                "\(section.title) integration is optional",
                subtitle: "Local Git operations (history, staging, commits, branches, AI commit generation) work without signing in. Sign in to enable: \(features)."
            ) {
                SettingsIcon(symbol: section.systemImage, tint: section.tint, size: SettingsMetrics.heroIcon)
            }
        }
    }
}
