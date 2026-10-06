import Foundation
import GitKit
import Observation

/// How every diff in Avi is shown, set from the diff toolbar and remembered in
/// Avi's user defaults rather than the config file: these change with what
/// you are reading, many times a day.
@MainActor
@Observable
final class DiffPreferences {
    static let shared = DiffPreferences()

    /// Lines of context the toolbar steps through.
    static let contextSteps = [0, 1, 3, 5, 10, 25, 50, 100]

    var ignoreWhitespace: Bool {
        didSet { save(ignoreWhitespace, Key.ignoreWhitespace) }
    }

    var showInvisibles: Bool {
        didSet { save(showInvisibles, Key.showInvisibles) }
    }

    var wrapLines: Bool {
        didSet { save(wrapLines, Key.wrapLines) }
    }

    var contextLines: Int {
        didSet { save(contextLines, Key.contextLines) }
    }

    var wholeFile: Bool {
        didSet { save(wholeFile, Key.wholeFile) }
    }

    var sideBySide: Bool {
        didSet { save(sideBySide, Key.sideBySide) }
    }

    private enum Key {
        static let ignoreWhitespace = "diff.ignoreWhitespace"
        static let showInvisibles = "diff.showInvisibles"
        static let wrapLines = "diff.wrapLines"
        static let contextLines = "diff.contextLines"
        static let wholeFile = "diff.wholeFile"
        static let sideBySide = "diff.sideBySide"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ignoreWhitespace = defaults.bool(forKey: Key.ignoreWhitespace)
        showInvisibles = defaults.bool(forKey: Key.showInvisibles)
        wrapLines = defaults.bool(forKey: Key.wrapLines)
        contextLines = defaults.object(forKey: Key.contextLines) as? Int ?? DiffOptions.standard.contextLines
        wholeFile = defaults.bool(forKey: Key.wholeFile)
        sideBySide = defaults.bool(forKey: Key.sideBySide)
    }

    /// What Git is asked for; a change means the diff has to load again.
    var gitOptions: DiffOptions {
        DiffOptions(contextLines: contextLines, wholeFile: wholeFile, ignoreWhitespace: ignoreWhitespace)
    }

    var canShowFewerLines: Bool {
        !wholeFile && contextLines > Self.contextSteps[0]
    }

    var canShowMoreLines: Bool {
        !wholeFile && contextLines < Self.contextSteps[Self.contextSteps.count - 1]
    }

    func showFewerLines() {
        contextLines = Self.step(from: contextLines, by: -1)
    }

    func showMoreLines() {
        contextLines = Self.step(from: contextLines, by: 1)
    }

    /// The next step down or up from `value`, which may sit between steps.
    static func step(from value: Int, by direction: Int) -> Int {
        if direction < 0 {
            return contextSteps.last { $0 < value } ?? contextSteps[0]
        }
        return contextSteps.first { $0 > value } ?? contextSteps[contextSteps.count - 1]
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
