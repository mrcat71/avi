import SwiftUI

/// Header strip at the top of a panel: title, optional breadcrumb segments,
/// and an optional trailing slot for action buttons or menus.
struct AviPanelHeader<Trailing: View>: View {
    let title: String
    var breadcrumb: [String] = []
    let trailing: Trailing

    @Environment(\.aviDensity) private var density

    init(_ title: String, breadcrumb: [String] = [], @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Text(title)
                .aviLabel(density)

            // Segments can be ref names, so they keep their case.
            ForEach(Array(breadcrumb.enumerated()), id: \.offset) { _, segment in
                Text("·")
                    .font(DS.Font.label(density))
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(segment)
                    .font(DS.Font.label(density))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, DS.Spacing.xl)
        .frame(height: DS.RowHeight.panelHeader(density))
    }
}

extension AviPanelHeader where Trailing == EmptyView {
    init(_ title: String, breadcrumb: [String] = []) {
        self.title = title
        self.breadcrumb = breadcrumb
        trailing = EmptyView()
    }
}
