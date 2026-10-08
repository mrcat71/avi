import SwiftUI

/// Standard visual treatments for ref labels (branch, remote branch, tag, current)
/// plus the small numeric count chip used in sidebar items and toolbar buttons.
/// Ref labels are neutral chips with a colored mark, so a branch chip can carry
/// its commit-graph lane color through `tint`.
struct AviBadge: View {
    enum Kind: Equatable {
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
    var tintOverride: Color?
    var isSelected: Bool = false

    @Environment(\.aviDensity) private var density

    init(_ kind: Kind, text: String, icon: String? = nil, tint: Color? = nil, isSelected: Bool = false) {
        self.kind = kind
        self.text = text
        self.icon = icon ?? defaultIcon(for: kind)
        tintOverride = tint
        self.isSelected = isSelected
    }

    var body: some View {
        if isRef {
            refChip
        } else {
            chip
        }
    }

    private var isRef: Bool {
        switch kind {
        case .localBranch, .currentBranch, .remoteBranch, .tag: return true
        default: return false
        }
    }

    /// Branch and tag label: mark + monospaced name on a hairline pill.
    private var refChip: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md - 1, style: .continuous)
        return HStack(spacing: 4) {
            refMark
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(kind == .remoteBranch ? DS.Palette.textSecondary : DS.Palette.textPrimary)
        }
        .padding(.leading, 5)
        .padding(.trailing, 6)
        .padding(.vertical, 1.5)
        .background(shape.fill(kind == .currentBranch ? tint.opacity(0.2) : Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(kind == .currentBranch ? tint.opacity(0.6) : Color.primary.opacity(0.14), lineWidth: 0.5))
    }

    @ViewBuilder
    private var refMark: some View {
        switch kind {
        case .localBranch:
            Circle().fill(tint).frame(width: 6, height: 6)
        case .currentBranch:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(tint)
        default:
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(kind == .remoteBranch ? DS.Palette.textSecondary : tint)
            }
        }
    }

    private var chip: some View {
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
        if let tintOverride {
            return tintOverride
        }
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
