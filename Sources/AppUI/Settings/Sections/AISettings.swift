import SwiftUI

struct AISettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var openAIKey: String = ""
    @State private var validation: AIValidationReport?
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Validation") {
                SettingsFormRow("Status", description: "Checked before generation. Re-runs on demand.") {
                    HStack(spacing: 8) {
                        if isChecking {
                            ProgressView().controlSize(.mini)
                        } else if let v = validation {
                            Image(systemName: v.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(v.isValid ? .green : .orange)
                            Text(v.isValid ? "OK" : "\(v.messages.count) issue\(v.messages.count == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(v.isValid ? .green : .orange)
                        } else {
                            Text("Not checked yet")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Re-check", action: runValidation)
                    }
                }
                if let v = validation {
                    if let exe = v.resolvedExecutable {
                        Divider().padding(.vertical, 4)
                        SettingsFormRow("Resolved") {
                            Text(exe)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if let version = v.detectedVersion {
                        Divider().padding(.vertical, 4)
                        SettingsFormRow("Version") {
                            Text(version)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    if !v.messages.isEmpty {
                        Divider().padding(.vertical, 4)
                        SettingsFormRow("Issues") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(v.messages, id: \.self) { msg in
                                    Text("• \(msg)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }

            SettingsGroup("Generation") {
                SettingsFormRow("Enable AI commit messages") {
                    Toggle("", isOn: bind(\.ai.enabled))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Backend") {
                    Picker("", selection: bind(\.ai.backend)) {
                        Text("Custom command").tag("command")
                        Text("OpenAI-compatible API").tag("openai")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Model") {
                    TextField("gpt-5 / claude-3-7-sonnet / ...", text: bind(\.ai.model))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Temperature") {
                    HStack {
                        Slider(value: bind(\.ai.temperature), in: 0 ... 1, step: 0.05)
                            .frame(maxWidth: 220)
                        Text(String(format: "%.2f", store.config.ai.temperature))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Max tokens") {
                    Stepper(value: bind(\.ai.maxTokens), in: 100 ... 4000, step: 100) {
                        Text("\(store.config.ai.maxTokens)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Timeout", description: "Kill the AI command if it doesn't finish.") {
                    Stepper(value: bind(\.ai.timeoutSeconds), in: 30 ... 600, step: 30) {
                        Text("\(store.config.ai.timeoutSeconds) seconds")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            if store.config.ai.backend == "command" {
                SettingsGroup("Custom command") {
                    SettingsFormRow("Command template", description: "Variables: ${model}, ${prompt_file}. Prompt is also piped on stdin.") {
                        TextField("codex exec --model ${model}", text: bind(\.ai.commandTemplate))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 400)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            } else {
                SettingsGroup("OpenAI-compatible API") {
                    SettingsFormRow("Base URL") {
                        TextField("https://api.openai.com/v1", text: bind(\.ai.openAIBaseURL))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 400)
                    }
                    Divider().padding(.vertical, 4)
                    SettingsFormRow("API key", description: "Stored in macOS Keychain.") {
                        HStack(spacing: 8) {
                            SecureField("sk-…", text: $openAIKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                            Button("Save Key") {
                                let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                try? KeychainStore.setString(trimmed, account: store.config.ai.openAIKeychainItem)
                                openAIKey = ""
                            }
                            .disabled(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Divider().padding(.vertical, 4)
                    SettingsFormRow("") {
                        HStack {
                            Text(KeychainStore.getString(account: store.config.ai.openAIKeychainItem) != nil ? "Key stored ✓" : "No key stored")
                                .font(.system(size: 11))
                                .foregroundStyle(KeychainStore.getString(account: store.config.ai.openAIKeychainItem) != nil ? .green : .secondary)
                            Spacer()
                            Button("Delete Key") {
                                KeychainStore.deleteString(account: store.config.ai.openAIKeychainItem)
                            }
                            .disabled(KeychainStore.getString(account: store.config.ai.openAIKeychainItem) == nil)
                        }
                    }
                }
            }

            SettingsGroup("Style") {
                SettingsFormRow("Conventional Commits") {
                    Toggle("", isOn: bind(\.ai.conventionalCommits))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Subject soft limit") {
                    Stepper(value: bind(\.ai.subjectSoftLimit), in: 30 ... 100, step: 1) {
                        Text("\(store.config.ai.subjectSoftLimit) chars")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Subject hard limit") {
                    Stepper(value: bind(\.ai.subjectHardLimit), in: 40 ... 120, step: 1) {
                        Text("\(store.config.ai.subjectHardLimit) chars")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Body wrap") {
                    Stepper(value: bind(\.ai.bodyWrap), in: 60 ... 120, step: 1) {
                        Text("\(store.config.ai.bodyWrap) chars")
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }

            SettingsGroup("Prompt template") {
                SettingsFormRow("Available variables") {
                    Text("${target}, ${staged_diff}, ${lowLimit}, ${highLimit}, ${guideLine}, ${branch}, ${files}, ${repo}, ${model}")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Template") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: bind(\.ai.promptTemplate))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 200, maxHeight: 400)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                            )
                        HStack {
                            Spacer()
                            Button("Reset to default") {
                                store.update { $0.ai.promptTemplate = AIConfig.defaultPromptTemplate }
                            }
                        }
                    }
                }
            }
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: kp] },
            set: { v in store.update { $0[keyPath: kp] = v } }
        )
    }

    private func runValidation() {
        isChecking = true
        let snapshot = store.config.ai
        Task {
            let report = await AICLIValidator.validate(snapshot)
            await MainActor.run {
                validation = report
                isChecking = false
            }
        }
    }
}
