import AppKit
import SwiftUI

/// The frame Avi's sheets share, after Rex: an icon tile with the title on
/// top, the content in the middle, and the buttons at the bottom. Fields put
/// their label above the control, and on/off choices are rows of switches in
/// a flat group, instead of a right-aligned form with checkboxes.
struct AviPopup<Content: View, Footer: View>: View {
    let symbol: String
    var tint: Color = DS.Palette.accent
    let title: String
    var subtitle: String?
    /// Nil lets the content size the sheet.
    var width: CGFloat? = 460
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AviPopupHeader(symbol: symbol, tint: tint, title: title, subtitle: subtitle)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            AviPopupFooter {
                footer()
            }
        }
        .frame(width: width)
        // The sheet takes the content's full height, so text editors and
        // scroll views never squeeze the header or the buttons out of it.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A sheet's icon tile and title, with an optional accessory at the end.
struct AviPopupHeader<Accessory: View>: View {
    let symbol: String
    var tint: Color = DS.Palette.accent
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AviPopupIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }
}

extension AviPopupHeader where Accessory == EmptyView {
    init(symbol: String, tint: Color = DS.Palette.accent, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

/// The rounded icon tile at the start of a sheet's header.
struct AviPopupIcon: View {
    let symbol: String
    var tint: Color = DS.Palette.accent
    var size: CGFloat = 34

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(tint.gradient))
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The buttons under a sheet's content. Put an `AviPopupFooterNote` or a
/// `Spacer` first, then Cancel and the action.
struct AviPopupFooter<Content: View>: View {
    /// A line above the buttons, for a sheet whose content scrolls up to them.
    var separated = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, separated ? 12 : 2)
        .padding(.bottom, separated ? 12 : 18)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .overlay(alignment: .top) {
            if separated {
                Divider()
            }
        }
    }
}

/// Small print at the start of the footer; it takes the free width.
struct AviPopupFooterNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(DS.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A field's name above its control, as Rex titles its groups.
struct AviPopupLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.Palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labelled control: the label above it, a note under it.
struct AviPopupField<Control: View>: View {
    let label: String
    var note: String?
    var noteTone: AviPopupNote.Tone = .secondary
    @ViewBuilder let control: () -> Control

    init(
        _ label: String,
        note: String? = nil,
        noteTone: AviPopupNote.Tone = .secondary,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.label = label
        self.note = note
        self.noteTone = noteTone
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AviPopupLabel(label)
            control()
            if let note, !note.isEmpty {
                AviPopupNote(note, tone: noteTone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rows on a flat rounded card, such as a sheet's switches, as in Settings.
struct AviPopupGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Glass.Corner.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(DS.Palette.groupFill))
    }
}

/// The line between two rows of an `AviPopupGroup`, in line with their text.
struct AviPopupGroupDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}

/// An on/off choice in an `AviPopupGroup`: its title and what it does, with
/// a switch at the end.
struct AviPopupOption: View {
    let title: String
    var detail: String?
    var detailTone: AviPopupNote.Tone = .secondary
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, detailTone: AviPopupNote.Tone = .secondary, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self.detailTone = detailTone
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(detailTone.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A row in an `AviPopupGroup`, as a setting is in Settings: what it is on
/// the left, its control or value at the end. `.stacked` puts a wide
/// control, such as a text field, under the label.
struct AviPopupRow<Control: View>: View {
    enum Layout {
        case inline
        case stacked
    }

    let label: String
    var detail: String?
    var detailTone: AviPopupNote.Tone = .secondary
    var layout: Layout = .inline
    @ViewBuilder let control: () -> Control

    init(
        _ label: String,
        detail: String? = nil,
        detailTone: AviPopupNote.Tone = .secondary,
        layout: Layout = .inline,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.label = label
        self.detail = detail
        self.detailTone = detailTone
        self.layout = layout
        self.control = control
    }

    var body: some View {
        Group {
            switch layout {
            case .inline:
                HStack(alignment: .center, spacing: 16) {
                    labels
                        .frame(maxWidth: .infinity, alignment: .leading)
                    control()
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 6) {
                    labels
                    control()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var labels: some View {
        let hasDetail = !(detail ?? "").isEmpty
        return VStack(alignment: .leading, spacing: 2) {
            // A title on its own keeps its width, so a long value, such as
            // a branch name, gives up its middle instead.
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: !hasDetail, vertical: true)
            if let detail, hasDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(detailTone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One of a few choices, as rows in a group: the chosen row is ticked and
/// says what it does. Takes the place of radio buttons.
struct AviPopupChoices<Value: Hashable>: View {
    struct Choice {
        let value: Value
        let title: String
        var detail: String?
    }

    let choices: [Choice]
    @Binding var selection: Value

    var body: some View {
        AviPopupGroup {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                if index > 0 {
                    AviPopupGroupDivider()
                }
                row(choice)
            }
        }
    }

    private func row(_ choice: Choice) -> some View {
        let isSelected = choice.value == selection
        return Button {
            withAnimation(Glass.Motion.snappy) {
                selection = choice.value
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.textTertiary)
                    .frame(height: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(DS.Palette.textPrimary)
                    if isSelected, let detail = choice.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(choice.detail ?? "")
    }
}

/// A line of small print under a control.
struct AviPopupNote: View {
    enum Tone {
        case secondary
        case warning
        case danger

        var color: Color {
            switch self {
            case .secondary: return DS.Palette.textSecondary
            case .warning: return DS.Palette.warning
            case .danger: return DS.Palette.danger
            }
        }
    }

    let text: String
    var tone: Tone = .secondary

    init(_ text: String, tone: Tone = .secondary) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tinted box for what you should know before you click: a warning, or
/// what an option does.
struct AviPopupCallout: View {
    enum Tone {
        case info
        case warning
        case danger

        var color: Color {
            switch self {
            case .info: return DS.Palette.accent
            case .warning: return DS.Palette.warning
            case .danger: return DS.Palette.danger
            }
        }

        var symbol: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning, .danger: return "exclamationmark.triangle.fill"
            }
        }
    }

    let text: String
    var tone: Tone = .info

    init(_ text: String, tone: Tone = .info) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: tone.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(tone == .info ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(shape.fill(tone.color.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// Buttons in sheets, notices, and Settings: flat capsules, as in Rex.
/// Prominent is filled with the accent, red for a destructive role; secondary
/// is a quiet gray pill, red-tinted with red text for a destructive role.
/// Give one its key with `aviKeyboardShortcut(_:)`, not `keyboardShortcut(_:)`.
struct AviPopupButtonStyle: PrimitiveButtonStyle {
    enum Emphasis {
        case prominent
        case secondary
    }

    enum Size {
        case regular
        case small
    }

    var emphasis: Emphasis = .secondary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(AviPopupButtonLook(emphasis: emphasis, size: size))
            .background(AviKeyEquivalentButton(action: configuration.trigger))
    }
}

extension View {
    /// `keyboardShortcut(_:)` for a button in `AviPopupButtonStyle`. SwiftUI
    /// draws the pill itself, so the key is SwiftUI's to route, and a sheet
    /// presented from inside a split view's pane gets it routed to the
    /// window behind it: Return and Escape did nothing in Push. The pill also
    /// puts the key on an AppKit button in its own window, the way the
    /// system buttons carry theirs.
    func aviKeyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        keyboardShortcut(shortcut)
            .environment(\.aviKeyEquivalent, shortcut)
    }

    /// `keyboardShortcut(_:modifiers:)` for a button in `AviPopupButtonStyle`.
    func aviKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        aviKeyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }
}

private struct AviKeyEquivalentKey: EnvironmentKey {
    static let defaultValue: KeyboardShortcut? = nil
}

extension EnvironmentValues {
    /// Set by `aviKeyboardShortcut(_:)` for the pill under it.
    var aviKeyEquivalent: KeyboardShortcut? {
        get { self[AviKeyEquivalentKey.self] }
        set { self[AviKeyEquivalentKey.self] = newValue }
    }
}

/// The pill's key as an AppKit button behind it: it draws nothing and takes
/// no clicks, focus, or VoiceOver, and presses the pill's action when its
/// window gets the key, unless the pill is disabled.
private struct AviKeyEquivalentButton: View {
    let action: () -> Void

    @Environment(\.aviKeyEquivalent) private var shortcut
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if let shortcut {
            KeyEquivalentButton(shortcut: shortcut, isEnabled: isEnabled, action: action)
        }
    }
}

private struct KeyEquivalentButton: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSButton {
        let button = PassThroughButton(title: "", target: context.coordinator, action: #selector(Coordinator.press))
        button.isBordered = false
        button.isTransparent = true
        button.refusesFirstResponder = true
        button.setAccessibilityElement(false)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.keyEquivalent = String(shortcut.key.character)
        button.keyEquivalentModifierMask = NSEvent.ModifierFlags(shortcut.modifiers)
        button.isEnabled = isEnabled
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void = {}

        @objc func press() {
            action()
        }
    }

    /// Clicks land on the pill in front of it.
    private final class PassThroughButton: NSButton {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: EventModifiers) {
        self = []
        if modifiers.contains(.command) {
            insert(.command)
        }
        if modifiers.contains(.shift) {
            insert(.shift)
        }
        if modifiers.contains(.option) {
            insert(.option)
        }
        if modifiers.contains(.control) {
            insert(.control)
        }
    }
}

/// The pill itself, drawn for `AviPopupButtonStyle`.
private struct AviPopupButtonLook: ButtonStyle {
    let emphasis: AviPopupButtonStyle.Emphasis
    let size: AviPopupButtonStyle.Size

    func makeBody(configuration: Configuration) -> some View {
        AviPopupButtonBody(configuration: configuration, emphasis: emphasis, size: size)
    }
}

extension PrimitiveButtonStyle where Self == AviPopupButtonStyle {
    /// The sheet's action: accent-filled, or red with a destructive role.
    static var aviProminent: AviPopupButtonStyle {
        AviPopupButtonStyle(emphasis: .prominent)
    }

    /// Cancel and the other quiet buttons of a sheet.
    static var aviSecondary: AviPopupButtonStyle {
        AviPopupButtonStyle(emphasis: .secondary)
    }
}

private struct AviPopupButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let emphasis: AviPopupButtonStyle.Emphasis
    let size: AviPopupButtonStyle.Size

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: size == .small ? 12 : 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, size == .small ? 11 : 15)
            .frame(minWidth: size == .small ? 0 : 72)
            .frame(height: size == .small ? 24 : 28)
            .foregroundStyle(foreground)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Glass.Motion.snappy, value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }

    private var isDestructive: Bool {
        configuration.role == .destructive
    }

    private var isActive: Bool {
        isEnabled && (isHovering || configuration.isPressed)
    }

    private var fill: Color {
        switch emphasis {
        case .prominent:
            let base = isDestructive ? DS.Palette.danger : DS.Palette.accent
            return configuration.isPressed ? base.opacity(0.8) : (isActive ? base.opacity(0.9) : base)
        case .secondary:
            let base = isDestructive ? DS.Palette.danger : Color.primary
            let rest = isDestructive ? 0.14 : 0.08
            return base.opacity(configuration.isPressed ? rest + 0.08 : (isActive ? rest + 0.04 : rest))
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .prominent:
            return DS.Palette.textOnAccent
        case .secondary:
            return isDestructive ? DS.Palette.danger : DS.Palette.textPrimary
        }
    }
}
