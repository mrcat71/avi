import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var store = ConfigStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Theme") {
                SettingsFormRow("Appearance") {
                    Picker("", selection: themeBinding) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 300)
                }
            }

            SettingsGroup("Density") {
                SettingsFormRow("Row density", description: "Compact for dense lists, comfortable for readability.") {
                    Picker("", selection: densityBinding) {
                        Text("Compact").tag("compact")
                        Text("Comfortable").tag("comfortable")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Font size") {
                    HStack {
                        Slider(value: fontSizeBinding, in: 11...16, step: 1)
                            .frame(maxWidth: 220)
                        Text("\(store.config.appearance.fontSize) pt")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsGroup("Diff & Graph") {
                SettingsFormRow("Diff font") {
                    TextField("", text: diffFontBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                Divider().padding(.vertical, 4)
                SettingsFormRow("Graph lane width") {
                    Picker("", selection: laneWidthBinding) {
                        Text("12 pt").tag(12)
                        Text("16 pt").tag(16)
                        Text("20 pt").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }

            SettingsGroup("File List") {
                SettingsFormRow("Local Changes display") {
                    Picker("", selection: fileListModeBinding) {
                        Text("Tree").tag("tree")
                        Text("Flat list").tag("flat")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
        }
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { store.config.appearance.theme },
            set: { v in store.update { $0.appearance.theme = v } }
        )
    }

    private var densityBinding: Binding<String> {
        Binding(
            get: { store.config.appearance.density },
            set: { v in
                store.update { $0.appearance.density = v }
                NotificationCenter.default.post(name: .aviDensityChanged, object: nil)
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(store.config.appearance.fontSize) },
            set: { v in store.update { $0.appearance.fontSize = Int(v) } }
        )
    }

    private var diffFontBinding: Binding<String> {
        Binding(
            get: { store.config.appearance.diffFont },
            set: { v in store.update { $0.appearance.diffFont = v } }
        )
    }

    private var laneWidthBinding: Binding<Int> {
        Binding(
            get: { store.config.appearance.graphLaneWidth },
            set: { v in store.update { $0.appearance.graphLaneWidth = v } }
        )
    }

    private var fileListModeBinding: Binding<String> {
        Binding(
            get: { store.config.appearance.fileListMode },
            set: { v in store.update { $0.appearance.fileListMode = v } }
        )
    }
}
