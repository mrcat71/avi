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
                .font(DS.Font.captionStrong(density))
                .foregroundStyle(DS.Palette.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(Array(breadcrumb.enumerated()), id: \.offset) { _, segment in
                Text("·")
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(segment)
                    .font(DS.Font.caption(density))
                    .foregroundStyle(DS.Palette.textSecondary)
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
        self.trailing = EmptyView()
    }
}
