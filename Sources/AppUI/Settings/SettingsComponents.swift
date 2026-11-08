import AppKit
import SwiftUI

/// The settings panes' measurements, after Rex's settings: rows in flat
/// rounded cards, each card under a bold title.
enum SettingsMetrics {
    /// From a card's edge to its rows' text and controls.
    static let inset: CGFloat = 12
    /// A hero row's icon, and the gap after it.
    static let heroIcon: CGFloat = 32
    static let heroSpacing: CGFloat = 12
    /// Where the rows under a hero row start, in line with its title.
    static let heroTextInset: CGFloat = heroIcon + heroSpacing
}

/// The compact, circular-thumb switches used throughout Settings.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Switch(configuration: configuration)
    }

    private struct Switch: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? DS.Palette.accent : Color.primary.opacity(0.18))
                    .overlay {
                        Capsule()
                            .strokeBorder(configuration.isOn ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1)
                    }
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            .padding(2)
                    }
                    .frame(width: 30, height: 18)
                    .overlay {
                        if isFocused {
                            Capsule()
                                .stroke(DS.Palette.accent, lineWidth: 2)
                                .padding(-3)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($isFocused)
            .onKeyPress(.space) {
                guard isEnabled else { return .ignored }
                configuration.isOn.toggle()
                return .handled
            }
            .opacity(isEnabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: configuration.isOn)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch)
            }
        }
    }
}

/// A card of rows under a bold title. Put a `SettingsDivider` between rows.
/// A card about one thing, such as Avi itself, starts with a
/// `SettingsHeroRow` and needs no title. `accessory` sits at the end of the
/// title, such as a Re-detect button; `footer` explains the card under it.
struct SettingsGroup<Content: View, Accessory: View>: View {
    let title: String?
    let footer: String?
    let content: Content
    let accessory: Accessory

    init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || Accessory.self != EmptyView.self {
                HStack(alignment: .center, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 8)
                    accessory
                }
                .padding(.horizontal, SettingsMetrics.inset)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(DS.Palette.groupFill))
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsMetrics.inset)
            }
        }
        .toggleStyle(SettingsSwitchStyle())
        .padding(.bottom, 24)
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, footer: footer, content: content, accessory: { EmptyView() })
    }
}

/// Which sections show their Advanced settings, remembered per section.
enum SettingsAdvanced {
    static func key(for section: SettingsSection) -> String {
        "avi.settings.showAdvanced.\(section.rawValue)"
    }

    /// Opens `section`'s Advanced settings, as a search that finds a row in
    /// them does.
    static func reveal(_ section: SettingsSection, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(for: section))
    }
}

/// The settings most people never change, at the end of a section under a
/// row that says what is inside: closed at first, remembered per section,
/// and opened by a search that finds one of them.
struct SettingsAdvancedSection<Content: View>: View {
    let section: SettingsSection
    let content: Content

    @AppStorage private var isExpanded: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ section: SettingsSection, @ViewBuilder content: () -> Content) {
        self.section = section
        self.content = content()
        _isExpanded = AppStorage(wrappedValue: false, SettingsAdvanced.key(for: section))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            disclosure
                .padding(.bottom, 24)
            if isExpanded {
                content
                    .transition(.opacity)
            }
        }
    }

    private var disclosure: some View {
        let shape = RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
        return Button {
            withAnimation(reduceMotion ? nil : Glass.Motion.snappy) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                    if let summary = section.advancedSummary {
                        Text(summary)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, SettingsMetrics.inset)
            .padding(.vertical, 10)
            .background(shape.fill(Color.primary.opacity(isHovering ? 0.07 : 0.045)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Advanced settings")
        .accessibilityValue(isExpanded ? "Shown" : "Hidden")
        .accessibilityHint(section.advancedSummary ?? "")
    }
}

/// A setting: what it is and does on the left, its control on the right.
/// `.stacked` puts a wide control, such as a text editor, under the label.
/// `detail` goes under the row, for a status the control acts on.
struct SettingsFormRow<Content: View, Detail: View>: View {
    enum Layout {
        case inline
        case stacked
    }

    let label: String
    var description: String?
    var layout: Layout = .inline
    let content: Content
    let detail: Detail

    init(
        _ label: String,
        description: String? = nil,
        layout: Layout = .inline,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.label = label
        self.description = description
        self.layout = layout
        self.content = content()
        self.detail = detail()
    }

    /// The control stays centered on the label and description; `detail`
    /// takes the row's whole width under them, so a status or a path field
    /// never pushes the control down.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch layout {
            case .inline:
                HStack(alignment: .center, spacing: 16) {
                    labels
                        .frame(maxWidth: .infinity, alignment: .leading)
                    content
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 8) {
                    labels
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            detail
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SettingsFormRow where Detail == EmptyView {
    init(_ label: String, description: String? = nil, layout: Layout = .inline, @ViewBuilder content: () -> Content) {
        self.init(label, description: description, layout: layout, content: content, detail: { EmptyView() })
    }
}

/// The first row of a card about one thing: its icon, a bold title with a
/// line or two under it, and its action at the end.
struct SettingsHeroRow<Icon: View, Subtitle: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        @ViewBuilder icon: @escaping () -> Icon,
        @ViewBuilder subtitle: @escaping () -> Subtitle,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: SettingsMetrics.heroSpacing) {
            icon()
                .frame(width: SettingsMetrics.heroIcon, height: SettingsMetrics.heroIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                subtitle()
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.vertical, 12)
    }
}

extension SettingsHeroRow where Subtitle == Text {
    init(
        _ title: String,
        subtitle: String,
        @ViewBuilder icon: @escaping () -> Icon,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(title, icon: icon, subtitle: { Text(subtitle) }, trailing: trailing)
    }
}

extension SettingsHeroRow where Subtitle == Text, Trailing == EmptyView {
    init(_ title: String, subtitle: String, @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title, icon: icon, subtitle: { Text(subtitle) }, trailing: { EmptyView() })
    }
}

extension View {
    /// Lines a row under a `SettingsHeroRow` up with the hero's title.
    func settingsHeroIndent() -> some View {
        padding(.leading, SettingsMetrics.heroTextInset)
    }
}

/// The line between two rows of a `SettingsGroup`. Under a hero row it
/// starts at the hero's title, as the rows do.
struct SettingsDivider: View {
    var underHero = false

    var body: some View {
        Divider()
            .padding(.leading, underHero ? SettingsMetrics.heroTextInset : 0)
    }
}

/// A rounded tile with a white symbol, as in System Settings' sidebar.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Image(systemName: symbol)
            .symbolVariant(.fill)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(tint.gradient))
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Avi's icon from the app bundle. Development runs have no bundle icon,
/// so they show General's gear tile instead.
struct SettingsAppIcon: View {
    var size: CGFloat = SettingsMetrics.heroIcon

    var body: some View {
        if Bundle.main.bundleURL.pathExtension == "app" {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            SettingsIcon(symbol: SettingsSection.general.systemImage, tint: SettingsSection.general.tint, size: size)
        }
    }
}

/// A choice among a few values, drawn as the flat pill the sheets use
/// instead of a pop-up button. `items` can hold dividers and actions, such
/// as Choose… for a value the list does not have; `fallbackTitle` names a
/// selection that is not among the options.
struct SettingsPopupMenu<Value: Hashable>: View {
    enum Item {
        case option(Value, String)
        case divider
        case action(String, () -> Void)
    }

    let label: String
    @Binding var selection: Value
    let items: [Item]
    var fallbackTitle = ""
    var maxWidth: CGFloat = 240

    @State private var anchor = AviMenuAnchor()
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ label: String,
        selection: Binding<Value>,
        items: [Item],
        fallbackTitle: String = "",
        maxWidth: CGFloat = 240
    ) {
        self.label = label
        _selection = selection
        self.items = items
        self.fallbackTitle = fallbackTitle
        self.maxWidth = maxWidth
    }

    var body: some View {
        Button(action: showMenu) {
            AviMenuPill(title: currentTitle, maxWidth: maxWidth, isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(AviMenuAnchorView(anchor: anchor))
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(currentTitle)
        .accessibilityHint("Opens a menu")
    }

    private var currentTitle: String {
        Self.title(of: selection, in: items) ?? fallbackTitle
    }

    static func title(of value: Value, in items: [Item]) -> String? {
        for case let .option(option, title) in items where option == value {
            return title
        }
        return nil
    }

    /// The menu a click opens: the options with the chosen one ticked, then
    /// any dividers and actions where `items` puts them.
    static func menu(items: [Item], selection: Value, choose: @escaping (Value) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item {
            case let .option(value, title):
                let menuItem = AviMenuItem(title: title) { choose(value) }
                menuItem.state = value == selection ? .on : .off
                menu.addItem(menuItem)
            case .divider:
                menu.addItem(.separator())
            case let .action(title, perform):
                menu.addItem(AviMenuItem(title: title, handler: perform))
            }
        }
        return menu
    }

    private func showMenu() {
        guard let view = anchor.view, !items.isEmpty else { return }
        let menu = Self.menu(items: items, selection: selection) { selection = $0 }
        menu.minimumWidth = view.bounds.width
        let below = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: view)
    }
}

/// A one-line text field in a settings row, drawn flat like the sheets'
/// fields: a shade off the card, a hairline, the accent while you type.
struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    var monospaced = false
    var isSecure = false
    var maxWidth: CGFloat = 320

    @FocusState private var isFocused: Bool

    init(
        _ label: String,
        text: Binding<String>,
        prompt: String? = nil,
        monospaced: Bool = false,
        isSecure: Bool = false,
        maxWidth: CGFloat = 320
    ) {
        self.label = label
        _text = text
        self.prompt = prompt
        self.monospaced = monospaced
        self.isSecure = isSecure
        self.maxWidth = maxWidth
    }

    var body: some View {
        Group {
            if isSecure {
                SecureField(label, text: $text, prompt: prompt.map { Text($0) })
            } else {
                TextField(label, text: $text, prompt: prompt.map { Text($0) })
            }
        }
        .textFieldStyle(.plain)
        .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
        .focused($isFocused)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .frame(maxWidth: maxWidth)
        .modifier(AviFieldWell(isFocused: isFocused))
        .accessibilityLabel(label)
    }
}

/// A few words of status in a row, such as Found or Not signed in, in the
/// status's color with a symbol, so the color is never all it says.
struct SettingsStatus: View {
    enum Tone {
        case success
        case warning
        case error
        case neutral

        var color: Color {
            switch self {
            case .success: return DS.Palette.success
            case .warning: return DS.Palette.warning
            case .error: return DS.Palette.danger
            case .neutral: return DS.Palette.textSecondary
            }
        }

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .neutral: return "circle.dashed"
            }
        }
    }

    let text: String
    var tone: Tone = .neutral
    var symbol: String?

    init(_ text: String, tone: Tone = .neutral, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol ?? tone.symbol)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tone.color)
    }
}
