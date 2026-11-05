import AppKit
import SwiftUI

/// One value from a list, as a flat pill with a chevron in place of a
/// pop-up button. A click opens the list as a menu under the pill, the
/// chosen value ticked. The pill hugs its value up to `maxWidth` and gives
/// up the middle of a longer one, so a long branch name never widens the
/// sheet around it.
struct AviPopupMenu: View {
    let label: String
    let options: [String]
    @Binding var selection: String
    var symbol: String?
    var placeholder = "None"
    var maxWidth: CGFloat = 220

    @State private var anchor = AviMenuAnchor()
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    init(
        _ label: String,
        options: [String],
        selection: Binding<String>,
        symbol: String? = nil,
        placeholder: String = "None",
        maxWidth: CGFloat = 220
    ) {
        self.label = label
        self.options = options
        _selection = selection
        self.symbol = symbol
        self.placeholder = placeholder
        self.maxWidth = maxWidth
    }

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Text(selection.isEmpty ? placeholder : selection)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.leading, symbol == nil ? 11 : 9)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.primary.opacity(isHovering && isEnabled ? 0.12 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Its value's width, at most `maxWidth`, whatever the row offers.
        .fixedSize()
        .background(AviMenuAnchorView(anchor: anchor))
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .help(selection)
        .accessibilityLabel(label)
        .accessibilityValue(selection.isEmpty ? placeholder : selection)
        .accessibilityHint("Opens a menu")
    }

    private func showMenu() {
        guard let view = anchor.view, !options.isEmpty else { return }
        let menu = Self.menu(options: options, selection: selection) { selection = $0 }
        menu.minimumWidth = view.bounds.width
        // Under the pill, its first item in line with the pill's text.
        let below = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: view)
    }

    /// The menu a click opens: one item per option, the chosen one ticked.
    static func menu(options: [String], selection: String, choose: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for option in options {
            let item = AviMenuItem(title: option) { choose(option) }
            item.state = option == selection ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
}

/// A menu item that runs its own closure.
final class AviMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func choose() {
        handler()
    }
}

/// The AppKit view under a pill that its menu opens from.
@MainActor
final class AviMenuAnchor {
    weak var view: NSView?
}

private struct AviMenuAnchorView: NSViewRepresentable {
    let anchor: AviMenuAnchor

    func makeNSView(context _: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        anchor.view = view
    }

    /// Clicks land on the pill in front of it.
    private final class PassThroughView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

/// The well a sheet's text field or editor sits in: a shade off the card,
/// a hairline around it, and the accent around it while you type.
private struct AviFieldWell: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .background(shape.fill(Color(nsColor: .textBackgroundColor).opacity(0.55)))
            .overlay(
                shape.strokeBorder(
                    isFocused ? DS.Palette.accent.opacity(0.85) : Color.primary.opacity(0.1),
                    lineWidth: isFocused ? 1.5 : 1
                )
            )
            .animation(Glass.Motion.snappy, value: isFocused)
    }
}

/// A one-line text field in a sheet, drawn flat, with an optional control
/// at its end, such as a menu of suggestions.
struct AviPopupTextField<Accessory: View>: View {
    let label: String
    @Binding var text: String
    var prompt: String?
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(label, text: $text, prompt: prompt.map { Text($0) })
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .accessibilityLabel(label)
            accessory()
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .modifier(AviFieldWell(isFocused: isFocused))
    }
}

extension AviPopupTextField where Accessory == EmptyView {
    init(_ label: String, text: Binding<String>, prompt: String? = nil) {
        self.init(label: label, text: text, prompt: prompt) {
            EmptyView()
        }
    }
}

/// A few lines of text in a sheet, drawn as `AviPopupTextField` is.
struct AviPopupTextEditor: View {
    let label: String
    @Binding var text: String
    var height: CGFloat = 110

    @FocusState private var isFocused: Bool

    init(_ label: String, text: Binding<String>, height: CGFloat = 110) {
        self.label = label
        _text = text
        self.height = height
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .modifier(AviFieldWell(isFocused: isFocused))
            .accessibilityLabel(label)
    }
}
