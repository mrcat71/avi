import SwiftUI

/// Reusable badge that summarizes the state of a provider CLI (`gh`/`glab`).
struct ProviderCLIStatusBadge: View {
    let state: ProviderAuthState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(headline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var icon: String {
        switch state {
        case .authenticated: return "checkmark.circle.fill"
        case .unauthenticated: return "person.crop.circle.badge.questionmark"
        case .cliMissing: return "questionmark.app.dashed"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .authenticated: return .green
        case .unauthenticated: return .orange
        case .cliMissing: return .secondary
        case .error: return .red
        }
    }

    private var headline: String {
        switch state {
        case .authenticated: return "Signed in"
        case .unauthenticated: return "Not signed in"
        case .cliMissing: return "Not installed"
        case .error: return "Error"
        }
    }

    private var subtitle: String {
        switch state {
        case .authenticated(let username, let host): return "\(username) @ \(host)"
        case .unauthenticated: return "Run the CLI's auth login command"
        case .cliMissing: return "brew install gh / glab"
        case .error(let message): return message
        }
    }
}
