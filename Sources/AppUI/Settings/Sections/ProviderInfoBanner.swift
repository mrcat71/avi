import SwiftUI

/// Banner shown at the top of the GitHub and GitLab settings panes. Makes it
/// obvious that provider auth is optional and which features it unlocks.
struct ProviderInfoBanner: View {
    let provider: String
    let features: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 12))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(provider) integration is optional")
                    .font(.system(size: 12, weight: .semibold))
                Text("Local Git operations (history, staging, commits, branches, AI commit generation) work without signing in. Sign in to enable: \(features).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.blue.opacity(0.20), lineWidth: 1)
        )
        .padding(.bottom, 14)
    }
}
