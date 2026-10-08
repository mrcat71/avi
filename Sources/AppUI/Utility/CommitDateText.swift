import Foundation

/// Commit dates as people say them: "Today, 15:36" and "Yesterday, 11:17".
/// Only older commits get a calendar date, in the user's locale.
enum CommitDateText {
    enum Style {
        /// Day, month, and time: History rows.
        case short
        /// Day, month, year, and time: commit headers.
        case long
        /// Day, month, and year, no time: file history and blame.
        case day
    }

    static func string(
        for date: Date,
        style: Style,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(base.hour().minute())
        if let word = dayWord(for: date, now: now, calendar: calendar) {
            return style == .day ? word : "\(word), \(time)"
        }
        switch style {
        case .short:
            return date.formatted(base.month().day().hour().minute())
        case .long:
            return date.formatted(base.year().month().day().hour().minute())
        case .day:
            return date.formatted(base.year().month().day())
        }
    }

    /// "Today" or "Yesterday" when `date` falls on one of those days.
    static func dayWord(for date: Date, now: Date, calendar: Calendar) -> String? {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return nil
    }
}
