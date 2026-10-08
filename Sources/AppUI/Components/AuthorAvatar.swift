import SwiftUI

/// An author's picture in a rounded square, or their initials on a color of
/// their own until the picture arrives, or when there is none. Settings >
/// Appearance > Author pictures off keeps it to initials and asks no server.
struct AuthorAvatar: View {
    let name: String
    let email: String
    let size: CGFloat
    /// Commits by this author the repository's forge can be asked about.
    var commits: [String] = []
    var origin: AvatarOrigin?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size / 5, style: .continuous)
        ZStack {
            shape.fill(tint)
            Text(AvatarSource.initials(for: name))
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
            if let image = AvatarStore.shared.image(for: email) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
        .task(id: email) {
            guard ConfigStore.shared.config.appearance.authorPictures else { return }
            await AvatarStore.shared.load(email: email, commits: commits, origin: origin, pixels: Int(size * max(displayScale, 2)))
        }
    }

    /// The same color for the same address everywhere.
    private var tint: Color {
        HistoryGraphPalette.color(for: "author:" + AvatarSource.normalized(email))
    }
}
