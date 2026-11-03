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
/// `SettingsHeroRow` and needs no title.
struct SettingsGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, SettingsMetrics.inset)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsMetrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(DS.Palette.groupFill))
        }
        .toggleStyle(SettingsSwitchStyle())
        .padding(.bottom, 24)
    }
}

/// A setting: what it is and does on the left, its control on the right.
/// `.stacked` puts a wide control, such as a text editor, under the label.
/// `detail` goes under the description, for a status the control acts on.
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

    var body: some View {
        Group {
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
            detail
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
