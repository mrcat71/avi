import AppKit
import SwiftUI

/// GitHub Device Authorization flow.
///
/// The client ID below must be configured for your installation. Create one at
/// github.com/settings/applications/new (Device flow enabled) and paste it here.
/// Without a real client ID, the PAT path in Settings should be used instead.
enum GitHubDeviceFlowConfig {
    static let clientID: String = "" // intentionally empty; user provides for builds.
    static let scope: String = "repo"
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!
}

struct DeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int
}

struct TokenPollResponse: Decodable {
    let access_token: String?
    let error: String?
    let interval: Int?
}

struct GitHubDeviceFlowSheet: View {
    let onComplete: (ProviderAccount) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .initial
    @State private var code: String = ""
    @State private var verificationURL: String = ""
    @State private var errorMessage: String?

    enum Phase {
        case initial
        case waitingForCode
        case userVerifying
        case polling
        case done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to GitHub")
                .font(.system(size: 14, weight: .semibold))

            if GitHubDeviceFlowConfig.clientID.isEmpty {
                Text("Device flow is not configured in this build. Use the Personal Access Token option in Settings instead.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else {
                switch phase {
                case .initial:
                    Text("Start a browser-based sign-in. You'll be shown a short code to enter on GitHub.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                case .waitingForCode, .userVerifying:
                    Text("Enter this code on the GitHub page that opens:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .padding(.vertical, 6)
                        .textSelection(.enabled)
                    Text(verificationURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.blue)
                        .onTapGesture {
                            if let url = URL(string: verificationURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                case .polling:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Waiting for authorization...")
                            .font(.system(size: 11))
                    }
                case .done:
                    Text("Signed in.")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                if GitHubDeviceFlowConfig.clientID.isEmpty == false, phase == .initial {
                    Button("Start") { Task { await start() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func start() async {
        phase = .waitingForCode
        do {
            let deviceCode = try await requestDeviceCode()
            code = deviceCode.user_code
            verificationURL = deviceCode.verification_uri
            phase = .userVerifying
            if let url = URL(string: deviceCode.verification_uri) {
                NSWorkspace.shared.open(url)
            }
            phase = .polling
            let token = try await pollForToken(deviceCode: deviceCode)
            try await completeSignIn(token: token)
            phase = .done
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            phase = .initial
        }
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: GitHubDeviceFlowConfig.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(GitHubDeviceFlowConfig.clientID)&scope=\(GitHubDeviceFlowConfig.scope)"
        request.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    private func pollForToken(deviceCode: DeviceCodeResponse) async throws -> String {
        var interval = TimeInterval(deviceCode.interval)
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expires_in))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            var request = URLRequest(url: GitHubDeviceFlowConfig.tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "client_id=\(GitHubDeviceFlowConfig.clientID)&device_code=\(deviceCode.device_code)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)
            let (data, _) = try await URLSession.shared.data(for: request)
            let resp = try JSONDecoder().decode(TokenPollResponse.self, from: data)
            if let token = resp.access_token { return token }
            switch resp.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval += 5
                continue
            case "expired_token":
                throw NSError(domain: "GitHubDeviceFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "Code expired. Please retry."])
            default:
                throw NSError(domain: "GitHubDeviceFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: resp.error ?? "Unknown error"])
            }
        }
        throw NSError(domain: "GitHubDeviceFlow", code: 3, userInfo: [NSLocalizedDescriptionKey: "Sign-in timed out."])
    }

    private func completeSignIn(token: String) async throws {
        try await AccountManager.shared.addGitHubPATAccount(token: token)
        // The most recently added account is the one we just created.
        if let account = AccountManager.shared.accounts(matching: "github").last {
            onComplete(account)
        }
    }
}
