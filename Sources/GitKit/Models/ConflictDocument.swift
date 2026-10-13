import Foundation

/// A conflicted file as Git left it in the working tree: the text both sides
/// agree on, and between it each conflict Git marked with `<<<<<<<`,
/// `=======`, and `>>>>>>>` (plus `|||||||` and the base in the diff3 style).
/// Resolving a conflict replaces its markers with the lines you chose.
public struct ConflictDocument: Sendable, Equatable {
    public enum Segment: Sendable, Equatable {
        /// Lines outside any conflict.
        case common([String])
        case conflict(Conflict)
    }

    public struct Conflict: Sendable, Equatable {
        /// What follows `<<<<<<<`: `HEAD`, or the stash's "Updated upstream".
        public let currentLabel: String
        /// HEAD's side, Git's "ours".
        public let current: [String]
        /// What follows `|||||||`, when Git wrote the base too.
        public let baseLabel: String?
        public let base: [String]?
        /// What follows `>>>>>>>`: the merged branch, or the replayed commit.
        public let incomingLabel: String
        /// The change being applied, Git's "theirs".
        public let incoming: [String]
        /// The line its `<<<<<<<` marker is on, counting from 1.
        public let startLine: Int
        /// The marker lines as the file has them, line endings included, so
        /// the conflicts left unresolved are written back byte for byte.
        let markers: [String]
    }

    public enum Resolution: Sendable, Equatable, CaseIterable {
        case current
        case incoming
        case currentThenIncoming
        case incomingThenCurrent
    }

    public private(set) var segments: [Segment]
    /// The file ended with a line break, which must survive a resolution.
    private let endsWithNewline: Bool

    /// Nil when the markers do not pair up, such as a conflict that was
    /// half resolved by hand. Lines keep a trailing carriage return, so files
    /// with Windows line endings keep them.
    public init?(text: String) {
        var lines = text.components(separatedBy: "\n")
        endsWithNewline = lines.last == ""
        if endsWithNewline {
            lines.removeLast()
        }

        enum Part {
            case current, base, incoming
        }
        var segments: [Segment] = []
        var common: [String] = []
        var open: (label: String, start: Int)?
        var markers: [String] = []
        var part = Part.current
        var current: [String] = []
        var base: [String]?
        var baseLabel: String?
        var incoming: [String] = []

        for (index, line) in lines.enumerated() {
            let bare = line.hasSuffix("\r") ? String(line.dropLast()) : line
            guard let conflict = open else {
                if let label = Self.label(of: bare, marker: "<") {
                    if !common.isEmpty {
                        segments.append(.common(common))
                        common = []
                    }
                    open = (label, index + 1)
                    markers = [line]
                    part = .current
                    current = []
                    base = nil
                    baseLabel = nil
                    incoming = []
                } else {
                    common.append(line)
                }
                continue
            }
            if Self.label(of: bare, marker: "<") != nil {
                return nil
            }
            if bare == String(repeating: "=", count: Self.markerSize) {
                guard part != .incoming else { return nil }
                part = .incoming
                markers.append(line)
            } else if part == .current, let label = Self.label(of: bare, marker: "|") {
                part = .base
                baseLabel = label
                base = []
                markers.append(line)
            } else if part == .incoming, let label = Self.label(of: bare, marker: ">") {
                markers.append(line)
                segments.append(.conflict(Conflict(
                    currentLabel: conflict.label,
                    current: current,
                    baseLabel: baseLabel,
                    base: base,
                    incomingLabel: label,
                    incoming: incoming,
                    startLine: conflict.start,
                    markers: markers
                )))
                open = nil
            } else {
                switch part {
                case .current: current.append(line)
                case .base: base?.append(line)
                case .incoming: incoming.append(line)
                }
            }
        }
        guard open == nil else { return nil }
        if !common.isEmpty {
            segments.append(.common(common))
        }
        self.segments = segments
    }

    /// The conflicts in file order.
    public var conflicts: [Conflict] {
        segments.compactMap {
            if case let .conflict(conflict) = $0 {
                return conflict
            }
            return nil
        }
    }

    /// The file's text as it stands, markers included.
    public var text: String {
        var lines: [String] = []
        for segment in segments {
            switch segment {
            case let .common(common):
                lines += common
            case let .conflict(conflict):
                // open, [base,] separator, close
                let markers = conflict.markers
                lines.append(markers[0])
                lines += conflict.current
                if let base = conflict.base {
                    lines.append(markers[1])
                    lines += base
                }
                lines.append(markers[markers.count - 2])
                lines += conflict.incoming
                lines.append(markers[markers.count - 1])
            }
        }
        let joined = lines.joined(separator: "\n")
        return endsWithNewline ? joined + "\n" : joined
    }

    /// The document with its `index`th conflict replaced by the chosen lines.
    /// Line numbers of the conflicts after it move to match.
    public func resolving(conflictAt index: Int, with resolution: Resolution) -> ConflictDocument {
        var result = self
        var seen = 0
        var resolved: [Segment] = []
        for segment in segments {
            guard case let .conflict(conflict) = segment, seen == index else {
                if case .conflict = segment {
                    seen += 1
                }
                resolved.append(segment)
                continue
            }
            seen += 1
            let lines: [String]
            switch resolution {
            case .current: lines = conflict.current
            case .incoming: lines = conflict.incoming
            case .currentThenIncoming: lines = conflict.current + conflict.incoming
            case .incomingThenCurrent: lines = conflict.incoming + conflict.current
            }
            resolved.append(.common(lines))
        }
        result.segments = Self.renumbered(Self.joiningCommon(resolved))
        return result
    }

    // MARK: - Markers

    /// Git's default; a `conflict-marker-size` attribute can change it, and
    /// then nothing here parses as a marker.
    static let markerSize = 7

    /// The label after a marker line such as `<<<<<<< HEAD`, or "" for a bare
    /// one; nil when `line` is not that marker.
    private static func label(of line: String, marker: Character) -> String? {
        let run = String(repeating: marker, count: markerSize)
        guard line.hasPrefix(run) else { return nil }
        let rest = line.dropFirst(markerSize)
        if rest.isEmpty {
            return ""
        }
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst())
    }

    private static func joiningCommon(_ segments: [Segment]) -> [Segment] {
        var joined: [Segment] = []
        for segment in segments {
            if case let .common(lines) = segment, case let .common(previous)? = joined.last {
                joined[joined.count - 1] = .common(previous + lines)
            } else if case let .common(lines) = segment, lines.isEmpty {
                continue
            } else {
                joined.append(segment)
            }
        }
        return joined
    }

    private static func renumbered(_ segments: [Segment]) -> [Segment] {
        var line = 1
        return segments.map { segment in
            switch segment {
            case let .common(lines):
                line += lines.count
                return segment
            case let .conflict(conflict):
                let moved = Conflict(
                    currentLabel: conflict.currentLabel,
                    current: conflict.current,
                    baseLabel: conflict.baseLabel,
                    base: conflict.base,
                    incomingLabel: conflict.incomingLabel,
                    incoming: conflict.incoming,
                    startLine: line,
                    markers: conflict.markers
                )
                line += 3 + conflict.current.count + conflict.incoming.count + (conflict.base.map { $0.count + 1 } ?? 0)
                return .conflict(moved)
            }
        }
    }
}
