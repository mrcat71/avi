import SwiftUI

/// Sidebar section header with optional disclosure chevron + count + trailing actions.
struct AviSectionHeader<Trailing: View>: View {
    let title: String
    var count: Int?
    var isExpanded: Binding<Bool>?
    let trailing: Trailing

    @Environment(\.aviDensity) private var density

    init(
        _ title: String,
        count: Int? = nil,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.count = count
        self.isExpanded = isExpanded
        self.trailing = trailing()
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: DS.Spacing.sm) {
                if let isExpanded {
                    Image(systemName: "chevron.right")
                        .font(.system(size: DS.IconScale.xs, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                Text(title)
                    .font(DS.Font.captionStrong(density))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: DS.IconScale.sm, weight: .medium))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer()
                trailing
            }
            .padding(.horizontal, DS.Spacing.xl)
            .frame(height: DS.RowHeight.panelHeader(density) - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isExpanded == nil)
    }

    private func toggle() {
        guard let isExpanded else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            isExpanded.wrappedValue.toggle()
        }
    }
}

extension AviSectionHeader where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil, isExpanded: Binding<Bool>? = nil) {
        self.title = title
        self.count = count
        self.isExpanded = isExpanded
        trailing = EmptyView()
    }
}
