@testable import AppUI
import Testing

struct SettingsSearchTests {
    struct Case: Sendable {
        let name: String
        let query: String
        let expected: [SettingsSection]
    }

    static let everySection: [SettingsSection] = [
        .general, .appearance, .keyboard, .git, .clone, .externalTools, .github, .gitlab, .ai, .agents
    ]

    static let cases: [Case] = [
        Case(name: "an empty query lists every section in sidebar order", query: "", expected: everySection),
        Case(name: "spaces alone are an empty query", query: "   ", expected: everySection),
        Case(name: "a title finds its section", query: "Clone", expected: [.clone]),
        Case(name: "a row label finds its section", query: "launch at login", expected: [.general]),
        Case(name: "case does not matter", query: "AUTHOR", expected: [.appearance, .git]),
        Case(name: "spaces match hyphens", query: "auto fetch", expected: [.git]),
        Case(name: "accents do not matter", query: "génèral", expected: [.general]),
        Case(name: "every word has to match", query: "token self-hosted", expected: [.gitlab]),
        Case(name: "words can match different rows", query: "token github", expected: [.github]),
        Case(name: "keyboard finds its shortcuts' actions", query: "command palette", expected: [.keyboard]),
        Case(name: "settings under Advanced are found too", query: "temperature", expected: [.ai]),
        Case(name: "the config file is under General", query: "config.toml", expected: [.general]),
        Case(name: "nothing matches", query: "zzz", expected: [])
    ]

    @Test(arguments: cases)
    func matching(_ test: Case) {
        #expect(SettingsSection.matching(test.query) == test.expected, "\(test.name)")
    }

    struct RevealCase: Sendable {
        let query: String
        let section: SettingsSection
        let reveals: Bool
    }

    @Test(arguments: [
        RevealCase(query: "temperature", section: .ai, reveals: true),
        RevealCase(query: "model", section: .ai, reveals: false),
        RevealCase(query: "AI temperature", section: .ai, reveals: true),
        RevealCase(query: "sign commits", section: .git, reveals: true),
        RevealCase(query: "auto fetch", section: .git, reveals: false),
        RevealCase(query: "git", section: .git, reveals: false),
        RevealCase(query: "reset all", section: .general, reveals: true),
        RevealCase(query: "", section: .ai, reveals: false),
        RevealCase(query: "token", section: .github, reveals: false)
    ])
    func searchOpensAdvancedOnlyForWhatIsInside(_ test: RevealCase) {
        #expect(test.section.revealsAdvanced(for: test.query) == test.reveals, "\(test.query)")
    }

    @Test
    func everySectionWithAdvancedSettingsSaysWhatIsInside() {
        for section in SettingsSection.allCases {
            #expect(section.advancedKeywords.isEmpty == (section.advancedSummary == nil), "\(section)")
        }
    }

    @Test
    func sidebarListsEverySectionOnce() {
        let sidebar = SettingsSection.sidebarGroups.flatMap { $0 }
        #expect(sidebar.count == SettingsSection.allCases.count)
        #expect(Set(sidebar) == Set(SettingsSection.allCases))
    }
}

struct SettingsHistoryTests {
    enum Step: Sendable {
        case visit(SettingsSection)
        case back
        case forward
    }

    struct Case: Sendable {
        let name: String
        let steps: [Step]
        let current: SettingsSection
        let back: [SettingsSection]
        let forward: [SettingsSection]
    }

    static let cases: [Case] = [
        Case(name: "starts with nowhere to go", steps: [], current: .general, back: [], forward: []),
        Case(
            name: "visiting keeps the way back",
            steps: [.visit(.git), .visit(.ai)], current: .ai, back: [.general, .git], forward: []
        ),
        Case(
            name: "visiting the section on show changes nothing",
            steps: [.visit(.git), .visit(.git)], current: .git, back: [.general], forward: []
        ),
        Case(
            name: "back returns to the previous section and keeps the way forward",
            steps: [.visit(.git), .visit(.ai), .back], current: .git, back: [.general], forward: [.ai]
        ),
        Case(
            name: "forward undoes back",
            steps: [.visit(.git), .visit(.ai), .back, .back, .forward], current: .git, back: [.general], forward: [.ai]
        ),
        Case(
            name: "visiting after back drops the way forward",
            steps: [.visit(.git), .visit(.ai), .back, .visit(.clone)], current: .clone, back: [.general, .git], forward: []
        ),
        Case(
            name: "back and forward with nowhere to go change nothing",
            steps: [.back, .forward], current: .general, back: [], forward: []
        )
    ]

    @Test(arguments: cases)
    func navigation(_ test: Case) {
        var history = SettingsHistory(.general)
        for step in test.steps {
            switch step {
            case .visit(let section): history.visit(section)
            case .back: history.goBack()
            case .forward: history.goForward()
            }
        }
        #expect(history.current == test.current, "\(test.name)")
        #expect(history.back == test.back, "\(test.name)")
        #expect(history.forward == test.forward, "\(test.name)")
        #expect(history.canGoBack == !test.back.isEmpty, "\(test.name)")
        #expect(history.canGoForward == !test.forward.isEmpty, "\(test.name)")
    }
}
