import Foundation

/// On-disk configuration schema. Lives at `~/Library/Application Support/Avi/config.toml`.
/// Codable conformance bridges to/from `[String: Any]` (used by `MiniTOML`).
public struct AviConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var general: GeneralConfig
    public var appearance: AppearanceConfig
    public var git: GitConfig
    public var integrations: IntegrationsConfig
    public var ai: AIConfig
    public var externalTools: ExternalToolsConfig
    public var advanced: AdvancedConfig
    public var clone: CloneConfig

    public init(
        version: Int = 1,
        general: GeneralConfig = .init(),
        appearance: AppearanceConfig = .init(),
        git: GitConfig = .init(),
        integrations: IntegrationsConfig = .init(),
        ai: AIConfig = .init(),
        externalTools: ExternalToolsConfig = .init(),
        advanced: AdvancedConfig = .init(),
        clone: CloneConfig = .init()
    ) {
        self.version = version
        self.general = general
        self.appearance = appearance
        self.git = git
        self.integrations = integrations
        self.ai = ai
        self.externalTools = externalTools
        self.advanced = advanced
        self.clone = clone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AviConfig()
        version = (try? c.decode(Int.self, forKey: .version)) ?? defaults.version
        general = (try? c.decode(GeneralConfig.self, forKey: .general)) ?? defaults.general
        appearance = (try? c.decode(AppearanceConfig.self, forKey: .appearance)) ?? defaults.appearance
        git = (try? c.decode(GitConfig.self, forKey: .git)) ?? defaults.git
        integrations = (try? c.decode(IntegrationsConfig.self, forKey: .integrations)) ?? defaults.integrations
        ai = (try? c.decode(AIConfig.self, forKey: .ai)) ?? defaults.ai
        externalTools = (try? c.decode(ExternalToolsConfig.self, forKey: .externalTools)) ?? defaults.externalTools
        advanced = (try? c.decode(AdvancedConfig.self, forKey: .advanced)) ?? defaults.advanced
        clone = (try? c.decode(CloneConfig.self, forKey: .clone)) ?? defaults.clone
    }
}

public struct CloneConfig: Codable, Equatable, Sendable {
    public var defaultDirectory: String // "~/src" expanded at use site
    public var openAfterClone: Bool
    public var preferredProtocol: String // "https" | "ssh"
    public var preferredCLI: String // "auto" | "gh-glab" | "git"
    public var rememberDestinationPerProvider: Bool

    public init(
        defaultDirectory: String = "~/Developer",
        openAfterClone: Bool = true,
        preferredProtocol: String = "https",
        preferredCLI: String = "auto",
        rememberDestinationPerProvider: Bool = true
    ) {
        self.defaultDirectory = defaultDirectory
        self.openAfterClone = openAfterClone
        self.preferredProtocol = preferredProtocol
        self.preferredCLI = preferredCLI
        self.rememberDestinationPerProvider = rememberDestinationPerProvider
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CloneConfig()
        defaultDirectory = (try? c.decode(String.self, forKey: .defaultDirectory)) ?? defaults.defaultDirectory
        openAfterClone = (try? c.decode(Bool.self, forKey: .openAfterClone)) ?? defaults.openAfterClone
        preferredProtocol = (try? c.decode(String.self, forKey: .preferredProtocol)) ?? defaults.preferredProtocol
        preferredCLI = (try? c.decode(String.self, forKey: .preferredCLI)) ?? defaults.preferredCLI
        rememberDestinationPerProvider = (try? c.decode(Bool.self, forKey: .rememberDestinationPerProvider)) ?? defaults.rememberDestinationPerProvider
    }
}

public struct GeneralConfig: Codable, Equatable, Sendable {
    /// Telemetry and update-check toggles were removed in iter 5 because the
    /// app doesn't implement those features. Old config files containing those
    /// keys still decode cleanly because we ignore unknown keys.
    public init() {}

    public init(from decoder: Decoder) throws {
        // Tolerant decoder: silently drop any legacy keys.
        _ = try? decoder.container(keyedBy: AnyCodingKey.self)
    }

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? {
            nil
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            return nil
        }
    }
}

public struct AppearanceConfig: Codable, Equatable, Sendable {
    public var theme: String // system | light | dark
    public var density: String // compact | comfortable
    public var fontSize: Int
    public var diffFont: String
    public var fileListMode: String // tree | flat
    public var graphLaneWidth: Int

    public init(
        theme: String = "system",
        density: String = "comfortable",
        fontSize: Int = 13,
        diffFont: String = "SF Mono",
        fileListMode: String = "tree",
        graphLaneWidth: Int = 16
    ) {
        self.theme = theme
        self.density = density
        self.fontSize = fontSize
        self.diffFont = diffFont
        self.fileListMode = fileListMode
        self.graphLaneWidth = graphLaneWidth
    }
}

public struct GitConfig: Codable, Equatable, Sendable {
    public var defaultAuthorName: String
    public var defaultAuthorEmail: String
    public var signCommits: Bool
    public var fetchInterval: Int // minutes; 0 = manual
    public var autoRefresh: Bool
    public var pruneOnFetch: Bool
    public var externalEditor: String
    public var terminalApp: String

    public init(
        defaultAuthorName: String = "",
        defaultAuthorEmail: String = "",
        signCommits: Bool = false,
        fetchInterval: Int = 0,
        autoRefresh: Bool = true,
        pruneOnFetch: Bool = true,
        externalEditor: String = "",
        terminalApp: String = ""
    ) {
        self.defaultAuthorName = defaultAuthorName
        self.defaultAuthorEmail = defaultAuthorEmail
        self.signCommits = signCommits
        self.fetchInterval = fetchInterval
        self.autoRefresh = autoRefresh
        self.pruneOnFetch = pruneOnFetch
        self.externalEditor = externalEditor
        self.terminalApp = terminalApp
    }
}

public struct IntegrationsConfig: Codable, Equatable, Sendable {
    public var accounts: [ProviderAccount]
    public init(accounts: [ProviderAccount] = []) {
        self.accounts = accounts
    }
}

public struct ProviderAccount: Codable, Equatable, Identifiable, Sendable {
    public var id: String // uuid string
    public var kind: String // "github" | "gitlab"
    public var instanceURL: String // empty = github.com or gitlab.com
    public var username: String
    public var keychainItem: String // Keychain account reference
    public var lastValidatedISO: String // ISO-8601 timestamp, empty if never validated
    public var status: String // ok | invalid | unreachable | unknown

    public init(
        id: String = UUID().uuidString,
        kind: String,
        instanceURL: String = "",
        username: String,
        keychainItem: String,
        lastValidatedISO: String = "",
        status: String = "unknown"
    ) {
        self.id = id
        self.kind = kind
        self.instanceURL = instanceURL
        self.username = username
        self.keychainItem = keychainItem
        self.lastValidatedISO = lastValidatedISO
        self.status = status
    }
}

public struct AIConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var backend: String // command | openai
    public var model: String
    public var temperature: Double
    public var maxTokens: Int
    public var promptTemplate: String
    public var conventionalCommits: Bool
    public var subjectSoftLimit: Int
    public var subjectHardLimit: Int
    public var bodyWrap: Int
    public var commandTemplate: String
    public var openAIBaseURL: String
    public var openAIKeychainItem: String
    public var timeoutSeconds: Int
    public var reasoningEffort: String // "" | "minimal" | "low" | "medium" | "high"
    public var directInsert: Bool // skip the preview card; replace commit fields directly

    public init(
        enabled: Bool = false,
        backend: String = "command",
        model: String = "",
        temperature: Double = 0.2,
        maxTokens: Int = 800,
        promptTemplate: String = AIConfig.defaultPromptTemplate,
        conventionalCommits: Bool = true,
        subjectSoftLimit: Int = 50,
        subjectHardLimit: Int = 72,
        bodyWrap: Int = 72,
        commandTemplate: String = "codex exec --model ${model}",
        openAIBaseURL: String = "https://api.openai.com/v1",
        openAIKeychainItem: String = "avi.openai.apiKey",
        timeoutSeconds: Int = 120,
        reasoningEffort: String = "",
        directInsert: Bool = true
    ) {
        self.enabled = enabled
        self.backend = backend
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.promptTemplate = promptTemplate
        self.conventionalCommits = conventionalCommits
        self.subjectSoftLimit = subjectSoftLimit
        self.subjectHardLimit = subjectHardLimit
        self.bodyWrap = bodyWrap
        self.commandTemplate = commandTemplate
        self.openAIBaseURL = openAIBaseURL
        self.openAIKeychainItem = openAIKeychainItem
        self.timeoutSeconds = timeoutSeconds
        self.reasoningEffort = reasoningEffort
        self.directInsert = directInsert
    }

    public static let defaultPromptTemplate = """
    Generate commit message for ${target}.
    - Only respond with the commit message.
    - Start directly with the subject line (no preamble).
    - The header must be less than ${lowLimit} (soft limit) and ${highLimit} (hard limit).
    - Hard wrap lines at ${guideLine} characters.
    - Don't use the 'generated' footer.

    - Use Conventional Commits style:
      <type>(<scope>): <summary>
    """

    /// Tolerant decoder: any field can be missing in an older config file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AIConfig()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? defaults.enabled
        backend = (try? c.decode(String.self, forKey: .backend)) ?? defaults.backend
        model = (try? c.decode(String.self, forKey: .model)) ?? defaults.model
        temperature = (try? c.decode(Double.self, forKey: .temperature)) ?? defaults.temperature
        maxTokens = (try? c.decode(Int.self, forKey: .maxTokens)) ?? defaults.maxTokens
        promptTemplate = (try? c.decode(String.self, forKey: .promptTemplate)) ?? defaults.promptTemplate
        conventionalCommits = (try? c.decode(Bool.self, forKey: .conventionalCommits)) ?? defaults.conventionalCommits
        subjectSoftLimit = (try? c.decode(Int.self, forKey: .subjectSoftLimit)) ?? defaults.subjectSoftLimit
        subjectHardLimit = (try? c.decode(Int.self, forKey: .subjectHardLimit)) ?? defaults.subjectHardLimit
        bodyWrap = (try? c.decode(Int.self, forKey: .bodyWrap)) ?? defaults.bodyWrap
        commandTemplate = (try? c.decode(String.self, forKey: .commandTemplate)) ?? defaults.commandTemplate
        openAIBaseURL = (try? c.decode(String.self, forKey: .openAIBaseURL)) ?? defaults.openAIBaseURL
        openAIKeychainItem = (try? c.decode(String.self, forKey: .openAIKeychainItem)) ?? defaults.openAIKeychainItem
        timeoutSeconds = (try? c.decode(Int.self, forKey: .timeoutSeconds)) ?? defaults.timeoutSeconds
        reasoningEffort = (try? c.decode(String.self, forKey: .reasoningEffort)) ?? defaults.reasoningEffort
        directInsert = (try? c.decode(Bool.self, forKey: .directInsert)) ?? defaults.directInsert
    }
}

public struct ExternalToolsConfig: Codable, Equatable, Sendable {
    public var gitPath: String
    public var ghPath: String
    public var glabPath: String
    public var codexPath: String
    public var claudePath: String
    public var editorPath: String
    public var terminalPath: String
    public var diffToolPath: String
    public var mergeToolPath: String

    public init(
        gitPath: String = "",
        ghPath: String = "",
        glabPath: String = "",
        codexPath: String = "",
        claudePath: String = "",
        editorPath: String = "",
        terminalPath: String = "",
        diffToolPath: String = "",
        mergeToolPath: String = ""
    ) {
        self.gitPath = gitPath
        self.ghPath = ghPath
        self.glabPath = glabPath
        self.codexPath = codexPath
        self.claudePath = claudePath
        self.editorPath = editorPath
        self.terminalPath = terminalPath
        self.diffToolPath = diffToolPath
        self.mergeToolPath = mergeToolPath
    }
}

public struct AdvancedConfig: Codable, Equatable, Sendable {
    public var historyLimit: Int
    public var verboseLogging: Bool

    public init(historyLimit: Int = 200, verboseLogging: Bool = false) {
        self.historyLimit = historyLimit
        self.verboseLogging = verboseLogging
    }
}
