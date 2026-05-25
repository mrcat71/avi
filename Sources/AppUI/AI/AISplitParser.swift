import Foundation

/// One commit group proposed by the AI split prompt.
public struct AICommitGroup: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var files: [String]
    public var message: String

    public init(id: UUID = UUID(), files: [String], message: String) {
        self.id = id
        self.files = files
        self.message = message
    }
}

public enum AISplitParseError: Error, LocalizedError {
    case noJSONFound(raw: String)
    case decode(reason: String, raw: String)
    case emptyGroups

    public var errorDescription: String? {
        switch self {
        case .noJSONFound: return "AI response did not contain a JSON object."
        case .decode(let reason, _): return "Could not parse AI response: \(reason)"
        case .emptyGroups: return "AI returned no groups."
        }
    }

    /// The raw AI response so the user can inspect what came back.
    public var raw: String {
        switch self {
        case .noJSONFound(let raw), .decode(_, let raw): return raw
        case .emptyGroups: return ""
        }
    }
}

/// Parses the AI split prompt's structured output into `[AICommitGroup]`.
/// The prompt asks for a fenced ```json block, but tolerates JSON anywhere
/// in the response by finding the largest balanced `{...}` substring.
public enum AISplitParser {
    public static func parse(_ raw: String) throws -> [AICommitGroup] {
        guard let jsonString = extractJSON(from: raw) else {
            throw AISplitParseError.noJSONFound(raw: raw)
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw AISplitParseError.decode(reason: "UTF-8 conversion failed", raw: raw)
        }
        let decoded: Payload
        do {
            decoded = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw AISplitParseError.decode(reason: "\(error)", raw: raw)
        }
        let groups = decoded.groups.map { group in
            AICommitGroup(
                files: group.files,
                message: group.message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !groups.isEmpty else { throw AISplitParseError.emptyGroups }
        return groups
    }

    // MARK: - Private

    private struct Payload: Decodable {
        let groups: [Group]
    }

    private struct Group: Decodable {
        let files: [String]
        let message: String
    }

    /// Find a JSON object in `raw`. Prefers a fenced ```json … ``` block;
    /// otherwise grabs the largest balanced `{ … }` substring.
    static func extractJSON(from raw: String) -> String? {
        if let fenced = fencedJSON(in: raw) {
            return fenced
        }
        return balancedObject(in: raw)
    }

    private static func fencedJSON(in raw: String) -> String? {
        // Match ```json … ``` or ``` … ``` blocks; first wins.
        let lower = raw.lowercased()
        let openMarkers = ["```json", "```"]
        for marker in openMarkers {
            guard let openRange = lower.range(of: marker) else { continue }
            let bodyStart = openRange.upperBound
            guard let closeRange = lower.range(of: "```", range: bodyStart ..< lower.endIndex) else {
                continue
            }
            // Map back to the original string's indices.
            let startOffset = lower.distance(from: lower.startIndex, to: bodyStart)
            let endOffset = lower.distance(from: lower.startIndex, to: closeRange.lowerBound)
            let bodyStartOriginal = raw.index(raw.startIndex, offsetBy: startOffset)
            let bodyEndOriginal = raw.index(raw.startIndex, offsetBy: endOffset)
            let body = String(raw[bodyStartOriginal ..< bodyEndOriginal]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        return nil
    }

    private static func balancedObject(in raw: String) -> String? {
        guard let firstBrace = raw.firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = firstBrace
        while i < raw.endIndex {
            let ch = raw[i]
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let endInclusive = raw.index(after: i)
                    return String(raw[firstBrace ..< endInclusive])
                }
            }
            i = raw.index(after: i)
        }
        return nil
    }
}
