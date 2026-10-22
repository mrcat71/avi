import Foundation

/// Avi's interface is in English, so its dates are too: English words and
/// month names, in the date and time order of your region. A system set to
/// Spanish no longer turns "2 min ago" into "hace 2 min" next to English
/// labels.
enum AviLocale {
    static var display: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(languageCode: .english, region: Locale.current.region)
        return Locale(components: components)
    }

    /// "2 min ago", "in 3 days"; under a minute either way is "just now".
    static func relative(
        _ date: Date,
        to now: Date = Date(),
        style: RelativeDateTimeFormatter.UnitsStyle = .abbreviated
    ) -> String {
        if abs(date.timeIntervalSince(now)) < 60 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = display
        formatter.unitsStyle = style
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
