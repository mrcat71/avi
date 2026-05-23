import SwiftUI

struct ExternalToolsSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var detection: [DetectedTool] = []
    @State private var isDetecting = false
    @State private var testing: Set<String> = []
    @State private var testResults: [String: AICLIValidator.TestResult] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Auto-detected tools") {
                SettingsFormRow("Status") {
                    HStack(spacing: 8) {
                        Text("\(detection.count(where: { $0.isAvailable })) of \(detection.count) tools found")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: redetect) {
                            HStack(spacing: 4) {
                                if isDetecting {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Re-detect")
                            }
                        }
                        .disabled(isDetecting)
                    }
                }
                Divider().padding(.vertical, 4)
                ForEach(detection) { tool in
                    toolRow(tool)
                    if tool.id != detection.last?.id {
                        Divider().padding(.vertical, 4)
                    }
                }
            }
        }
        .task {
            if detection.isEmpty {
                redetect()
            }
        }
    }

    private func toolRow(_ tool: DetectedTool) -> some View {
        SettingsFormRow(tool.displayName, description: tool.version) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: tool.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(tool.isAvailable ? .green : .red)
                    Text(tool.isAvailable ? "Found" : "Not found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tool.isAvailable ? .green : .red)
                    if let path = tool.detectedPath {
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if tool.isAvailable {
                        Button(action: { runTest(tool: tool) }) {
                            if testing.contains(tool.id) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Test")
                            }
                        }
                        .disabled(testing.contains(tool.id))
                    }
                }
                TextField("Override path…", text: overrideBinding(for: tool.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: 420)

                if let result = testResults[tool.id] {
                    testResultView(result)
                }
            }
        }
    }

    @ViewBuilder
    private func testResultView(_ result: AICLIValidator.TestResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if result.timedOut {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Timed out after \(result.durationMS / 1000)s")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                } else if let exit = result.exitCode, exit == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("exit 0 · \(result.durationMS) ms")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("exit \(result.exitCode.map(String.init) ?? "?") · \(result.durationMS) ms")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            if !result.stdoutFirstLine.isEmpty {
                Text("stdout: \(result.stdoutFirstLine)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !result.stderrFirstLine.isEmpty {
                Text("stderr: \(result.stderrFirstLine)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.85))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func runTest(tool: DetectedTool) {
        guard let path = tool.detectedPath else { return }
        testing.insert(tool.id)
        Task {
            let result = await AICLIValidator.runTest(executable: path)
            await MainActor.run {
                testResults[tool.id] = result
                testing.remove(tool.id)
            }
        }
    }

    private func redetect() {
        isDetecting = true
        Task.detached(priority: .userInitiated) {
            let tools = ExternalToolsScanner.detectAll()
            await MainActor.run {
                detection = tools
                isDetecting = false
            }
        }
    }

    private func overrideBinding(for id: String) -> Binding<String> {
        Binding(
            get: { value(forToolID: id) },
            set: { v in setValue(forToolID: id, value: v) }
        )
    }

    private func value(forToolID id: String) -> String {
        switch id {
        case "git": return store.config.externalTools.gitPath
        case "gh": return store.config.externalTools.ghPath
        case "glab": return store.config.externalTools.glabPath
        case "codex": return store.config.externalTools.codexPath
        case "claude": return store.config.externalTools.claudePath
        case "editor": return store.config.externalTools.editorPath
        case "terminal": return store.config.externalTools.terminalPath
        case "diffTool": return store.config.externalTools.diffToolPath
        case "mergeTool": return store.config.externalTools.mergeToolPath
        default: return ""
        }
    }

    private func setValue(forToolID id: String, value: String) {
        store.update { config in
            switch id {
            case "git": config.externalTools.gitPath = value
            case "gh": config.externalTools.ghPath = value
            case "glab": config.externalTools.glabPath = value
            case "codex": config.externalTools.codexPath = value
            case "claude": config.externalTools.claudePath = value
            case "editor": config.externalTools.editorPath = value
            case "terminal": config.externalTools.terminalPath = value
            case "diffTool": config.externalTools.diffToolPath = value
            case "mergeTool": config.externalTools.mergeToolPath = value
            default: break
            }
        }
    }
}
