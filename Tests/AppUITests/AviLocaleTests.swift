import AppKit
@testable import AppUI
import Foundation
import Testing

struct AviLocaleTests {
    @Test func relativeDatesSayJustNowUnderAMinute() {
        let now = Date()
        #expect(AviLocale.relative(now.addingTimeInterval(-30), to: now) == "just now")
        #expect(AviLocale.relative(now.addingTimeInterval(20), to: now) == "just now")
        #expect(AviLocale.relative(now.addingTimeInterval(-7200), to: now).hasSuffix("ago"))
    }

    @Test func datesAreInEnglishWithTheUsersRegion() {
        #expect(AviLocale.display.language.languageCode == .english)
        #expect(AviLocale.display.region == Locale.current.region)
    }

    /// The Diff font falls back to the system's monospaced font.
    @Test func aMissingDiffFontFallsBackToTheSystemMonospacedFont() {
        let system = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        #expect(DiffDisplay.codeFont(family: "No Such Font 1234", size: 12) == system)
        #expect(DiffDisplay.codeFont(family: "", size: 12) == system)
        #expect(DiffDisplay.codeFont(family: "sf mono", size: 12) == system)
        #expect(DiffDisplay.codeFont(family: "Menlo", size: 14).familyName == "Menlo")
    }
}
