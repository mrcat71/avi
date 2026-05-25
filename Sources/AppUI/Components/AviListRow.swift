import SwiftUI

/// Selectable, hoverable row. Single source of styling so sidebar / history / file lists
/// all match. Use the `.compact` size for sidebar ref trees, `.standard` for primary nav,
/// `.comfortable` for history rows.
struct AviListRow<Content: View>: View {
    enum Size {
        case compact
        case standard
        case comfortable
    }

    let isSelected: Bool
    var isCurrentBranch: Bool = false
    var size: Size = .standard
    var onTap: (() -> Void)?
    let content: Content

    @Environment(\.aviDensity) private var density
    @State private var isHovering = false

    init(
        isSelected: Bool,
        isCurrentBranch: Bool = false,
        size: Size = .standard,
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isCurrentBranch = isCurrentBranch
        self.size = size
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, DS.Spacing.lg - 2)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Glass.Corner.inline, style: .continuous)
                if isSelected {
                    shape.fill(DS.Palette.accent)
                        .overlay(shape.fill(Glass.topHighlight))
                } else if isCurrentBranch {
                    shape.fill(DS.Palette.accent.opacity(0.18))
                } else if isHovering {
                    shape.fill(.thinMaterial)
                        .overlay(shape.fill(Glass.hoverTint()))
                } else {
                    shape.fill(Color.clear)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .onHover { isHovering = $0 }
            .animation(Glass.Motion.snappy, value: isHovering)
    }

    private var rowHeight: CGFloat {
        switch size {
        case .compact: return DS.RowHeight.compact(density)
        case .standard: return DS.RowHeight.standard(density)
        case .comfortable: return DS.RowHeight.standard(density) + 4
        }
    }
}
