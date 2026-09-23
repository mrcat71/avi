@testable import AppUI
import Foundation
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

    @Test func cloneConfigTolerantDecoderFillsMissingKeys() throws {
        // A clone config with only one field set should decode all other
        // keys to their defaults (the tolerant decoder behaviour exercised
        // by every section).
        let partial = #"{"defaultDirectory": "/tmp/avi-test-clones"}"#
        let data = Data(partial.utf8)
        let decoded = try JSONDecoder().decode(CloneConfig.self, from: data)
        #expect(decoded.defaultDirectory == "/tmp/avi-test-clones")
        #expect(decoded.openAfterClone == true)
        #expect(decoded.preferredProtocol == "https")
        #expect(decoded.preferredCLI == "auto")
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
        (#"{}"#, "gpt-6-luna"),
        (#"{"model": ""}"#, "gpt-6-luna"),
        (#"{"model": "  "}"#, "gpt-6-luna"),
        (#"{"model": "gpt-5.5"}"#, "gpt-5.5")
    ])
    func aiModelDefaultsToLunaUntilOneIsChosen(json: String, expected: String) throws {
        let decoded = try JSONDecoder().decode(AIConfig.self, from: Data(json.utf8))
        #expect(decoded.model == expected)
        #expect(AIConfig().model == "gpt-6-luna")
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
}
