import AppKit
import CryptoKit
import Foundation
import Observation

/// Where an author's picture comes from by address alone, once the forge that
/// hosts the repository (`ForgeAvatars`) could not say: the GitHub account
/// behind a no-reply address, the public lookup of the GitLab instance the
/// repository is on, then Gravatar, which is asked by a SHA-256 hash of the
/// address and answers 404 rather than a placeholder.
enum AvatarSource {
    static func urls(email: String, gitLabHost: String?, pixels: Int) -> [URL] {
        var urls: [URL] = []
        if let github = gitHubNoReplyURL(email: email, pixels: pixels) {
            urls.append(github)
        }
        if let gitLabHost, let lookup = gitLabLookupURL(host: gitLabHost, email: email, pixels: pixels) {
            urls.append(lookup)
        }
        if let gravatar = gravatarURL(email: email, pixels: pixels) {
            urls.append(gravatar)
        }
        return urls
    }

    /// `12345+login@users.noreply.github.com`, or the older `login@…`.
    static func gitHubNoReplyURL(email: String, pixels: Int) -> URL? {
        let address = normalized(email)
        let suffix = "@users.noreply.github.com"
        guard address.hasSuffix(suffix) else { return nil }
        let local = address.dropLast(suffix.count)
        let parts = local.split(separator: "+", maxSplits: 1)
        if parts.count == 2, let id = Int(parts[0]) {
            return URL(string: "https://avatars.githubusercontent.com/u/\(id)?s=\(pixels)&v=4")
        }
        guard !local.isEmpty, local.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return URL(string: "https://github.com/\(local).png?size=\(pixels)")
    }

    /// GitLab's avatar lookup, which answers with the picture's own URL.
    static func gitLabLookupURL(host: String, email: String, pixels: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v4/avatar"
        components.queryItems = [
            URLQueryItem(name: "email", value: normalized(email)),
            URLQueryItem(name: "size", value: String(pixels))
        ]
        // A literal "+" in a query reads as a space; addresses use it for tags.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    static func gravatarURL(email: String, pixels: Int) -> URL? {
        let address = normalized(email)
        guard address.contains("@") else { return nil }
        let hash = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL(string: "https://gravatar.com/avatar/\(hash)?s=\(pixels)&d=404")
    }

    /// Up to two letters for the picture's stand-in: "Andrey Svinarenko" is
    /// "AS", "renovate-okira[bot]" is "R".
    static func initials(for name: String) -> String {
        let words = name.split { $0 == " " || $0 == "." || $0 == "_" }
            .filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Author pictures, fetched once per address and launch, a few at a time,
/// and kept in an on-disk HTTP cache between launches.
@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()

    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var attempted: Set<String> = []
    @ObservationIgnored private var active = 0
    @ObservationIgnored private var waiting: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Avi/Avatars", isDirectory: true)
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    private static let maxConcurrentLoads = 4
    /// Test runs show initials and never reach the network.
    private static let isRunningTests = NSClassFromString("XCTestCase") != nil

    private init() {}

    func image(for email: String) -> NSImage? {
        images[AvatarSource.normalized(email)]
    }

    /// Looks the picture up unless this launch already tried; nothing found
    /// leaves the initials in place. The forge that hosts the repository is
    /// asked first, about `commits` by this author.
    func load(email: String, commits: [String], origin: AvatarOrigin?, pixels: Int) async {
        let key = AvatarSource.normalized(email)
        let place = origin.map { "\($0.host)/\($0.project)" } ?? ""
        guard !Self.isRunningTests, !key.isEmpty, images[key] == nil,
              attempted.insert("\(key)|\(place)").inserted else { return }
        // The forge's answer waits for the other authors on screen, so it
        // comes before taking one of the few download slots.
        var urls: [URL] = []
        if let origin, let account = await ForgeAvatars.shared.avatarURL(email: key, commits: commits, origin: origin, pixels: pixels) {
            urls.append(account)
        }
        urls += AvatarSource.urls(email: key, gitLabHost: origin?.gitLabHost, pixels: pixels)
        await acquire()
        defer { release() }
        for url in urls {
            if let image = await fetch(url, gitLabLookup: url.path == "/api/v4/avatar") {
                images[key] = image
                return
            }
        }
    }

    private func fetch(_ url: URL, gitLabLookup: Bool) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        if gitLabLookup {
            struct Lookup: Decodable {
                let avatar_url: String?
            }
            guard let lookup = try? JSONDecoder().decode(Lookup.self, from: data),
                  let next = lookup.avatar_url.flatMap(URL.init(string:)) else { return nil }
            return await fetch(next, gitLabLookup: false)
        }
        return NSImage(data: data)
    }

    private func acquire() async {
        if active < Self.maxConcurrentLoads {
            active += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
