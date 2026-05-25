import SwiftUI

enum AviButtonVariant {
    case primary
    case secondary
    case ghost
    case iconOnly
    case destructive
}

enum AviButtonSize {
    case small
    case medium
}

struct AviButton: View {
    let variant: AviButtonVariant
    let size: AviButtonSize
    let icon: String?
    let title: String?
    var isActive: Bool = false
    var isLoading: Bool = false
    var accessibilityLabel: String?
    let action: () -> Void

    @Environment(\.aviDensity) private var density
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(
        _ title: String? = nil,
        icon: String? = nil,
        variant: AviButtonVariant = .secondary,
        size: AviButtonSize = .medium,
        isActive: Bool = false,
        isLoading: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.size = size
        self.isActive = isActive
        self.isLoading = isLoading
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .medium))
                }
                if let title {
                    Text(title)
                        .font(textFont)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: heightValue)
            .frame(minWidth: variant == .iconOnly ? heightValue : nil)
            .background(backgroundShape)
            .overlay(borderShape)
            .foregroundStyle(foregroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title ?? "")
    }

    private var heightValue: CGFloat {
        switch size {
        case .small: return 22
        case .medium: return 26
        }
    }

    private var horizontalPadding: CGFloat {
        if variant == .iconOnly { return 0 }
        return size == .small ? DS.Spacing.lg - 2 : DS.Spacing.lg
    }

    private var iconSize: CGFloat {
        size == .small ? DS.IconScale.md : DS.IconScale.md
    }

    private var textFont: Font {
        switch size {
        case .small: return .system(size: 11, weight: .medium)
        case .medium: return DS.Font.bodyMedium(density)
        }
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch variant {
        case .primary:
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .fill(isHovering && isEnabled ? DS.Palette.accentEmphasis.opacity(0.9) : DS.Palette.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .fill(Glass.topHighlight)
                )
        case .secondary:
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .fill(.thinMaterial)
                .opacity(isActive || isHovering && isEnabled ? 1 : 0.65)
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                            .fill(DS.Palette.accent.opacity(0.25))
                    } else if isHovering, isEnabled {
                        RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                            .fill(Glass.hoverTint())
                    }
                }
        case .ghost:
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .fill(isActive ? DS.Palette.accent : (isHovering && isEnabled ? DS.Palette.rowHoverFill : Color.clear))
        case .iconOnly:
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(isHovering && isEnabled ? DS.Palette.rowHoverFill : Color.clear)
        case .destructive:
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .fill(isHovering && isEnabled ? DS.Palette.danger.opacity(0.9) : DS.Palette.danger)
                .overlay(
                    RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                        .fill(Glass.topHighlight)
                )
        }
    }

    @ViewBuilder
    private var borderShape: some View {
        switch variant {
        case .secondary:
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .strokeBorder(Glass.edgeStroke, lineWidth: 0.6)
        case .primary, .destructive:
            RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
        default:
            EmptyView()
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .destructive:
            return DS.Palette.textOnAccent
        case .secondary, .ghost, .iconOnly:
            return isActive ? DS.Palette.textOnAccent : DS.Palette.textPrimary
        }
    }
}
