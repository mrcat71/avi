import SwiftUI

struct AISettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var openAIKey = ""
    @State private var hasStoredKey = false
    @State private var validation: AIValidationReport?
    @State private var isChecking = false
    @State private var prompt = PromptKind.commit
    @FocusState private var isEditingPrompt: Bool

    private var ai: AIConfig {
        store.config.ai
    }

    private var usesAPI: Bool {
        ai.backend == "openai"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup {
                SettingsFormRow(
                    "AI commit messages",
                    description: "Adds Generate to the commit message, and AI actions to commits and plans. "
                        + "Avi sends the diff they work on to the backend below."
                ) {
                    Toggle("AI commit messages", isOn: bind(\.ai.enabled))
                        .labelsHidden()
                }
            }

            SettingsGroup("Setup") {
                SettingsFormRow(
                    "Backend",
                    description: usesAPI
                        ? "Calls an OpenAI-compatible API with your key."
                        : "Runs a command on your Mac, such as codex or claude, with the prompt."
                ) {
                    Picker("Backend", selection: bind(\.ai.backend)) {
                        Text("Command").tag("command")
                        Text("OpenAI-compatible API").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
                SettingsDivider()
                SettingsFormRow("Model", description: "Any model your backend accepts.") {
                    SettingsTextField("Model", text: bind(\.ai.model), prompt: AIConfig.defaultModel, maxWidth: 240)
                }
                if usesAPI {
                    SettingsDivider()
                    apiKeyRow
                }
                SettingsDivider()
                setupRow
            }

            SettingsGroup("Messages") {
                SettingsFormRow(
                    "Conventional Commits",
                    description: "Asks for type(scope): summary subjects. Applies to prompts that use ${style}, as the built-in ones do."
                ) {
                    Toggle("Conventional Commits", isOn: bind(\.ai.conventionalCommits))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsFormRow(
                    "Insert directly",
                    description: "Puts a generated message straight into the summary and body. Off shows it first, with Replace, Append, and Discard."
                ) {
                    Toggle("Insert directly", isOn: bind(\.ai.directInsert))
                        .labelsHidden()
                }
            }

            SettingsAdvancedSection(.ai) {
                generation
                if usesAPI {
                    api
                } else {
                    command
                }
                limits
                prompts
            }
        }
        .task {
            refreshStoredKey()
            if ai.enabled {
                runValidation()
            }
        }
        .onChange(of: ai.backend) { _, _ in
            validation = nil
            refreshStoredKey()
        }
    }

    // MARK: Backend

    private var apiKeyRow: some View {
        SettingsFormRow("API key", description: "Kept in your Keychain, never in the config file.") {
            HStack(spacing: 6) {
                SettingsTextField("API key", text: $openAIKey, prompt: hasStoredKey ? "Replace the stored key" : "sk-…", isSecure: true, maxWidth: 200)
                Button("Save Key", action: saveKey)
                    .disabled(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } detail: {
            HStack(spacing: 8) {
                if hasStoredKey {
                    SettingsStatus("A key is stored", tone: .success)
                    Button("Delete Key", role: .destructive, action: deleteKey)
                } else {
                    SettingsStatus("No key stored", tone: .warning)
                }
            }
            .padding(.top, 6)
        }
    }

    private var setupRow: some View {
        SettingsFormRow("Status", description: "Checked again before each generation.") {
            Button(action: runValidation) {
                if isChecking {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Check Setup")
                }
            }
            .disabled(isChecking)
        } detail: {
            if let validation {
                VStack(alignment: .leading, spacing: 3) {
                    if validation.isValid {
                        SettingsStatus(readySummary(validation), tone: .success)
                            .textSelection(.enabled)
                    }
                    ForEach(validation.messages, id: \.self) { message in
                        SettingsStatus(message, tone: .warning)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func readySummary(_ report: AIValidationReport) -> String {
        let parts = [report.resolvedExecutable, report.detectedVersion].compactMap(\.self)
        return parts.isEmpty ? "Ready" : "Ready: " + parts.joined(separator: ", ")
    }

    // MARK: Advanced

    private var generation: some View {
        SettingsGroup("Generation") {
            SettingsFormRow(
                "Reasoning effort",
                description: usesAPI ? "Sent as reasoning_effort." : "Given to the command as ${effort} and ${effort_kv}."
            ) {
                SettingsPopupMenu("Reasoning effort", selection: bind(\.ai.reasoningEffort), items: Self.effortItems, fallbackTitle: ai.reasoningEffort)
            }
            if usesAPI {
                SettingsDivider()
                SettingsFormRow("Temperature", description: "Lower is steadier, higher more varied.") {
                    HStack(spacing: 8) {
                        Slider(value: bind(\.ai.temperature), in: 0 ... 1, step: 0.05)
                            .frame(maxWidth: 160)
                            .accessibilityLabel("Temperature")
                        Text(String(format: "%.2f", ai.temperature))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsDivider()
                SettingsFormRow("Max tokens", description: "The longest answer the API may give.") {
                    Stepper(value: bind(\.ai.maxTokens), in: 100 ... 4000, step: 100) {
                        Text("\(ai.maxTokens)")
                            .font(.system(size: 12).monospacedDigit())
                    }
                }
            }
            SettingsDivider()
            SettingsFormRow("Timeout", description: "Stops a generation that takes longer.") {
                Stepper(value: bind(\.ai.timeoutSeconds), in: 30 ... 600, step: 30) {
                    Text("\(ai.timeoutSeconds) s")
                        .font(.system(size: 12).monospacedDigit())
                }
            }
        }
    }

    private var command: some View {
        SettingsGroup(
            "Command",
            footer: "${model} is the model above. ${prompt_file} is a file with the prompt, which also arrives on standard input. "
                + "${effort_kv} becomes codex's -c model_reasoning_effort=<effort> when an effort is chosen, and ${effort} the effort itself."
        ) {
            SettingsFormRow("Command template", layout: .stacked) {
                SettingsTextField(
                    "Command template",
                    text: bind(\.ai.commandTemplate),
                    prompt: AIConfig().commandTemplate,
                    monospaced: true,
                    maxWidth: .infinity
                )
            }
            SettingsDivider()
            SettingsFormRow("Runs", layout: .stacked) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedCommandPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    if effortPickedButNotUsed {
                        SettingsStatus(
                            "Add ${effort_kv} (codex) or ${effort} to the template to use the reasoning effort.",
                            tone: .warning,
                            symbol: "lightbulb"
                        )
                    }
                }
            }
        }
    }

    private var api: some View {
        SettingsGroup("API") {
            SettingsFormRow("Base URL", description: "Any OpenAI-compatible endpoint, such as a local server.") {
                SettingsTextField("Base URL", text: bind(\.ai.openAIBaseURL), prompt: AIConfig().openAIBaseURL, monospaced: true, maxWidth: 280)
            }
        }
    }

    private var limits: some View {
        SettingsGroup("Message Limits", footer: "Prompts get these as ${lowLimit}, ${highLimit}, and ${guideLine}.") {
            limitRow("Subject soft limit", value: \.ai.subjectSoftLimit, range: 30 ... 100)
            SettingsDivider()
            limitRow("Subject hard limit", value: \.ai.subjectHardLimit, range: 40 ... 120)
            SettingsDivider()
            limitRow("Body wrap", value: \.ai.bodyWrap, range: 60 ... 120)
        }
    }

    private func limitRow(_ label: String, value: WritableKeyPath<AviConfig, Int>, range: ClosedRange<Int>) -> some View {
        SettingsFormRow(label) {
            Stepper(value: bind(value), in: range) {
                Text("\(store.config[keyPath: value]) characters")
                    .font(.system(size: 12).monospacedDigit())
            }
        }
    }

    private var prompts: some View {
        SettingsGroup("Prompts") {
            SettingsFormRow("Prompt", description: prompt.purpose) {
                SettingsPopupMenu("Prompt", selection: $prompt, items: PromptKind.allCases.map { .option($0, $0.title) })
            }
            SettingsDivider()
            SettingsFormRow("Template", layout: .stacked) {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: bind(prompt.keyPath))
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .focused($isEditingPrompt)
                        .padding(6)
                        .frame(minHeight: 200, maxHeight: 360)
                        .modifier(AviFieldWell(isFocused: isEditingPrompt))
                        .accessibilityLabel("\(prompt.title) prompt")
                    HStack(alignment: .firstTextBaseline) {
                        // A word joiner keeps each ${name} whole when the line wraps.
                        Text(prompt.variables.replacingOccurrences(of: "${", with: "$\u{2060}{"))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Reset to Default") {
                            store.update { $0[keyPath: prompt.keyPath] = prompt.defaultTemplate }
                        }
                        .disabled(store.config[keyPath: prompt.keyPath] == prompt.defaultTemplate)
                    }
                }
            }
        }
    }

    // MARK: Values

    static let effortItems: [SettingsPopupMenu<String>.Item] = [
        .option("", "None"),
        .divider,
        .option("minimal", "Minimal"),
        .option("low", "Low"),
        .option("medium", "Medium"),
        .option("high", "High")
    ]

    /// The command template with the settings filled in. `${prompt_file}`
    /// shows as a sample path because each run gets its own.
    private var resolvedCommandPreview: String {
        let template = ai.commandTemplate.isEmpty ? "(empty)" : ai.commandTemplate
        let effortKV = ai.reasoningEffort.isEmpty ? "" : "-c model_reasoning_effort=\(ai.reasoningEffort)"
        return template
            .replacingOccurrences(of: "${model}", with: ai.model.isEmpty ? "<model>" : ai.model)
            .replacingOccurrences(of: "${effort_kv}", with: effortKV)
            .replacingOccurrences(of: "${effort}", with: ai.reasoningEffort)
            .replacingOccurrences(of: "${prompt_file}", with: "/tmp/avi-prompt.txt")
    }

    private var effortPickedButNotUsed: Bool {
        guard !ai.reasoningEffort.isEmpty else { return false }
        return !ai.commandTemplate.contains("${effort}") && !ai.commandTemplate.contains("${effort_kv}")
    }

    // MARK: Actions

    private func saveKey() {
        let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.setString(trimmed, account: ai.openAIKeychainItem)
            openAIKey = ""
            refreshStoredKey()
        } catch {
            SettingsNotices.error("Could not save the API key: \(error)")
        }
    }

    private func deleteKey() {
        if !KeychainStore.deleteString(account: ai.openAIKeychainItem) {
            SettingsNotices.error("Could not delete the API key from the Keychain.")
        }
        refreshStoredKey()
    }

    private func refreshStoredKey() {
        hasStoredKey = KeychainStore.getString(account: ai.openAIKeychainItem) != nil
    }

    private func runValidation() {
        isChecking = true
        let snapshot = ai
        Task {
            validation = await AICLIValidator.validate(snapshot)
            isChecking = false
        }
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The prompts Settings > AI Commit Messages edits.
enum PromptKind: String, CaseIterable, Identifiable, Hashable {
    case commit
    case reword
    case split
    case planRevision

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .commit: return "Commit message"
        case .reword: return "Reword"
        case .split: return "Split into commits"
        case .planRevision: return "Revise a plan"
        }
    }

    var purpose: String {
        switch self {
        case .commit: return "Writes a message for the staged changes or a planned commit."
        case .reword: return "Rewrites an existing commit's message."
        case .split: return "Groups changes into several commits; must answer in JSON."
        case .planRevision: return "Changes planned commits as you ask; must answer in JSON."
        }
    }

    var keyPath: WritableKeyPath<AviConfig, String> {
        switch self {
        case .commit: return \.ai.promptTemplate
        case .reword: return \.ai.rewordPromptTemplate
        case .split: return \.ai.splitPromptTemplate
        case .planRevision: return \.ai.planRevisionPromptTemplate
        }
    }

    var defaultTemplate: String {
        switch self {
        case .commit: return AIConfig.defaultPromptTemplate
        case .reword: return AIConfig.defaultRewordPromptTemplate
        case .split: return AIConfig.defaultSplitPromptTemplate
        case .planRevision: return AIConfig.defaultPlanRevisionPromptTemplate
        }
    }

    /// The `${name}` values this prompt gets.
    var variables: String {
        let common = "${branch} ${repo} ${model} ${lowLimit} ${highLimit} ${guideLine} ${style}"
        switch self {
        case .commit: return "${target} ${staged_diff} ${files} " + common
        case .reword: return "${existing_message} ${commit_diff} " + common
        case .split: return "${target} " + common
        case .planRevision: return "${instructions} ${plan} ${target} ${files} " + common
        }
    }
}
