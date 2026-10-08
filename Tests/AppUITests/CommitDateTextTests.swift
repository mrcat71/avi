@testable import AppUI
import Foundation
import Testing

struct CommitDateTextTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        /// Seconds before "now" (2026-10-07 13:00 in Madrid).
        let ago: TimeInterval
        let style: CommitDateText.Style
        /// The day word expected in front of the time, or nil for a calendar date.
        let word: String?

        var testDescription: String {
            name
        }
    }

    static let cases: [Case] = [
        Case(name: "earlier today", ago: 3 * 3600, style: .short, word: "Today"),
        Case(name: "just after midnight is still today", ago: 12 * 3600 + 59 * 60, style: .short, word: "Today"),
        Case(name: "just before midnight is yesterday", ago: 13 * 3600 + 60, style: .short, word: "Yesterday"),
        Case(name: "yesterday in a header", ago: 30 * 3600, style: .long, word: "Yesterday"),
        Case(name: "today without a time", ago: 3600, style: .day, word: "Today"),
        Case(name: "two days ago gets a date", ago: 50 * 3600, style: .short, word: nil),
        Case(name: "last year gets a date", ago: 400 * 86400, style: .long, word: nil)
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private static let locale = Locale(identifier: "en_GB")
    private static let now = ISO8601DateFormatter().date(from: "2026-10-07T11:00:00Z")!

    @Test(arguments: cases)
    func format(_ testCase: Case) {
        let date = Self.now.addingTimeInterval(-testCase.ago)
        let text = CommitDateText.string(for: date, style: testCase.style, now: Self.now, calendar: Self.calendar, locale: Self.locale)
        let base = Date.FormatStyle(locale: Self.locale, calendar: Self.calendar, timeZone: Self.calendar.timeZone)
        if let word = testCase.word {
            let expected = testCase.style == .day ? word : "\(word), \(date.formatted(base.hour().minute()))"
            #expect(text == expected)
        } else {
            #expect(!text.hasPrefix("Today") && !text.hasPrefix("Yesterday"))
            #expect(text.contains(date.formatted(base.day())))
        }
    }
}
