import SwiftUI

/// Standard visual treatments for ref labels (branch, remote branch, tag, current)
/// plus the small numeric count chip used in sidebar items and toolbar buttons.
struct AviBadge: View {
    enum Kind {
        case localBranch
        case currentBranch
        case remoteBranch
        case tag
        case count
        case ahead(Int)
        case behind(Int)
        case synced
        case info // generic neutral chip
        case warning
    }

    let kind: Kind
    let text: String
    var icon: String?
    var isSelected: Bool = false

    @Environment(\.aviDensity) private var density

    init(_ kind: Kind, text: String, icon: String? = nil, isSelected: Bool = false) {
        self.kind = kind
        self.text = text
        self.icon = icon ?? defaultIcon(for: kind)
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.IconScale.xs, weight: .semibold))
            }
            Text(text)
                .font(font)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, paddingH)
        .padding(.vertical, paddingV)
        .background(background)
        .overlay(border)
        .foregroundStyle(foreground)
    }

    private var font: Font {
        switch kind {
        case .ahead, .behind, .synced, .count:
            return .system(size: DS.IconScale.sm, weight: .semibold, design: .monospaced)
        case .tag:
            return .system(size: 10, weight: .medium, design: .monospaced)
        default:
            return .system(size: 10, weight: .semibold)
        }
    }

    private var paddingH: CGFloat {
        switch kind {
        case .count: return 5
        default: return 5
        }
    }

    private var paddingV: CGFloat {
        1
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .currentBranch:
            Capsule().fill(tint)
        case .tag:
            Capsule().fill(tint.opacity(0.18))
        case .remoteBranch:
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(Color.clear)
        case .ahead, .behind, .synced, .info, .warning:
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(tint.opacity(0.16))
        case .count:
            Capsule().fill(isSelected ? Color.white.opacity(0.25) : Color.primary.opacity(0.10))
        case .localBranch:
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(tint.opacity(0.18))
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .remoteBranch:
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(tint.opacity(0.55), lineWidth: 1)
        case .currentBranch:
            Capsule().stroke(tint, lineWidth: 0.5)
        case .tag:
            Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5)
        case .localBranch:
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(tint.opacity(0.32), lineWidth: 0.5)
        default:
            EmptyView()
        }
    }

    private var tint: Color {
        switch kind {
        case .localBranch: return DS.Palette.infoBlue
        case .currentBranch: return DS.Palette.accent
        case .remoteBranch: return DS.Palette.infoPurple
        case .tag: return DS.Palette.infoOrange
        case .ahead: return DS.Palette.success
        case .behind: return DS.Palette.infoBlue
        case .synced: return DS.Palette.success
        case .info: return DS.Palette.textSecondary
        case .warning: return DS.Palette.warning
        case .count: return DS.Palette.textSecondary
        }
    }

    private var foreground: Color {
        if isSelected {
            switch kind {
            case .currentBranch: return DS.Palette.textOnAccent
            case .count: return DS.Palette.textOnAccent
            default: return DS.Palette.textOnAccent.opacity(0.9)
            }
        }
        switch kind {
        case .currentBranch: return DS.Palette.textOnAccent
        case .count: return DS.Palette.textSecondary
        default: return tint
        }
    }

    private func defaultIcon(for kind: Kind) -> String? {
        switch kind {
        case .localBranch: return "arrow.triangle.branch"
        case .currentBranch: return "checkmark"
        case .remoteBranch: return "network"
        case .tag: return "tag.fill"
        case .ahead, .behind, .synced, .count, .info, .warning: return nil
        }
    }
}
