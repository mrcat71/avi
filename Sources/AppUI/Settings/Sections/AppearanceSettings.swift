import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var store = ConfigStore.shared
    @State private var fontFamilies: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsGroup("Theme") {
                SettingsFormRow("Appearance") {
                    Picker("Appearance", selection: bind(\.appearance.theme)) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                SettingsDivider()
                SettingsFormRow("Row density", description: "Compact fits more rows; comfortable is easier to read.") {
                    Picker("Row density", selection: densityBinding) {
                        Text("Compact").tag("compact")
                        Text("Comfortable").tag("comfortable")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }

            SettingsGroup("Changes and History") {
                SettingsFormRow("Changed files", description: "How Local Changes lists them.") {
                    Picker("Changed files", selection: bind(\.appearance.fileListMode)) {
                        Text("Tree").tag("tree")
                        Text("Flat list").tag("flat")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                SettingsDivider()
                SettingsFormRow("Diff text size", description: "Diffs and their line numbers.") {
                    HStack(spacing: 8) {
                        Slider(value: fontSizeBinding, in: 11 ... 16, step: 1)
                            .frame(maxWidth: 180)
                            .accessibilityLabel("Diff text size")
                        Text("\(store.config.appearance.fontSize - 1) pt")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                SettingsDivider()
                SettingsFormRow(
                    "Author pictures",
                    description: "Shows each author's picture beside their name in History. Avi asks the repository's "
                        + "GitHub or GitLab which account wrote each commit, signed in with your token from Settings or "
                        + "through gh or glab, and otherwise looks the email address up there and on Gravatar, which only "
                        + "receives a hash of it. Off shows the names alone and asks no server."
                ) {
                    Toggle("Author pictures", isOn: bind(\.appearance.authorPictures))
                        .labelsHidden()
                }
            }

            SettingsAdvancedSection(.appearance) {
                SettingsGroup("Diff and Graph") {
                    SettingsFormRow("Diff font", description: "A monospaced family. SF Mono is the system's.") {
                        SettingsPopupMenu(
                            "Diff font",
                            selection: bind(\.appearance.diffFont),
                            items: fontItems,
                            fallbackTitle: store.config.appearance.diffFont
                        )
                    }
                    SettingsDivider()
                    SettingsFormRow("Graph lane width", description: "The room each branch line takes in History.") {
                        Picker("Graph lane width", selection: bind(\.appearance.graphLaneWidth)) {
                            Text("12 pt").tag(12)
                            Text("16 pt").tag(16)
                            Text("20 pt").tag(20)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }
            }
        }
        .task {
            fontFamilies = MonospacedFonts.families()
        }
    }

    /// SF Mono first, then every installed monospaced family, and the chosen
    /// one even when it is not installed, so the pill can name it.
    private var fontItems: [SettingsPopupMenu<String>.Item] {
        let chosen = store.config.appearance.diffFont.trimmingCharacters(in: .whitespaces)
        var families = fontFamilies.filter { $0 != MonospacedFonts.system }
        if !chosen.isEmpty, chosen != MonospacedFonts.system, !families.contains(chosen) {
            families.insert(chosen, at: 0)
        }
        return [.option(MonospacedFonts.system, "\(MonospacedFonts.system) (System)")]
            + (families.isEmpty ? [] : [.divider])
            + families.map { .option($0, $0) }
    }

    private var densityBinding: Binding<String> {
        Binding(
            get: { store.config.appearance.density },
            set: { value in
                store.update { $0.appearance.density = value }
                NotificationCenter.default.post(name: .aviDensityChanged, object: nil)
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(store.config.appearance.fontSize) },
            set: { value in store.update { $0.appearance.fontSize = Int(value) } }
        )
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AviConfig, T>) -> Binding<T> {
        Binding(
            get: { store.config[keyPath: keyPath] },
            set: { value in store.update { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The monospaced font families Settings offers for diffs.
enum MonospacedFonts {
    /// The system's own, which needs no install; also the default.
    static let system = "SF Mono"

    /// Installed families with a fixed-pitch face, sorted by name.
    @MainActor
    static func families() -> [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName }.filter { !$0.hasPrefix(".") })
        return families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
