import SwiftUI

/// Centered empty-state view with an icon, headline, optional secondary text,
/// and an optional vertical button stack of actions.
struct AviEmptyState<Actions: View>: View {
    let icon: String
    let title: String
    var message: String?
    var iconTint: Color = DS.Palette.textTertiary
    let actions: Actions

    @Environment(\.aviDensity) private var density

    init(
        icon: String,
        title: String,
        message: String? = nil,
        iconTint: Color = DS.Palette.textTertiary,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconTint = iconTint
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(iconTint)

            VStack(spacing: DS.Spacing.sm) {
                Text(title)
                    .font(DS.Font.bodyBold(density))
                    .foregroundStyle(DS.Palette.textPrimary)
                if let message {
                    Text(message)
                        .font(DS.Font.body(density))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: DS.Spacing.sm) {
                actions
            }
            .frame(maxWidth: 220)
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AviEmptyState where Actions == EmptyView {
    init(
        icon: String,
        title: String,
        message: String? = nil,
        iconTint: Color = DS.Palette.textTertiary
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconTint = iconTint
        actions = EmptyView()
    }
}
