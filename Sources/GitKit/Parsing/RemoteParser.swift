import Foundation

/// Parses `git remote -v` output.
public enum RemoteParser {
    public static func parse(_ text: String) -> [GitRemote] {
        var remotesByName: [String: (fetchURL: String?, pushURL: String?)] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3 else { continue }

            let name = String(parts[0])
            let url = String(parts[1])
            let direction = String(parts[2])
            var remote = remotesByName[name] ?? (fetchURL: nil, pushURL: nil)

            switch direction {
            case "(fetch)":
                remote.fetchURL = url
            case "(push)":
                remote.pushURL = url
            default:
                continue
            }

            remotesByName[name] = remote
        }

        return remotesByName
            .map { GitRemote(name: $0.key, fetchURL: $0.value.fetchURL, pushURL: $0.value.pushURL) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
