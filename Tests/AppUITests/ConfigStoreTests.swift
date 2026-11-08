@testable import AppUI
import Foundation
import GitKit
import Testing

struct ConfigStoreTests {
    @Test func configPathIsUnderApplicationSupport() {
        let path = ConfigPath.fileURL.path
        #expect(path.hasSuffix("Avi/config.toml"))
        #expect(path.contains("Application Support"))
    }

    @Test func ensureDirectoryExistsIsIdempotent() throws {
        // Calling it twice in a row must not throw or corrupt the directory.
        try ConfigPath.ensureDirectoryExists()
        try ConfigPath.ensureDirectoryExists()
        #expect(FileManager.default.fileExists(atPath: ConfigPath.directoryURL.path))
    }

    @Test func defaultAviConfigPopulatesEverySection() {
        let config = AviConfig()
        // Sub-structs come from explicit defaults; sanity-check that the
        // tolerant decoder won't be needed for a fresh install.
        #expect(config.version == 1)
        #expect(config.appearance.theme == "system")
        #expect(config.git.autoRefresh)
        #expect(config.clone.openAfterClone)
        #expect(config.ai.enabled == false)
        #expect(config.externalTools.gitPath == "")
        #expect(config.advanced.historyLimit == 200)
    }

    /// A config written before the merge tool keys existed keeps its paths.
    @Test func externalToolsWithoutMergeToolKeysKeepTheirPaths() throws {
        let older = #"{"externalTools": {"gitPath": "/opt/git", "diffToolPath": "/usr/local/bin/ksdiff", "mergeToolPath": ""}}"#
        let decoded = try JSONDecoder().decode(AviConfig.self, from: Data(older.utf8))
        #expect(decoded.externalTools.gitPath == "/opt/git")
        #expect(decoded.externalTools.diffToolPath == "/usr/local/bin/ksdiff")
        #expect(decoded.externalTools.mergeTool == "")
        #expect(decoded.externalTools.mergeToolCommand == "")
    }

    @Test func cloneConfigTolerantDecoderFillsMissingKeys() throws {
        // A clone config with only one field set should decode all other
        // keys to their defaults (the tolerant decoder behaviour exercised
        // by every section).
        // `preferredCLI` is gone; files that still have it decode the same.
        let partial = #"{"defaultDirectory": "/tmp/avi-test-clones", "preferredCLI": "gh-glab"}"#
        let data = Data(partial.utf8)
        let decoded = try JSONDecoder().decode(CloneConfig.self, from: data)
        #expect(decoded.defaultDirectory == "/tmp/avi-test-clones")
        #expect(decoded.openAfterClone == true)
        #expect(decoded.preferredProtocol == "https")
        #expect(decoded.rememberDestinationPerProvider == true)
    }

    @Test func aviConfigTolerantDecoderHandlesMinimalInput() throws {
        // Just `version`; every section should fall back to defaults.
        let minimal = #"{"version": 1}"#
        let data = Data(minimal.utf8)
        let decoded = try JSONDecoder().decode(AviConfig.self, from: data)
        #expect(decoded.version == 1)
        #expect(decoded.appearance.theme == "system")
        #expect(decoded.clone.defaultDirectory == "~/Developer")
        #expect(decoded.ai.backend == "command")
        #expect(decoded.agents.enabled)
    }

    @Test(arguments: [
        (#"{}"#, "gpt-6.1-luna"),
        (#"{"model": ""}"#, "gpt-6.1-luna"),
        (#"{"model": "  "}"#, "gpt-6.1-luna"),
        (#"{"model": "gpt-6-luna"}"#, "gpt-6-luna"),
        (#"{"model": "gpt-5.5"}"#, "gpt-5.5")
    ])
    func aiModelDefaultsToLunaUntilOneIsChosen(json: String, expected: String) throws {
        let decoded = try JSONDecoder().decode(AIConfig.self, from: Data(json.utf8))
        #expect(decoded.model == expected)
        #expect(AIConfig().model == "gpt-6.1-luna")
    }

    @Test func agentsSectionRoundTripsThroughTOML() throws {
        var config = AviConfig()
        config.agents.enabled = false
        let raw = try JSONEncoder().encode(config)
        let object = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let toml = MiniTOML.encode(object)
        #expect(toml.contains("[agents]\nenabled = false"))
        let parsed = try MiniTOML.parse(toml)
        let decoded = try JSONDecoder().decode(AviConfig.self, from: JSONSerialization.data(withJSONObject: parsed))
        #expect(decoded.agents.enabled == false)
    }

    /// The TOML round trip ConfigStore reads files with.
    private func decode(_ toml: String) throws -> AviConfig {
        let parsed = try MiniTOML.parse(toml)
        return try JSONDecoder().decode(AviConfig.self, from: JSONSerialization.data(withJSONObject: parsed))
    }

    private func toml(_ object: [String: Any]) -> String {
        MiniTOML.encode(object)
    }

    /// A [git] table written before a key existed keeps the keys it has.
    @Test func gitTableWithoutSomeKeysKeepsTheRest() throws {
        let decoded = try decode("""
        [git]
        defaultAuthorName = "Andrei"
        signCommits = true
        """)
        #expect(decoded.git.defaultAuthorName == "Andrei")
        #expect(decoded.git.signCommits)
        #expect(decoded.git.fetchInterval == GitConfig().fetchInterval)
        #expect(decoded.git.pruneOnFetch)
        #expect(decoded.git.terminalApp == "")
    }

    @Test func advancedTableWithoutSomeKeysKeepsTheRest() throws {
        let decoded = try decode("""
        [advanced]
        verboseLogging = true
        """)
        #expect(decoded.advanced.verboseLogging)
        #expect(decoded.advanced.historyLimit == 200)
    }

    @Test(arguments: [(10, 50), (200, 200), (4000, 4000), (99999, 5000)])
    func historyLimitStaysInItsRange(stored: Int, used: Int) {
        #expect(AdvancedConfig(historyLimit: stored).clampedHistoryLimit == used)
    }

    /// External Tools' own editor and terminal paths, which nothing used,
    /// become the ones Open in Editor and Open in Terminal use.
    @Test func externalToolsEditorAndTerminalMoveToGit() throws {
        let decoded = try decode("""
        [externalTools]
        editorPath = "/Applications/Zed.app"
        terminalPath = "/Applications/WezTerm.app"
        """)
        #expect(decoded.git.externalEditor == "/Applications/Zed.app")
        #expect(decoded.git.terminalApp == "/Applications/WezTerm.app")
    }

    @Test func gitsOwnEditorAndTerminalWinOverExternalTools() throws {
        let decoded = try decode("""
        [externalTools]
        editorPath = "/Applications/Zed.app"
        terminalPath = "/Applications/WezTerm.app"

        [git]
        externalEditor = "/Applications/Cursor.app"
        terminalApp = "/Applications/Ghostty.app"
        """)
        #expect(decoded.git.externalEditor == "/Applications/Cursor.app")
        #expect(decoded.git.terminalApp == "/Applications/Ghostty.app")
    }

    struct PromptCase: @unchecked Sendable {
        let key: String
        let previous: String
        let current: KeyPath<AIConfig, String>
        let builtIn: String
    }

    static let prompts: [PromptCase] = [
        PromptCase(key: "promptTemplate", previous: AIConfig.previousDefaultPromptTemplates[0], current: \.promptTemplate, builtIn: AIConfig.defaultPromptTemplate),
        PromptCase(key: "rewordPromptTemplate", previous: AIConfig.previousDefaultRewordPromptTemplates[0], current: \.rewordPromptTemplate, builtIn: AIConfig.defaultRewordPromptTemplate),
        PromptCase(key: "splitPromptTemplate", previous: AIConfig.previousDefaultSplitPromptTemplates[0], current: \.splitPromptTemplate, builtIn: AIConfig.defaultSplitPromptTemplate),
        PromptCase(key: "planRevisionPromptTemplate", previous: AIConfig.previousDefaultPlanRevisionPromptTemplates[0], current: \.planRevisionPromptTemplate, builtIn: AIConfig.defaultPlanRevisionPromptTemplate)
    ]

    /// A prompt a config file kept from an earlier Avi, never edited,
    /// follows today's built-in one and its Conventional Commits switch.
    @Test(arguments: prompts)
    func previousBuiltInPromptsBecomeTodaysDefault(_ test: PromptCase) throws {
        let decoded = try decode(toml(["ai": [test.key: test.previous]]))
        #expect(decoded.ai[keyPath: test.current] == test.builtIn)
        #expect(test.builtIn.contains("${style}"))
        #expect(test.previous != test.builtIn)
    }

    @Test(arguments: prompts)
    func editedPromptsStayAsTheyAre(_ test: PromptCase) throws {
        let edited = test.previous + "\nAlways mention the ticket."
        let decoded = try decode(toml(["ai": [test.key: edited]]))
        #expect(decoded.ai[keyPath: test.current] == edited)
    }

    /// Git's part of Settings, as every git command gets it.
    @Test func gitOptionsComeFromSettings() {
        var config = AviConfig()
        config.git.defaultAuthorName = "  Andrei  "
        config.git.defaultAuthorEmail = "andrei@example.com"
        config.git.signCommits = true
        config.git.pruneOnFetch = false
        config.advanced.verboseLogging = true
        config.externalTools.gitPath = "/usr/bin/git"
        let options = GitCommandOptions(settings: config)
        #expect(options.fallbackName == "Andrei")
        #expect(options.fallbackEmail == "andrei@example.com")
        #expect(options.signCommits)
        #expect(!options.pruneOnFetch)
        #expect(options.logCommands)
        #expect(options.executable?.path == "/usr/bin/git")

        config.externalTools.gitPath = "/no/such/git"
        #expect(GitCommandOptions(settings: config).executable == nil, "a path that is no executable is ignored")
    }

    /// config.example.toml documents every key; it has to read as Avi reads
    /// a config file.
    @Test func exampleConfigDecodes() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("config.example.toml")
        let decoded = try decode(String(contentsOf: example, encoding: .utf8))
        #expect(decoded.git.fetchInterval == 5)
        #expect(decoded.ai.conventionalCommits)
        #expect(decoded.ai.commandTemplate == AIConfig().commandTemplate)
        #expect(decoded.advanced.historyLimit == 200)
        #expect(decoded.clone.rememberDestinationPerProvider)
        #expect(decoded.externalTools.diffToolPath == "")
    }
}
